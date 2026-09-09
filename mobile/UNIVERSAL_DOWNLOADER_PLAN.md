# Mobile Universal Downloader Plan

This file tracks the next mobile step after the backend universal resolver foundation.

## Goal

Keep the current stressless Clipora home flow:

```text
Paste link
→ Save media
→ Clipora detects platform
→ Clipora resolves and downloads automatically
→ Media appears in Gallery
```

## Mobile implementation plan

1. Add a `PlatformDetector` in Flutter matching the backend supported platforms.
2. Add platform chips/icons beside the input: Threads, TikTok, Instagram, X, Pinterest, Facebook, Snapchat, YouTube.
3. Add `UniversalResolverService` for backend `/api/detect` and `/api/resolve/universal`.
4. Keep the existing local Threads Smart Capture path as the default fallback for Threads/private links.
5. Use backend universal resolve only for public/share links that return direct MP4/image URLs.
6. Add Queue screen polish: platform, quality, progress, retry, saved location.
7. Store files by platform folders under Clipora.

Phone testing:

1. `powershell -ExecutionPolicy Bypass -File .\scripts\start_api.ps1`
2. In Clipora Settings, set Resolver URL to the printed LAN address.
3. Tap Test, then share or paste a public TikTok or X link.

## Do not regress

- Do not bring back the poster-JPG bug.
- Do not force the user to choose Video/Post/Photos every time.
- Do not collect platform passwords.
- Do not add watermark-removal behavior.
