# Backend services

## Current resolver layout

- `threads_provider.py` handles public Threads post pages without collecting login credentials.
- `platforms.py` detects supported social platforms from pasted URLs.
- `universal_provider.py` uses the safe resolver-provider model for non-Threads public/share links.
- `download_service.py` now routes download jobs through `universal_provider`.

## Next step

The Flutter and native Android share flows both use `/api/resolve/universal`. There is no local WebView capture fallback.
