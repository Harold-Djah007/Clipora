# Backend services

## Current resolver layout

- `threads_provider.py` keeps the existing Threads-specific authorized-session resolver.
- `platforms.py` detects supported social platforms from pasted URLs.
- `universal_provider.py` uses the safe resolver-provider model for non-Threads public/share links.
- `download_service.py` now routes download jobs through `universal_provider`.

## Next step

Wire the Flutter app to `/api/detect` and `/api/resolve/universal`, while keeping local Threads Smart Capture as the no-stress fallback.
