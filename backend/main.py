import os
import shutil
import threading
import time
import uuid
import urllib.request
import urllib.parse
import json
from pathlib import Path
from typing import Literal

import yt_dlp
from yt_dlp.utils import DownloadError
from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel
import traceback

app = FastAPI()

BASE_DIR = Path(__file__).resolve().parent
cookies_file = BASE_DIR / "cookies.txt"
downloads_dir = BASE_DIR / "downloads"
downloads_dir.mkdir(exist_ok=True)

# Startup logic: check if YOUTUBE_COOKIES_CONTENT env var is set and write to cookies.txt
cookies_content = os.getenv("YOUTUBE_COOKIES_CONTENT")
if cookies_content:
    try:
        cookies_file.write_text(cookies_content.strip() + "\n", encoding="utf-8")
        print(f"Successfully wrote YOUTUBE_COOKIES_CONTENT to cookies.txt ({len(cookies_content)} characters)")
    except Exception as e:
        print(f"Error writing YOUTUBE_COOKIES_CONTENT to cookies.txt: {e}")
else:
    print("YOUTUBE_COOKIES_CONTENT environment variable is NOT set.")

if cookies_file.exists():
    print(f"Cookies file found at: {cookies_file.absolute()} (size: {cookies_file.stat().st_size} bytes)")
else:
    print(f"No cookies file found at: {cookies_file.absolute()}. Operating in cookie-less mode.")

allowed_origins_env = os.getenv("ALLOWED_ORIGINS", "")
allowed_origins = [origin.strip() for origin in allowed_origins_env.split(",") if origin.strip()]
allow_credentials = bool(allowed_origins)

if not allowed_origins:
    allowed_origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

jobs = {}
jobs_lock = threading.Lock()
media_types = {
    "mp3": "audio/mpeg",
    "mp4": "video/mp4",
}


class DownloadRequest(BaseModel):
    url: str
    format_type: Literal["mp3", "mp4"] = "mp3"
    quality: Literal["128", "192", "256", "320"] = "192"
    concurrent_threads: int = 1


class PlaylistDownloadRequest(BaseModel):
    url: str
    format_type: Literal["mp3", "mp4"] = "mp3"
    quality: Literal["128", "192", "256", "320"] = "192"
    concurrent_threads: int = 1


def require_binary(binary_name, detail):
    if shutil.which(binary_name):
        return

    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail=detail,
    )


