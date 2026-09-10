# Changelog

## 0.8.8 Extractor-pipeline universal saver
- Upgraded the non-Threads universal backend toward the same architecture used by strong open-source downloaders: site extractors first, playlist/story entries preserved, nested media URL scanning, backend media proxy/cache for videos, and host/path dedupe for signed URLs.
- Threads remains unchanged on its local Smart Capture path.
- The resolver keeps up to 20 carousel/story items and avoids saving poster images when video-like metadata exists.
- Added regression tests for nested story media URLs, multi-image photo carousels, signed URL dedupe, and best-quality selection.

## 0.8.7 Field Mode commercial polish
- Field Mode is the default: Clipora can run on a phone without a PC backend/server.
- Optional Resolver URLs still work for advanced LAN/cloud setups, but they are no longer required.
- Legacy localhost resolver settings are migrated back to blank Field Mode so sold/test installs do not fail on `127.0.0.1:8010`.
- Field capture now keeps up to 20 media items, dedupes signed duplicate video variants, and can keep strong mixed carousel image slides without saving single video posters.
- Paste-clear remains tied to successful saves only.

## 0.8.5 Phone-ready universal saver
- Added a Resolver URL setting with a backend health check for LAN and USB testing.
- Bound the Windows start script to `0.0.0.0` and printed the PC LAN address for phone tests.
- Added Share-to-Clipora for Android text/plain share intents.
- Instagram and Facebook now fall back to Smart Capture when the backend cannot resolve the public link.
- Added an additive HLS file fallback: if yt-dlp has no direct MP4, the backend downloads the file and serves `/api/files/{token}`.
- Kept Threads on the existing local Smart Capture path. No watermark-removal. No platform passwords.

## 0.8.4 Universal Resolver Foundation
- Added backend platform detection for Threads, TikTok, Instagram, X/Twitter, Pinterest, Facebook, Snapchat public/share links, and YouTube/Shorts.
- Added `yt-dlp`-powered universal resolver foundation for supported public/share links.
- Added `/api/detect` and `/api/resolve/universal` endpoints.
- Updated download jobs to use the universal provider while preserving the existing Threads resolver for compatibility.
- Extended download items with platform, source page URL, file size, and quality metadata.
- Added regression tests for platform detection and media candidate selection.
- Kept the safety boundary: no platform password collection, no private-access bypassing, and no watermark-removal feature.

## 0.8.3
- Added autopilot Smart Capture that tries to auto-start Threads videos before requiring user interaction.
- Kept video-poster guard so video posts wait for a real MP4 instead of saving poster JPG.

## 0.8.2
- Replaced manual Video/Post/Photos choice with Smart Save and automatic Smart Capture.

## 0.8.1
- Fixed share-link regression where video posts could be saved as image-only poster snapshots.

## 0.8.0
- Added 10/10 polish pass, faster resolving, default 5 download lanes, and safer media handling.

## 0.6.0
- Replaced placeholder mobile shell with a functional local-first download workflow.
- Added embedded Threads browser resolution for public/private authorized posts.
- Added `video_versions` parser with DASH fallback.
- Added image/carousel extraction.
- Added batch post handling and multiple-media downloads.
- Added filename templates and caption sidecars.
- Added persistent on-device history and sharing.
- Added Threads login/reconnect screen.
- Added secure session metadata and configurable auto-wipe TTL.
- Added premium Material 3 navigation and cards.
- Replaced backend stub provider with real HTTP/HTML parser boundary.
- Added resolver/session status/health endpoints.
- Added Docker image and parser regression tests.
- Added Android application scaffold.
