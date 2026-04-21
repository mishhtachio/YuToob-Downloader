# Yuutoob Downloader

Flutter app for searching YouTube content, fetching video info, and downloading audio through a backend API.

## Release APK Setup

To make a shareable Android APK, you need two things:

1. A reachable backend API.
2. A real Android signing key.

### 1. Point the app at a public backend

The app reads the backend URL from a Dart define when you build:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=http://YOUR_SERVER:8000
```

If you do not provide `API_BASE_URL`, the app falls back to local development addresses and the old LAN IP, which is not suitable for a shareable build.

### 2. Create a release keystore

Create a keystore from the `android` folder:

```powershell
keytool -genkey -v -keystore ..\upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then copy `android/key.properties.example` to `android/key.properties` and fill in your values:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=../upload-keystore.jks
```

`android/key.properties` is already gitignored and should not be committed.

### 3. Build the APK

```powershell
flutter build apk --release --dart-define=API_BASE_URL=http://YOUR_SERVER:8000
```

The APK will be created at:

`build/app/outputs/flutter-apk/app-release.apk`

## Android Identity

This project now uses the Android application id:

`com.mishe.yt_downloader`

If you plan to publish this more widely, you may want to change that to a domain or brand you control.