def download_task(job_id, url, format_type, quality, concurrent_threads=1):
    final_file_path = {"path": ""}

    def progress_hook(d):
        with jobs_lock:
            job = jobs.get(job_id)

        if not job:
            return

        if job.get("cancelled"):
            raise DownloadError("Cancelled")

        if d['status'] == 'downloading':
            downloaded = d.get('downloaded_bytes', 0)
            total = d.get('total_bytes') or d.get('total_bytes_estimate')
            speed = d.get('speed', 0)
            eta = d.get('eta', 0)

            percent = 0
            if total:
                percent = (downloaded / total) * 100

            with jobs_lock:
                job.update({
                    "status": "downloading",
                    "progress": round(percent, 2),
                    "downloaded": downloaded,
                    "total": total,
                    "speed": speed,
                    "eta": eta
                })

        elif d['status'] == 'finished':
            with jobs_lock:
                job["status"] = "processing"
                job["progress"] = 95

            final_file_path["path"] = d.get("filename")

    ydl_opts = {
        "progress_hooks": [progress_hook],
        "outtmpl": str(downloads_dir / f"%(title)s-{job_id}.%(ext)s"),
        "restrictfilenames": True,
        "js_runtimes": {"deno": {}, "node": {}},
        "concurrent_fragment_downloads": concurrent_threads,
    }

    if cookies_file.exists():
        ydl_opts["cookiefile"] = str(cookies_file)
        ydl_opts["remote_components"] = ["ejs:github"]

    if format_type == "mp3":
        ydl_opts.update({
            "format": "bestaudio/best",
            "postprocessors": [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": quality,
            }],
        })
    else:
        ydl_opts.update({
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "merge_output_format": "mp4",
        })

    retries = 1
    while retries >= 0:
        try:
            with yt_dlp.YoutubeDL(dict(ydl_opts)) as ydl:  # type: ignore
                ydl.download([url])

            file_path = final_file_path["path"]

            if format_type == "mp3" and file_path:
                base, _ = os.path.splitext(file_path)
                file_path = base + ".mp3"

            for _ in range(12):
                if file_path and os.path.exists(file_path):
                    break
                time.sleep(0.5)

            if not file_path or not os.path.exists(file_path):
                raise FileNotFoundError("Downloaded file was not created.")

            with jobs_lock:
                jobs[job_id].update({
                    "status": "completed",
                    "progress": 100,
                    "filename": file_path,
                    "format_type": format_type,
                })
            break

        except (DownloadError, Exception) as e:
            is_416 = "416" in str(e) or "Range Not Satisfiable" in str(e)
            if is_416 and retries > 0:
                print(f"Caught 416 error for job {job_id}. Clearing partial files and retrying from scratch...")
                retries -= 1
                try:
                    for f in downloads_dir.glob(f"*{job_id}*"):
                        if f.exists():
                            f.unlink()
                except Exception as delete_err:
                    print(f"Error deleting partial files for job {job_id}: {delete_err}")
                continue

            is_cancelled = "Cancelled" in str(e)
            with jobs_lock:
                if is_cancelled:
                    if jobs[job_id]["status"] == "paused":
                        pass
                    else:
                        jobs[job_id]["status"] = "cancelled"
                else:
                    jobs[job_id]["status"] = "error"
                    err_msg = str(e)
                    if cookies_file.exists():
                        err_msg += f" (Cookies file size: {cookies_file.stat().st_size} bytes)"
                    else:
                        err_msg += " (No cookies file found)"
                    jobs[job_id]["error"] = err_msg
            break


@app.get("/search")
def search_videos(query: str):
    query = query.strip()
    if not query:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"error": "Query is required."},
        )

    if not shutil.which("node"):
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"error": "Node.js is required on the backend for search requests."},
        )

    try:
        ydl_opts = {
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "extract_flat": True,
            "js_runtimes": {"deno": {}, "node": {}},
        }

        if cookies_file.exists():
            ydl_opts["cookiefile"] = str(cookies_file)
            ydl_opts["remote_components"] = ["ejs:github"]

        with yt_dlp.YoutubeDL(dict(ydl_opts)) as ydl:  # type: ignore
            search_data = ydl.extract_info(f"ytsearch10:{query}", download=False) or {}

        entries = search_data.get("entries") or []
        results = []

        for v in entries:
            if not v:
                continue

            thumbnail = v.get("thumbnail") or ""
            if not thumbnail:
                thumbnails = v.get("thumbnails") or []
                if thumbnails:
                    thumbnail = thumbnails[-1].get("url") or ""

            webpage_url = v.get("webpage_url")
            ie_key = (v.get("ie_key") or v.get("_type") or "").lower()
            entry_type = "video"

            # Detect playlist-type results
            if ie_key in ("youtubeplaylist", "youtubetab", "playlist") or v.get("_type") == "playlist":
                entry_type = "playlist"
                if not webpage_url and v.get("id"):
                    webpage_url = f"https://www.youtube.com/playlist?list={v['id']}"
            else:
                if not webpage_url and v.get("id"):
                    webpage_url = f"https://www.youtube.com/watch?v={v['id']}"

            result_entry = {
                "title": v.get("title") or "No title",
                "thumbnail": thumbnail,
                "url": webpage_url or "",
                "duration": v.get("duration"),
                "uploader": v.get("uploader") or v.get("channel") or "Unknown",
                "type": entry_type,
            }

            # Add video count for playlists if available
            if entry_type == "playlist":
                result_entry["video_count"] = v.get("playlist_count") or v.get("n_entries")

            results.append(result_entry)

        return {"results": results}

    except Exception as e:
        traceback.print_exc()
        err_msg = str(e)
        if cookies_file.exists():
            err_msg += f" (Cookies file size: {cookies_file.stat().st_size} bytes)"
        else:
            err_msg += " (No cookies file found)"
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"error": err_msg},
        )

