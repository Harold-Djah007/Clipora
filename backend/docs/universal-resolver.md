# Clipora Universal Resolver Foundation

## Purpose

This backend is Clipora's platform-aware resolver. The APK does not use a mobile WebView capture fallback.

## Supported detection targets

- Threads
- TikTok
- Instagram
- X / Twitter
- Pinterest
- Facebook
- Snapchat public/share links
- YouTube/Shorts

## API flow

```text
POST /api/detect
→ returns platform, hostname, and resolver support state

POST /api/resolve/universal
→ returns source page metadata and validated direct media candidates

GET /api/files/{token}
→ serves a locally downloaded HLS/DASH file when no direct MP4 exists

POST /api/downloads
→ creates a download job using the same universal provider
```

## Resolver strategy

- Threads uses the dedicated public-page `threads_provider`.
- Other supported platforms use `yt-dlp` as a resolver engine.
- The provider prefers direct MP4 files because the current Android downloader can save direct files cleanly.
- HLS `.m3u8` streams are not returned as mobile URLs. If a link is HLS-only, the backend downloads it locally and exposes `/api/files/{token}` for the phone.
- Photo-only links can return the largest image thumbnail only when no direct video candidate exists.

## Safety boundaries

- No platform passwords are collected.
- No private-access bypassing is implemented.
- No watermark-removal feature is implemented.
- Creator/source metadata is preserved in the response.

## Next mobile task

Phone testing: follow `local-backend-test.md`. Start the backend with `scripts/start_api.ps1`, map USB with `adb reverse tcp:8010 tcp:8010`, build the debug APK with `--dart-define=CLIPORA_RESOLVER_URL=http://127.0.0.1:8010`, then share a public TikTok link to Clipora.
