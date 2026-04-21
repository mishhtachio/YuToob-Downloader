# 🎵 YT Downloader App

A full-stack mobile application that allows users to search, preview, and download YouTube audio directly to their device with real-time progress tracking.

---

## 🚀 Features

* **Search YouTube videos** using keywords
* **Paste direct YouTube links** for instant access
* **Download audio (MP3)** with selectable quality
* **Real-time progress tracking** (speed, ETA, percentage)
* **Saves files directly to device storage** (Downloads folder)
* **Clipboard auto-detection** for quick link input
* **Download history tracking**
* **Cancel downloads anytime**

---

## 🛠️ Tech Stack

### Frontend

* Flutter
* Dart
* Flutter Downloader (DownloadManager integration)

### Backend

* FastAPI
* yt-dlp
* Python
* FFmpeg (for audio conversion)

---

## ⚙️ Setup Instructions

### 🔹 1. Clone Repository

```bash
git clone https://github.com/yourusername/yt-downloader.git
cd yt-downloader
```

---

## 🧠 Backend Setup (FastAPI)

### Install dependencies

```bash
cd backend
pip install -r requirements.txt
```

### Install FFmpeg (required)

* Download from: https://ffmpeg.org/download.html
* Add to system PATH

### Run backend server

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 📱 Frontend Setup (Flutter)

### Install dependencies

```bash
cd frontend
flutter pub get
```

### Run app

```bash
flutter run
```

---

## 📦 Build APK

```bash
flutter build apk --release
```

APK will be available at:

```
build/app/outputs/flutter-apk/app-release.apk
```

---

## ⚠️ Notes

* Requires internet connection
* YouTube extraction depends on yt-dlp updates
* FFmpeg must be installed for MP3 conversion

---
