<div align="center">

# YuToob Downloader

*A modern, full-stack application to search, preview, and download high-quality YouTube audio (MP3) directly to your Android device or local storage.*

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-%23009688.svg?style=flat&logo=FastAPI&logoColor=white)](https://fastapi.tiangolo.com)
[![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)](https://www.python.org)
[![Android](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat&logo=android&logoColor=white)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat)](https://opensource.org/licenses/MIT)

---
</div>

## Features

* **Search YouTube**: Search videos directly in-app using keywords or paste direct YouTube/Music links.
* **Select Quality**: Download MP3 audio in selectable bitrates: Eco (128 kbps), Recommended (192 kbps), High (256 kbps), or Ultra (320 kbps).
* **Live Progress Tracking**: Displays download speed, percentage, ETA, and active conversion processing.
* **Dynamic Themes**: Interactive UI theme adjustments (choose from Crimson, Pink, Purple, Blue, Green, or Amber accents).
* **Local Controls**: Pause, resume, or cancel active downloads, persistent search history, and WiFi-only network protection toggles.

---

## Screenshots

### Search & Discovery

| Home Screen | Search Results | Video Details |
| :---: | :---: | :---: |
| <img src="assets/screenshots/home_screen.jpg" width="250" /> | <img src="assets/screenshots/search_results.jpg" width="250" /> | <img src="assets/screenshots/video_detail.jpg" width="250" /> |

### Quality Selection & Downloads

| Select Quality | Active Download | Download Completed |
| :---: | :---: | :---: |
| <img src="assets/screenshots/select_quality.jpg" width="250" /> | <img src="assets/screenshots/downloads_active.jpg" width="250" /> | <img src="assets/screenshots/downloads_completed.jpg" width="250" /> |

### Details & Settings

| Download Progress Details | Settings Screen |
| :---: | :---: |
| <img src="assets/screenshots/download_details.jpg" width="250" /> | <img src="assets/screenshots/settings_screen.jpg" width="250" /> |

---

## Tech Stack

### Frontend (Mobile App)
* **Flutter & Dart**: Cross-platform application framework.
* **SharedPreferences**: Local persistence for settings and queries.
* **MethodChannels**: Native Android file system and network status queries.

### Backend (API Server)
* **FastAPI**: Modern, fast Python web framework.
* **yt-dlp**: Rich media extraction utility.
* **FFmpeg**: Postprocessor for converting audio streams to high-fidelity MP3 files.

---

## Developer Setup Instructions

### 1. Prerequisites
Ensure you have the following installed on your developer machine:
* [Git](https://git-scm.com/)
* [Python 3.9+](https://www.python.org/downloads/)
* [Flutter SDK](https://docs.flutter.dev/get-started/install)
* [FFmpeg](https://ffmpeg.org/download.html) (add `bin/` path to your system's Environment Variables `PATH`)

### 2. Clone the Repository
```bash
git clone https://github.com/yourusername/yt-downloader.git
cd yt-downloader
```

---

## Backend Setup (FastAPI)

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```
2. Create and activate a Python virtual environment:
   ```bash
   python -m venv venv
   # On Windows (PowerShell):
   .\venv\Scripts\Activate.ps1
   # On macOS/Linux:
   source venv/bin/activate
   ```
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
4. **Setup YouTube Cookies (Highly Recommended)**:
   To prevent YouTube from rate-limiting or blocking requests, export your browser's YouTube cookies:
   * Use an extension like *Get cookies.txt LOCALLY* (Chrome/Firefox).
   * Save the file as `backend/cookies.txt`.
   * *Note: This file is automatically ignored by Git to protect your account session.*
5. Run the FastAPI development server:
   ```bash
   uvicorn main:app --host 0.0.0.0 --port 8000 --reload
   ```

---

## Frontend Setup & Run (Flutter)

1. Navigate to the frontend directory:
   ```bash
   cd frontend
   ```
2. Fetch package dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app in development mode:
   * Connect an Android device (with USB debugging enabled) or start an emulator.
   * Run the app:
     ```bash
     flutter run
     ```

---

## Building and Installing Your Own APK

To compile a release-ready Android APK that successfully connects to your API backend, follow these steps:

### 1. Determine Your Backend URL
* **Local Server (Same Wi-Fi network)**: If your phone is connected to the same Wi-Fi network as your PC running the backend:
  * Find your PC's IP address:
    * **Windows**: Open Command Prompt (`cmd`) and run `ipconfig`. Find your wireless adapter's `IPv4 Address` (e.g., `192.168.1.123`).
    * **macOS/Linux**: Run `ifconfig` or `ip a` (e.g., `192.168.1.123`).
  * Your API URL will be `http://<YOUR_PC_IP>:8000`.
* **Public Server**: If you deployed your backend to a platform like Render or a VPS:
  * Your API URL will be your public domain (e.g., `https://yutoob-downloader.onrender.com`).

### 2. Compile the Release APK
Pass your target API URL using Flutter's `--dart-define` flag:

* **For Local Wi-Fi Testing**:
  ```bash
  flutter build apk --release --dart-define=API_BASE_URL=http://<YOUR_PC_IP>:8000
  ```
* **For Production Deployment**:
  ```bash
  flutter build apk --release --dart-define=API_BASE_URL=https://your-backend-url.onrender.com
  ```

### 3. Install on Android Device
1. Locate the output APK file:
   ```
   frontend/build/app/outputs/flutter-apk/app-release.apk
   ```
2. Transfer this `.apk` file to your Android phone (via USB cable, Google Drive, email, or messaging app).
3. On your phone, tap the file to open and install it.
   * *If prompted by Google Play Protect or System Installer, select **Install Anyway** and enable "Install from Unknown Sources".*

---

## Security & Reliability Considerations

* **CORS Policy**: The backend defaults to open access (`*`). For public deployments, restrict origins using the `ALLOWED_ORIGINS` environment variable (e.g., `ALLOWED_ORIGINS=https://app.yourdomain.com`).
* **Path Traversal Shield**: The backend validates and resolves all file delivery paths to ensure they stay relative to the designated `downloads/` folder, blocking arbitrary file reads.
* **Server Protection Limits**: Active system-wide concurrent downloads are capped at 30, and individual download requests are capped at 8 threads to prevent system resource exhaustion or IP blocks.
