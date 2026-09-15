from __future__ import annotations

import os
from http.cookiejar import MozillaCookieJar
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


DEFAULT_COOKIE_FILE = Path("/etc/secrets/cookies.txt")


def cookie_file() -> Path | None:
    configured = os.getenv("CLIPORA_COOKIES_FILE", "").strip()
    candidate = Path(configured) if configured else DEFAULT_COOKIE_FILE
    return candidate if candidate.is_file() and candidate.stat().st_size > 0 else None


def outbound_proxy() -> str | None:
    value = os.getenv("CLIPORA_OUTBOUND_PROXY", "").strip()
    if not value:
        return None
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https", "socks4", "socks5", "socks5h"} or not parsed.hostname:
        raise ValueError("CLIPORA_OUTBOUND_PROXY must be a valid HTTP(S) or SOCKS proxy URL.")
    return value


def ytdlp_session_options() -> dict[str, Any]:
    options: dict[str, Any] = {}
    cookies = cookie_file()
    proxy = outbound_proxy()
    if cookies:
        options["cookiefile"] = str(cookies)
    if proxy:
        options["proxy"] = proxy
    return options


def httpx_session_options() -> dict[str, Any]:
    options: dict[str, Any] = {"trust_env": False}
    cookies = cookie_file()
    proxy = outbound_proxy()
    if cookies:
        jar = MozillaCookieJar(str(cookies))
        jar.load(ignore_discard=True, ignore_expires=True)
        options["cookies"] = jar
    # httpx 0.27 supports HTTP(S) forward proxies. yt-dlp handles SOCKS for
    # extraction; direct CDN caching falls back to the normal network in that case.
    if proxy and urlparse(proxy).scheme in {"http", "https"}:
        options["proxy"] = proxy
    return options


def session_status() -> dict[str, bool]:
    return {
        "cookies_configured": cookie_file() is not None,
        "proxy_configured": outbound_proxy() is not None,
    }
