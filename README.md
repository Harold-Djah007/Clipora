# Clipora

Clipora is a premium social media saver focused on a stressless paste-link flow.

Current mobile baseline: **0.8.3 autopilot playback capture**.
Current backend upgrade branch: **universal resolver foundation**.

## Current stable mobile behavior

The mobile app handles Threads media that the signed-in user is already authorized to view. It saves real MP4 videos, photos, and carousels while rejecting poster images, page artwork, sprites, audio-only resources, and unrelated static assets.

### 0.8.3 mobile highlights

- Smart Save: one tap tries hidden resolving first, then uses Smart Capture automatically without forcing Video/Post choices.
- Autopilot playback: Smart Capture tries to start videos by itself using muted inline autoplay plus repeated play-control nudges.
- Faster resolving: shorter hidden checks, faster canonical detection, and faster Smart Capture polling.
- Video-safe media rules: video posts wait for real MP4 and do not fall back to low-quality poster JPG.
- Photo/carousel support for real image-only posts.
- Background foreground-service downloads, wake lock, Clipora folders, launch animation, and compact neon UI.

## Universal downloader foundation

Clipora is being upgraded from a Threads-focused saver into a universal social saver architecture.

Target platforms:

- Threads
- TikTok
- Instagram
- X / Twitter
- Pinterest
- Facebook
- Snapchat public/share links
- YouTube/Shorts where supported

The backend now has a platform-detection layer and a `yt-dlp`-powered universal resolver foundation. Threads remains connected to the existing local-session-aware resolver so the working private-video flow does not regress.

## Universal API endpoints

```text
POST /api/detect
POST /api/resolve/universal
POST /api/downloads
```

Example:

```bash
curl -X POST http://127.0.0.1:8000/api/detect \
  -H "Content-Type: application/json" \
  -d '{"url":"https://x.com/user/status/1234567890"}'
```

## Backend development

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pytest -q
uvicorn app.main:app --reload --port 8000
```

On Windows PowerShell:

```powershell
cd "C:\Users\A S U S\Desktop\Clipora\backend"
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pytest -q
uvicorn app.main:app --reload --port 8000
```

## Mobile development

```powershell
cd "C:\Users\A S U S\Desktop\Clipora\mobile"
flutter clean
flutter pub get
flutter test
flutter build apk --debug --no-pub
& "C:\Android\Sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-debug.apk"
```

## Storage

- Videos: `Movies/Clipora`
- Photos: `Pictures/Clipora`
- Captions: `Downloads/Clipora`

## Privacy and safety

Clipora does not ask for, store, or handle platform passwords. Private/restricted media must only work through a local signed-in session for content the user is already allowed to view. Clipora preserves source/creator metadata and does not add its own watermark.
