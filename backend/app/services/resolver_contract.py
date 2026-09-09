"""Stable response contract notes for mobile/client integration.

The dataclasses in universal_provider are FastAPI-serializable and intentionally mirror
Clipora mobile needs: platform, source URL, title/caption, media type, direct URL, quality,
resolution and approximate size.
"""

UNIVERSAL_RESOLVE_ENDPOINT = "/api/resolve/universal"
PLATFORM_DETECT_ENDPOINT = "/api/detect"
