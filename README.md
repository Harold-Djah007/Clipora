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

The native share service receives the same `CLIPORA_RESOLVER_URL` that Flutter receives. A hosted field build ignores stale localhost/LAN settings left by USB testing.

## Free hosted field build

1. Deploy the included Render Blueprint:

   [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/Harold-Djah007/Clipora&branch=feature/universal-resolver-foundation)

2. Wait for `/health` on the new `onrender.com` URL to return Clipora `2.0.8`.
3. On GitHub, edit [`mobile/field_resolver_url.txt`](mobile/field_resolver_url.txt), replace its comments with that HTTPS URL, and commit the edit to `feature/universal-resolver-foundation`.
4. GitHub automatically runs **Build field APK**. Download its `clipora-field-apk` artifact and install `app-release.apk` once.

After that, normal use requires no PC backend, terminal, ADB reverse, pasted URL, or Save button. Sharing a supported link starts the background save and returns to the social app. The Android worker waits for a sleeping free Render service to wake and shows that state in its notification. The workflow's manual URL input remains available after the workflow reaches the repository's default branch.

Render documents that free web services sleep after 15 idle minutes and can take about one minute to wake. This free setup is suitable for field evaluation, but not an instant or production SLA. See [the field deployment guide](backend/docs/field-deployment.md).

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

The field workflow produces a release-mode APK for direct sideload testing. The repository currently falls back to Android's debug signing key; configure a stable private production keystore before Play Store publishing or distributing upgradeable production releases.
