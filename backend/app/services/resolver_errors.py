from __future__ import annotations

import re


_ANSI_ESCAPE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


class ResolverError(RuntimeError):
    """Base resolver error for clear API failures."""


class UnsupportedPlatformError(ResolverError):
    """Raised when Clipora cannot support a pasted URL yet."""


class NoDirectMediaError(ResolverError):
    """Raised when a resolver finds no direct downloadable media."""


_TIKTOK_RETRY = (
    "TikTok did not return a public video or photo file for this link. "
    "Open the post in TikTok, tap Share, and send it to Clipora again."
)


def public_resolver_error(error: Exception, *, limit: int = 360) -> str:
    """Return a concise, display-safe resolver failure for API clients."""

    text = _ANSI_ESCAPE.sub("", str(error)).replace("\r", " ").replace("\n", " ")
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"^(?:ERROR:\s*)+", "", text, flags=re.IGNORECASE)

    cause = error.__cause__
    lowered = " ".join(
        part for part in (text, type(error).__name__, str(cause) if cause else "", repr(error)) if part
    ).lower()

    if (
        "tiktok.com/?_r=1" in lowered
        or "video not available, status code 0" in lowered
        or "did not return a public video or photo" in lowered
    ):
        return _TIKTOK_RETRY
    if "unsupported url" in lowered and "tiktok" in lowered:
        return "TikTok redirected this share link away from its video. Retry with the full TikTok video link or use a hosted resolver."
    if "tiktok" in lowered and (
        not text
        or "could not extract" in lowered
        or "no downloadable" in lowered
        or "returned no downloadable" in lowered
    ):
        return _TIKTOK_RETRY
    if "sign in" in lowered or "login" in lowered or "private" in lowered:
        return "This post is private or requires an account login. Clipora resolves public/shareable links only."
    if "ffmpeg" in lowered:
        return "The resolver needs FFmpeg to combine this video's audio and picture. Install FFmpeg on the resolver and retry."
    if not text:
        return "The resolver could not extract downloadable media from this link."
    return text if len(text) <= limit else f"{text[: limit - 1].rstrip()}…"
