import os
import shutil
import threading
import time
import uuid
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

downloads_dir = Path("downloads")
downloads_dir.mkdir(exist_ok=True)

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


def require_binary(binary_name, detail):
    if shutil.which(binary_name):
        return

    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail=detail,
    )


def download_task(job_id, url, format_type, quality):
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
        "js_runtimes": {"node": {}},
    }

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

    except DownloadError as e:
        with jobs_lock:
            if "Cancelled" in str(e):
                jobs[job_id]["status"] = "cancelled"
            else:
                jobs[job_id]["status"] = "error"
                jobs[job_id]["error"] = str(e)

    except Exception as e:
        with jobs_lock:
            jobs[job_id]["status"] = "error"
            jobs[job_id]["error"] = str(e)


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
            "noplaylist": True,
            "js_runtimes": {"node": {}},
        }

        with yt_dlp.YoutubeDL(dict(ydl_opts)) as ydl:  # type: ignore
            search_data = ydl.extract_info(f"ytsearch5:{query}", download=False) or {}

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
            if not webpage_url and v.get("id"):
                webpage_url = f"https://www.youtube.com/watch?v={v['id']}"

            results.append({
                "title": v.get("title") or "No title",
                "thumbnail": thumbnail,
                "url": webpage_url or "",
                "duration": v.get("duration"),
                "uploader": v.get("uploader") or v.get("channel") or "Unknown",
            })

        return {"results": results}

    except Exception as e:
        traceback.print_exc()
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"error": str(e)},
        )



@app.post("/download")
def start_download(request: DownloadRequest):
    url = request.url.strip()
    if not url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A video URL is required.",
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
        }

    threading.Thread(
        target=download_task,
        args=(job_id, url, request.format_type, request.quality),
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

    format_type = job.get("format_type", "mp3")

    return FileResponse(
        file_path,
        media_type=media_types.get(format_type, "application/octet-stream"),
        filename=os.path.basename(file_path)
    )
