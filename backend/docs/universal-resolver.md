# Clipora Universal Resolver Foundation

## Purpose

This backend foundation turns Clipora into a platform-aware social media resolver while keeping the mobile Threads Smart Capture flow intact.

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
→ returns platform, hostname, support state, and whether local session may be needed

POST /api/resolve/universal
→ returns source page metadata and validated direct media candidates

POST /api/downloads
→ creates a download job using the same universal provider
```

## Resolver strategy

- Threads uses the existing `threads_provider` to avoid breaking the private-video fix.
- Other supported platforms use `yt-dlp` as a resolver engine.
- The provider prefers direct MP4 files because the current Android downloader can save direct files cleanly.
- HLS `.m3u8` streams are skipped for now until a dedicated ffmpeg/mobile streaming pipeline is added.
- Photo-only links can return the largest image thumbnail only when no direct video candidate exists.

## Safety boundaries

- No platform passwords are collected.
- No private-access bypassing is implemented.
- No watermark-removal feature is implemented.
- Creator/source metadata is preserved in the response.

## Next mobile task

Add a `UniversalResolverService` in Flutter so the home screen can detect TikTok, Instagram, X, Pinterest, Facebook, Snapchat, YouTube, and Threads links before choosing the resolver path.
