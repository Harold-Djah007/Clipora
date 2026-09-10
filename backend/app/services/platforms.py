from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from urllib.parse import urlparse
import re


class Platform(str, Enum):
    THREADS = "threads"
    TIKTOK = "tiktok"
    INSTAGRAM = "instagram"
    X = "x"
    PINTEREST = "pinterest"
    FACEBOOK = "facebook"
    SNAPCHAT = "snapchat"
    YOUTUBE = "youtube"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class PlatformInfo:
    platform: Platform
    hostname: str
    normalized_url: str
    needs_local_session: bool = False
    supports_server_resolve: bool = True


_SUPPORTED_HOSTS: dict[Platform, tuple[str, ...]] = {
    Platform.THREADS: ("threads.com", "www.threads.com", "threads.net", "www.threads.net"),
    Platform.TIKTOK: (
        "tiktok.com",
        "www.tiktok.com",
        "m.tiktok.com",
        "vm.tiktok.com",
        "vt.tiktok.com",
    ),
    Platform.INSTAGRAM: ("instagram.com", "www.instagram.com", "instagr.am", "www.instagr.am"),
    Platform.X: ("x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"),
    Platform.PINTEREST: ("pinterest.com", "www.pinterest.com", "pin.it"),
    Platform.FACEBOOK: (
        "facebook.com",
        "www.facebook.com",
        "m.facebook.com",
        "fb.watch",
        "www.fb.watch",
    ),
    Platform.SNAPCHAT: ("snapchat.com", "www.snapchat.com", "story.snapchat.com"),
    Platform.YOUTUBE: ("youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"),
}


def _clean_hostname(hostname: str | None) -> str:
    if not hostname:
        return ""
    return hostname.lower().strip().removeprefix("www.")


def _matches(hostname: str, allowed: tuple[str, ...]) -> bool:
    normalized_allowed = tuple(_clean_hostname(host) for host in allowed)
    return any(hostname == host or hostname.endswith(f".{host}") for host in normalized_allowed)


def detect_platform(url: str) -> PlatformInfo:
    parsed = urlparse(url.strip())
    if parsed.scheme not in {"http", "https"}:
        raise ValueError("Please send a valid http or https link.")

    hostname = _clean_hostname(parsed.hostname)
    if not hostname:
        raise ValueError("Please send a valid link with a website host.")

    for platform, hosts in _SUPPORTED_HOSTS.items():
        if _matches(hostname, hosts):
            return PlatformInfo(
                platform=platform,
                hostname=hostname,
                normalized_url=url.strip(),
                needs_local_session=False,
                supports_server_resolve=platform not in {Platform.UNKNOWN},
            )

    return PlatformInfo(
        platform=Platform.UNKNOWN,
        hostname=hostname,
        normalized_url=url.strip(),
        supports_server_resolve=False,
    )


def ensure_supported_platform(url: str) -> PlatformInfo:
    info = detect_platform(url)
    if info.platform == Platform.UNKNOWN:
        raise ValueError(f"Unsupported platform: {info.hostname}")
    return info


def safe_filename_part(value: str | None, fallback: str = "clipora") -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", value or fallback).strip("._-")
    return cleaned[:80] or fallback
