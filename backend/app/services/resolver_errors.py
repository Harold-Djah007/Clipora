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
        return "TikTok did not release this video to the resolver. Update yt-dlp, then retry; some posts may require a hosted resolver in another network region."
    if "unsupported url" in lower and "tiktok.com" in lower:
        return "TikTok redirected this share link away from its video. Retry with the full TikTok video link or use a hosted resolver."
    if "sign in" in lower or "login" in lower or "private" in lower:
        return "This post is private or requires an account login. Clipora resolves public/shareable links only."
    if "ffmpeg" in lower:
        return "The resolver needs FFmpeg to combine this video's audio and picture. Install FFmpeg on the resolver and retry."
    if not text:
        return "The resolver could not extract downloadable media from this link."
    return text if len(text) <= limit else f"{text[: limit - 1].rstrip()}…"