@app.get("/info")
def get_video_info(url: str):
    url = url.strip()
    if not url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="URL is required.",
        )

    if not shutil.which("node"):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Node.js is required on the backend for info requests.",
        )

    try:
        ydl_opts = {
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "js_runtimes": {"deno": {}, "node": {}},
        }

        if cookies_file.exists():
            ydl_opts["cookiefile"] = str(cookies_file)
            ydl_opts["remote_components"] = ["ejs:github"]

        with yt_dlp.YoutubeDL(dict(ydl_opts)) as ydl:  # type: ignore
            v = ydl.extract_info(url, download=False) or {}

        thumbnail = v.get("thumbnail") or ""
        if not thumbnail:
            thumbnails = v.get("thumbnails") or []
            if thumbnails:
                thumbnail = thumbnails[-1].get("url") or ""

        return {
            "title": v.get("title") or "No title",
            "thumbnail": thumbnail,
            "url": v.get("webpage_url") or url,
            "duration": v.get("duration"),
            "uploader": v.get("uploader") or v.get("channel") or "Unknown",
        }

    except Exception as e:
        traceback.print_exc()
        err_msg = str(e)
        if cookies_file.exists():
            err_msg += f" (Cookies file size: {cookies_file.stat().st_size} bytes)"
        else:
            err_msg += " (No cookies file found)"
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=err_msg,
        )


@app.get("/playlist")
def get_playlist_info(url: str):
    url = url.strip()
    if not url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="URL is required.",
        )

    if not shutil.which("node"):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Node.js is required on the backend for playlist requests.",
        )

    try:
        ydl_opts = {
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "extract_flat": True,
            "js_runtimes": {"deno": {}, "node": {}},
        }

        if cookies_file.exists():
            ydl_opts["cookiefile"] = str(cookies_file)
            ydl_opts["remote_components"] = ["ejs:github"]

        with yt_dlp.YoutubeDL(dict(ydl_opts)) as ydl:  # type: ignore
            playlist_data = ydl.extract_info(url, download=False) or {}

        # Get playlist-level thumbnail
        playlist_thumbnail = playlist_data.get("thumbnail") or ""
        if not playlist_thumbnail:
            thumbnails = playlist_data.get("thumbnails") or []
            if thumbnails:
                playlist_thumbnail = thumbnails[-1].get("url") or ""

        entries_raw = playlist_data.get("entries") or []
        entries = []

        for v in entries_raw:
            if not v:
                continue

            thumb = v.get("thumbnail") or ""
            if not thumb:
                thumbs = v.get("thumbnails") or []
                if thumbs:
                    thumb = thumbs[-1].get("url") or ""

            webpage_url = v.get("webpage_url")
            if not webpage_url and v.get("id"):
                webpage_url = f"https://www.youtube.com/watch?v={v['id']}"

            entries.append({
                "title": v.get("title") or "No title",
                "thumbnail": thumb,
                "url": webpage_url or "",
                "duration": v.get("duration"),
                "uploader": v.get("uploader") or v.get("channel") or playlist_data.get("uploader") or "Unknown",
            })

        # Use first entry thumbnail as fallback for playlist thumbnail
        if not playlist_thumbnail and entries:
            playlist_thumbnail = entries[0].get("thumbnail", "")

        return {
            "title": playlist_data.get("title") or "Unknown Playlist",
            "thumbnail": playlist_thumbnail,
            "uploader": playlist_data.get("uploader") or playlist_data.get("channel") or "Unknown",
            "video_count": len(entries),
            "url": playlist_data.get("webpage_url") or url,
            "entries": entries,
        }

    except Exception as e:
        traceback.print_exc()
        err_msg = str(e)
        if cookies_file.exists():
            err_msg += f" (Cookies file size: {cookies_file.stat().st_size} bytes)"
        else:
            err_msg += " (No cookies file found)"
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=err_msg,
        )


