# Clipora

Clipora is an Android social-media saver built around one quick flow:

**Share a supported link → choose Clipora → return to the social app → download continues in the background.**

The mobile app never opens a social page to scrape or capture it. A Clipora resolver extracts the media and the Android app publishes completed videos to `Movies/Clipora`, photos to `Pictures/Clipora`, and optional captions to `Downloads/Clipora`.

## Supported links

- TikTok
- Instagram
- Threads
- X / Twitter
- Pinterest
- Facebook
- Snapchat public/share links
- YouTube and Shorts where the resolver supports the media

Clipora is for public media and content the user is authorized to save. It does not remove watermarks, collect platform passwords, or bypass private-account access controls.

## Clean Windows test cycle

Use this path from the repo folder. First PowerShell starts the backend and stays open. Second PowerShell checks health, maps USB port 8010, then builds and installs the debug APK.

```powershell
cd "C:\Users\A S U S\Desktop\threadvault_premium_0.6.0\threadvault"

git switch cursor/tiktok-notify-harden-2f1d
git pull origin cursor/tiktok-notify-harden-2f1d
git log -1 --oneline

cd backend
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m pytest -q
powershell -ExecutionPolicy Bypass -File ".\scripts\start_api.ps1"
```

Keep that terminal open. Verify it from a second terminal, then build:

```powershell
Invoke-RestMethod "http://127.0.0.1:8010/health"

& "C:\Android\Sdk\platform-tools\adb.exe" reverse --remove-all
& "C:\Android\Sdk\platform-tools\adb.exe" reverse tcp:8010 tcp:8010

cd "C:\Users\A S U S\Desktop\threadvault_premium_0.6.0\threadvault\mobile"
flutter clean
flutter pub get
flutter test
flutter build apk --debug --no-pub --dart-define=CLIPORA_RESOLVER_URL=http://127.0.0.1:8010
& "C:\Android\Sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-debug.apk"
```

Open Clipora once and allow notifications if Android asks. Then:

TikTok → Share → More → Clipora

If Download cannot reach the backend, confirm `adb reverse --list` contains `tcp:8010 tcp:8010`, then open Chrome on the phone at `http://127.0.0.1:8010/health`. Expected: `{"ok":true,"service":"clipora","version":"2.0.6"}`. That is a connection issue, not a TikTok extraction failure. Full recovery commands are in `backend/docs/local-backend-test.md`.

The native share service receives the same `CLIPORA_RESOLVER_URL` that Flutter receives. For a customer-ready APK, replace localhost with a stable HTTPS resolver URL.

## Backend checks

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest -q
```

API endpoints:

- `GET /health` and `GET /api/health`
- `POST /api/detect`
- `POST /api/resolve/universal`
- `GET /api/files/{token}` for temporary resolver-proxied media

## Release note

The repository's release build currently falls back to Android's debug signing key until a production keystore is configured. Configure production signing before Play Store or customer distribution.
