# Changelog

## 2.0.6+51 Public photo fallbacks for Pinterest, Instagram, X, and Facebook
- Pinterest HLS pins now save the pin image when FFmpeg is missing instead of failing the download.
- Instagram photo/reel pages scrape public `og:image` / carousel JSON when yt-dlp reports "no video formats".
- X image tweets use a public syndication fallback when the tweet has photos but no video.
- Facebook login-walled videos no longer dump cookie instructions; public embeds are still tried first.
- Resolver errors never show yt-dlp GitHub issue URLs.

## 2.0.6+50 Queue more links and harden every saver
- Instagram, X, YouTube, Pinterest, Facebook, and Snapchat now use the same yt-dlp retry and file-tunnel fallback as TikTok.
- Threads public pages expand share and `/t/` links, keep mixed photo/video carousels, pick the highest CDN variant, and ignore poster-only video pages.
- Threads media is fetched on the resolver and tunneled through `/api/files` so the phone is not blocked by Instagram CDN 403s.
- New shares and pastes queue while a save is already running instead of being ignored.

## 2.0.6+49 Debug APK compile fix
- Replaced the Kotlin `Notification.Builder.priority` field assignment that failed `flutter build apk` with `setPriority()`.

## 2.0.6+48 Phone test cycle and out-of-app alerts
- Locked the Windows test path to the PowerShell cycle: venv pip, `pytest -q`, `start_api.ps1`, health check, `adb reverse tcp:8010 tcp:8010`, `flutter test`, then a debug APK with `--dart-define=CLIPORA_RESOLVER_URL=http://127.0.0.1:8010`.
- Hardened TikTok short-link expansion and photo-carousel extraction through yt-dlp, without changing the Threads path.
- Added high-importance success and error notifications so Clipora can finish after Share returns you to TikTok.

## 2.0.6 Seamless resolver hardening
- Fixed Android build-time resolver injection in the active Gradle configuration.
- Removed the obsolete WebView capture and misleading local Threads-session screens; every save now follows the resolver-only route.
- Hardened TikTok short-link handling and stopped forcing headers that caused redirects to `tiktok.com/?_r=1`.
- Replaced raw ANSI/yt-dlp dumps with concise errors suitable for notifications and the mobile UI.
- Fixed gallery publishing on Android 9 and earlier, honored Wi-Fi-only for native share downloads, and synchronized backend/app version reporting.
- Reduced launch delay and updated the mobile version to 2.0.6+47.
- Replaced low-level Dio connection dumps with a direct backend/ADB recovery message and allowed slower resolver connections more time.

## 2.0.5 Share-return instant mode
- Added the Pinget-style handoff: when a user shares a link to Clipora, the app accepts the link, starts the foreground download service, and sends the user back to the source app after about a quarter second.
- Kept paste/manual entry as a fallback, but the fastest intended flow is Share -> Clipora -> return immediately while the resolver and Gallery save continue in the background.
- Added a native Android return-to-source action through the platform channel.
- Improved Android share parsing so multiple shared URLs can be accepted from one share payload.
- Kept the resolver-only rule for every supported platform: no in-app social web-player capture.
- Updated the mobile version to 2.0.5+45.

## 2.0.4 All-platform resolver-only instant mode
- Stopped using the old on-phone WebView/Field Mode capture route for every supported platform, including Threads.
- Clipora Instant now follows one stressless commercial flow for all platforms: paste/share link -> hosted resolver extracts -> APK saves automatically.
- Removed the hidden capture host from the instant downloader screen so normal saves cannot switch into a social web-player page.
- Added support for a bundled resolver URL through `--dart-define=CLIPORA_RESOLVER_URL=...` so release APKs can ship already connected instead of asking users to configure a server.
- Updated the mobile version to 2.0.4+44.

## 2.0.3 Resolver-only non-Threads instant route
- Stopped using the old on-phone WebView/Field Mode capture fallback for non-Threads platforms.
- TikTok, Instagram, X/Twitter, Pinterest, Facebook, Snapchat, and YouTube now require the Clipora resolver route so they can behave like a paste-to-download app instead of opening/scanning web players inside the APK.
- Threads remains on the existing local Smart Capture path as requested.
- Updated the mobile version to 2.0.3+43.

## 2.0.2 Clipora Instant paste-to-download
- Replaced the analyze-pick-save Studio flow with the simpler Pinget-style instant flow: paste/share link -> Clipora starts downloading automatically.
- Kept a manual Download Now button only as a fallback/retry, not as a required step.
- Kept hidden Field Mode capture inside the Save screen so normal link access does not visibly switch pages.
- Preserved the optional resolver boost for non-Threads services and kept Threads on the existing local Smart Capture path.
- Updated mobile description/version to 2.0.2+42.

## 2.0.1 Clipora Studio workflow break
- Replaced the old direct Smart Save feel with a visibly different three-step Studio flow: Paste -> Analyze -> Pick -> Save.
- Added a picker-ready scan stage so Clipora first builds a media plan, then lets the user see and select detected videos/photos before saving.
- Added AppState scanForMedia() and saveResolvedMedia() stages while keeping the old resolveAndDownload() wrapper only for compatibility.
- Kept Threads on the existing local Smart Capture path as requested.
- Kept the non-Threads extractor route based on yt-dlp-style extraction, cobalt-style picker/tunnel thinking, Seal-style mobile task UX, and gallery-dl-style nested media scanning without copying incompatible GPL/AGPL app code.

## 2.0.0 Clipora 2.0 Smart Save rebuild
- Rebuilt the mobile Save experience into a cleaner professional Smart Save Command Center.
- Switched the app shell and launch experience to Clipora 2.0 branding, faster launch timing, glass navigation, and a cleaner premium dark system.
- Kept Threads on the existing local smart-capture path as requested.
- Rebuilt the non-Threads downloader direction around a mature extractor-style route: yt-dlp backend engine, cobalt-style response/picker thinking, Seal-style mobile workflow ideas, and gallery-dl-style nested media/carousel scanning.
- Strengthened non-Threads extraction with nested media scanning, playlist/story preservation, signed URL dedupe, best-quality selection, server cache/proxy for hard video/CDN cases, and up to 20 carousel/story items.
- Preserved commercial safety boundaries: no watermark-removal feature, no platform password collection, no private-access bypassing.

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
