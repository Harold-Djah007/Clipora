from __future__ import annotations

import re


_ANSI_ESCAPE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


class ResolverError(RuntimeError):
    """Base resolver error for clear API failures."""


class UnsupportedPlatformError(ResolverError):
    """Raised when Clipora cannot support a pasted URL yet."""


class NoDirectMediaError(ResolverError):
    """Raised when a resolver finds no direct downloadable media."""


def public_resolver_error(error: Exception, *, limit: int = 360) -> str:
    """Return a concise, display-safe resolver failure for API clients."""

    text = _ANSI_ESCAPE.sub("", str(error)).replace("\r", " ").replace("\n", " ")
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"^(?:ERROR:\s*)+", "", text, flags=re.IGNORECASE)

    lower = text.lower()
    if "tiktok.com/?_r=1" in lower or "video not available, status code 0" in lower:
        return "TikTok did not release this public video to the resolver. Clipora tried both the share link and its canonical post URL; retry once after the resolver is awake."
    if "unsupported url" in lower and "tiktok.com" in lower:
        return "TikTok redirected this share link away from its video and did not provide a canonical public post URL."
    if (
        "no video formats found" in lower
        or "no downloadable mp4/image" in lower
        or "empty media response" in lower
    ):
        return "The public post loaded, but the platform did not expose downloadable media to the resolver."
    if "http error 403" in lower or "status code 403" in lower:
        return "The social platform refused its temporary media link. Clipora did not pass the broken link to your phone; retry to request a fresh copy."
    if (
        "sign in" in lower
        or "login" in lower
        or "logged-in" in lower
        or "authentication" in lower
        or "cookies-from-browser" in lower
        or "private" in lower
    ):
        return "This post is private or requires an account login. Clipora resolves public/shareable links only."
    if "ffmpeg" in lower:
        return "The resolver needs FFmpeg to combine this video's audio and picture. Install FFmpeg on the resolver and retry."
    if not text:
        return "The resolver could not extract downloadable media from this link."
    return text if len(text) <= limit else f"{text[: limit - 1].rstrip()}…"
