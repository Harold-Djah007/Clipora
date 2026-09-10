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

## Local resolver (Windows)

Use Python 3.12 or 3.13:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
powershell -ExecutionPolicy Bypass -File ".\scripts\start_api.ps1"
```

Keep that terminal open. Verify it from a second terminal:

```powershell
Invoke-RestMethod "http://127.0.0.1:8010/health"
```

## Android USB test build

```powershell
& "C:\Android\Sdk\platform-tools\adb.exe" reverse --remove-all
& "C:\Android\Sdk\platform-tools\adb.exe" reverse tcp:8010 tcp:8010

cd mobile
flutter clean
flutter pub get
flutter test
flutter build apk --debug --no-pub --dart-define=CLIPORA_RESOLVER_URL=http://127.0.0.1:8010
& "C:\Android\Sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-debug.apk"
```

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