@app.post("/download-playlist")
def download_playlist(request: PlaylistDownloadRequest):
    url = request.url.strip()
    if not url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A playlist URL is required.",
        )

    if request.concurrent_threads < 1 or request.concurrent_threads > 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="concurrent_threads must be between 1 and 8.",
        )

    require_binary("node", "Node.js is required on the backend for download requests.")

    if request.format_type == "mp3":
        require_binary("ffmpeg", "FFmpeg is required on the backend for mp3 downloads.")

    # First extract the playlist info to get individual video URLs
    try:
        ydl_opts = {
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "extract_flat": True,
            "js_runtimes": {"deno": {}, "node": {}},
        }

        if cookies_file.exists():
            ydl_opts["cookiefile"] = str(cookies_file)
            ydl_opts["remote_components"] = ["ejs:github"]

        with yt_dlp.YoutubeDL(dict(ydl_opts)) as ydl:  # type: ignore
            playlist_data = ydl.extract_info(url, download=False) or {}

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to extract playlist: {str(e)}",
        )

    entries = playlist_data.get("entries") or []
    if not entries:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No videos found in this playlist.",
        )

    playlist_id = str(uuid.uuid4())
    playlist_title = playlist_data.get("title") or "Unknown Playlist"
    job_ids = []

    # Limit to prevent overloading the server
    max_tracks = 50

    with jobs_lock:
        active_jobs = sum(
            1 for j in jobs.values()
            if j.get("status") in {"starting", "downloading", "processing"}
        )
        # Allow up to 30 concurrent active jobs total in the system
        allowed_slots = max(0, 30 - active_jobs)
        if allowed_slots == 0:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many active downloads. Please wait for current downloads to finish.",
            )

        # Dynamically slice entries to fit within the allowed active job slots
        entries = entries[:min(max_tracks, allowed_slots)]

    for v in entries:
        if not v:
            continue

        video_url = v.get("webpage_url")
        if not video_url and v.get("id"):
            video_url = f"https://www.youtube.com/watch?v={v['id']}"

        if not video_url:
            continue

        job_id = str(uuid.uuid4())
        video_title = v.get("title") or "No title"

        with jobs_lock:
            jobs[job_id] = {
                "status": "starting",
                "progress": 0,
                "downloaded": 0,
                "total": 0,
                "speed": 0,
                "eta": 0,
                "cancelled": False,
                "url": video_url,
                "filename": "",
                "format_type": request.format_type,
                "quality": request.quality,
                "concurrent_threads": request.concurrent_threads,
                "playlist_id": playlist_id,
                "title": video_title,
            }

        threading.Thread(
            target=download_task,
            args=(job_id, video_url, request.format_type, request.quality, request.concurrent_threads),
            daemon=True,
        ).start()

        job_ids.append({
            "job_id": job_id,
            "title": video_title,
            "thumbnail": v.get("thumbnail") or "",
            "uploader": v.get("uploader") or v.get("channel") or playlist_data.get("uploader") or "Unknown",
        })

    return {
        "playlist_id": playlist_id,
        "playlist_title": playlist_title,
        "job_ids": job_ids,
    }


from functools import lru_cache

