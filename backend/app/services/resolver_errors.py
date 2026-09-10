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

_PRIVATE = (
    "This post is private or requires an account login. Clipora resolves public/shareable links only."
)

_PLATFORM_RETRY = (
    ("threads", "Threads did not return a public photo or video for this link. Open the post, tap Share, and send it to Clipora again."),
    ("instagram", "Instagram did not return a public photo, reel, or carousel for this link. Open the post, tap Share, and send it to Clipora again."),
    ("facebook", "Facebook did not return a public video or photo for this link. Open the post, tap Share, and send it to Clipora again."),
    ("tiktok", _TIKTOK_RETRY),
    ("youtube", "YouTube did not return a downloadable file for this link. Public videos and Shorts work; private or age-gated videos do not."),
    ("pinterest", "Pinterest did not return a public pin image or video for this link. Open the pin, tap Share, and send it to Clipora again."),
    ("snapchat", "Snapchat did not return a public story or spotlight file for this link. Open the share link and send it to Clipora again."),
    ("twitter", "X/Twitter did not return a public video or image for this link. Open the post, tap Share, and send it to Clipora again."),
    (" x/", "X/Twitter did not return a public video or image for this link. Open the post, tap Share, and send it to Clipora again."),
    ("this x link", "X/Twitter did not return a public video or image for this link. Open the post, tap Share, and send it to Clipora again."),
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
        "registered users" in lowered
        or "cookies-from-browser" in lowered
        or "--cookies" in lowered
        or "only available for registered" in lowered
        or "login required" in lowered
        or "please log in" in lowered
        or "sign in" in lowered
        or "age-restrict" in lowered
        or ("private" in lowered and "clipora resolves public" not in lowered)
    ):
        return _PRIVATE

    if (
        "tiktok.com/?_r=1" in lowered
        or "video not available, status code 0" in lowered
        or "did not return a public video or photo" in lowered
    ):
        return _TIKTOK_RETRY
    if "unsupported url" in lowered and "tiktok" in lowered:
        return "TikTok redirected this share link away from its video. Retry with the full TikTok video link or use a hosted resolver."

    extract_failed = (
        not text
        or "could not extract" in lowered
        or "no downloadable" in lowered
        or "returned no downloadable" in lowered
        or "no video" in lowered
        or "no images found" in lowered
        or "ffmpeg" in lowered
        or "requested format" in lowered
        or "github.com/yt-dlp" in lowered
        or "yt-dlp" in lowered
    )
    if extract_failed:
        for token, message in _PLATFORM_RETRY:
            if token in lowered:
                return message
    if "ffmpeg" in lowered:
        return (
            "This video did not include a single downloadable file. "
            "Open the post, tap Share, and send it to Clipora again."
        )
    if not text or "yt-dlp" in lowered or "github.com" in lowered:
        return "The resolver could not extract downloadable media from this link."
    return text if len(text) <= limit else f"{text[: limit - 1].rstrip()}…"