@lru_cache(maxsize=512)
def fetch_google_suggestions(q: str):
    url = f"https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q={urllib.parse.quote(q)}"
    req = urllib.request.Request(
        url, 
        headers={'User-Agent': 'Mozilla/5.0'}
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        data = json.loads(response.read().decode('utf-8'))
        return data[1] if len(data) > 1 else []


@app.get("/suggest")
def get_suggestions(q: str):
    q = q.strip()
    if not q:
        return {"suggestions": []}
    try:
        suggestions = fetch_google_suggestions(q)
        return {"suggestions": suggestions}
    except Exception as e:
        return {"suggestions": [], "error": str(e)}


@app.post("/download")
def start_download(request: DownloadRequest):
    url = request.url.strip()
    if not url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A video URL is required.",
        )

    if request.concurrent_threads < 1 or request.concurrent_threads > 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="concurrent_threads must be between 1 and 8.",
        )

    # Limit maximum concurrent active downloads to prevent server overload
    with jobs_lock:
        active_jobs = sum(
            1 for j in jobs.values()
            if j.get("status") in {"starting", "downloading", "processing"}
        )
        if active_jobs >= 10:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many active download jobs. Please wait for current downloads to finish."
            )

    require_binary("node", "Node.js is required on the backend for download requests.")

    if request.format_type == "mp3":
        require_binary("ffmpeg", "FFmpeg is required on the backend for mp3 downloads.")

    job_id = str(uuid.uuid4())

    with jobs_lock:
        jobs[job_id] = {
            "status": "starting",
            "progress": 0,
            "downloaded": 0,
            "total": 0,
            "speed": 0,
            "eta": 0,
            "cancelled": False,
            "url": url,
            "filename": "",
            "format_type": request.format_type,
            "quality": request.quality,
            "concurrent_threads": request.concurrent_threads,
        }

    threading.Thread(
        target=download_task,
        args=(job_id, url, request.format_type, request.quality, request.concurrent_threads),
        daemon=True,
    ).start()

    return {"job_id": job_id}


@app.get("/progress/{job_id}")
def get_progress(job_id: str):
    with jobs_lock:
        job = jobs.get(job_id)

    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid job_id",
        )

    return job


@app.post("/cancel/{job_id}")
def cancel_download(job_id: str):
    with jobs_lock:
        job = jobs.get(job_id)
        if not job:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Invalid job_id",
            )

        if job["status"] in {"completed", "error", "cancelled"}:
            return {"message": f"Job already {job['status']}"}

        jobs[job_id]["cancelled"] = True

    return {"message": "Cancelling"}


@app.post("/pause/{job_id}")
def pause_download(job_id: str):
    with jobs_lock:
        job = jobs.get(job_id)
        if not job:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Invalid job_id",
            )

        if job["status"] not in {"starting", "downloading", "processing"}:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Job cannot be paused in {job['status']} state",
            )

        job["status"] = "paused"
        job["cancelled"] = True

    return {"message": "Paused"}


@app.post("/resume/{job_id}")
def resume_download(job_id: str):
    with jobs_lock:
        job = jobs.get(job_id)
        if not job:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Invalid job_id",
            )

        if job["status"] != "paused":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Job is not paused",
            )

        job["status"] = "starting"
        job["cancelled"] = False
        url = job["url"]
        format_type = job["format_type"]
        quality = job.get("quality", "192")
        concurrent_threads = job.get("concurrent_threads", 1)

    threading.Thread(
        target=download_task,
        args=(job_id, url, format_type, quality, concurrent_threads),
        daemon=True,
    ).start()

    return {"message": "Resumed"}


@app.get("/file/{job_id}")
def get_file(job_id: str):
    with jobs_lock:
        job = jobs.get(job_id)

    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid job_id",
        )

    if job["status"] != "completed":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="File not ready",
        )

    file_path = job.get("filename")

    if not file_path or not os.path.exists(file_path):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="File not found",
        )

    # Secure path traversal check: ensure file is strictly inside downloads_dir
    try:
        abs_downloads = os.path.abspath(downloads_dir)
        abs_file = os.path.abspath(file_path)
        if os.path.commonpath([abs_downloads, abs_file]) != abs_downloads:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied: File is outside the downloads directory."
            )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied: Invalid file path."
        )

    format_type = job.get("format_type", "mp3")

    return FileResponse(
        file_path,
        media_type=media_types.get(format_type, "application/octet-stream"),
        filename=os.path.basename(file_path)
    )
