from __future__ import annotations

import html as html_lib
import json
import re
from typing import Any
from urllib.parse import urlparse

import httpx

from app.services.platforms import Platform, ensure_supported_platform
from app.services.resolver_errors import NoDirectMediaError


class PublicSocialPageExtractor:
    """Extract public media metadata when a site's yt-dlp extractor is blocked.

    This is deliberately a public-page fallback. It does not sign in, bypass private
    posts, or execute page JavaScript. Modern social pages still expose OpenGraph,
    JSON-LD, or hydration media fields for embeds and link previews; those are enough
    to recover public photos, videos, and mixed stories on many edge variants.
    """

    _MAX_MEDIA = 20
    _BROWSER_HEADERS = (
        {
            "User-Agent": (
                "Mozilla/5.0 (Linux; Android 14; Pixel 8) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        },
        {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    _MEDIA_KEYS = re.compile(
        r'"(?P<key>(?:play(?:able|back)?|download|content|media|video|image|display|thumbnail)[A-Za-z0-9_]*url|'
        r'playAddr|downloadAddr|contentUrl|mediaUrl|videoUrl|imageUrl|display_url|playable_url)"'
        r"\s*:\s*\"(?P<url>https?:[^\"]+)\"",
        re.I,
    )

    def extract(self, url: str) -> dict[str, Any]:
        requested = ensure_supported_platform(url)
        candidate = self.expand_tiktok_short_url(url) if requested.platform == Platform.TIKTOK else url
        last_error: Exception | None = None

        for headers in self._BROWSER_HEADERS:
            try:
                page_headers = dict(headers)
                page_headers["Referer"] = f"https://{urlparse(candidate).hostname or requested.hostname}/"
                with httpx.Client(follow_redirects=True, timeout=20.0, headers=page_headers) as client:
                    response = client.get(candidate)
                response.raise_for_status()
                final_url = str(response.url)
                final_platform = ensure_supported_platform(final_url)
                if final_platform.platform != requested.platform:
                    raise NoDirectMediaError("The social site redirected away from the requested post.")
                return self.parse(response.text, final_url, requested.platform)
            except (httpx.HTTPError, ValueError, NoDirectMediaError) as exc:
                last_error = exc

        raise NoDirectMediaError(
            "The public post page did not expose downloadable media. The post may be unavailable or require login."
        ) from last_error

    def expand_tiktok_short_url(self, url: str) -> str:
        parsed = urlparse(url)
        if (parsed.hostname or "").lower() not in {"vt.tiktok.com", "vm.tiktok.com"}:
            return url

        candidates: list[str] = []
        # TikTok's public oEmbed endpoint often preserves the canonical @user/video
        # URL even when a cloud-hosted short-link request is redirected to /?_r=1.
        try:
            with httpx.Client(follow_redirects=True, timeout=10.0, headers=self._BROWSER_HEADERS[0]) as client:
                response = client.get("https://www.tiktok.com/oembed", params={"url": url})
            if response.status_code == 200:
                payload = response.json()
                candidates.extend(self._canonical_tiktok_candidates(json.dumps(payload)))
        except (httpx.HTTPError, ValueError, TypeError, AttributeError):
            pass

        profiles = (
            ({"User-Agent": "facebookexternalhit/1.1"}, "head"),
            (self._BROWSER_HEADERS[0], "get"),
            (self._BROWSER_HEADERS[1], "get"),
        )
        for headers, method in profiles:
            try:
                with httpx.Client(follow_redirects=True, timeout=10.0, headers=headers) as client:
                    response = client.head(url) if method == "head" else client.get(url)
                chain = [*getattr(response, "history", []), response]
                candidates.extend(str(item.url) for item in chain)
                candidates.extend(item.headers.get("location", "") for item in chain)
                candidates.extend(self._canonical_tiktok_candidates(response.text))
            except (httpx.HTTPError, ValueError, TypeError, AttributeError):
                continue

        return next((item for item in candidates if self._is_canonical_tiktok_url(item)), url)

    @staticmethod
    def _canonical_tiktok_candidates(text: str) -> list[str]:
        decoded = PublicSocialPageExtractor._decode(text)
        return re.findall(r"https://(?:www\.)?tiktok\.com/@[^\s\"'<>]+/(?:video|photo)/\d+", decoded)

    @staticmethod
    def _is_canonical_tiktok_url(value: str) -> bool:
        try:
            parsed = urlparse(value)
            host = (parsed.hostname or "").lower()
            return (host == "tiktok.com" or host.endswith(".tiktok.com")) and bool(
                re.search(r"/(?:video|photo)/\d+", parsed.path)
            )
        except ValueError:
            return False

    def parse(self, source: str, page_url: str, platform: Platform) -> dict[str, Any]:
        decoded = self._decode(source)
        meta = self._meta_values(decoded)
        primary: list[tuple[str, str]] = []
        previews: list[tuple[str, str]] = []

        for match in self._MEDIA_KEYS.finditer(source):
            item = (match.group("key"), self._decode(match.group("url")))
            (previews if "thumbnail" in match.group("key").lower() else primary).append(item)

        for key in ("og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"):
            primary.extend((key, value) for value in meta.get(key, []))
        for key in ("og:image", "og:image:url", "twitter:image", "twitter:image:src"):
            previews.extend((key, value) for value in meta.get(key, []))

        entries: list[dict[str, Any]] = []
        seen: set[str] = set()
        for key, media_url in primary:
            item = self._entry(media_url, key, page_url)
            if item and item["url"] not in seen:
                seen.add(item["url"])
                entries.append(item)

        # An OpenGraph image is frequently a video poster. Use it only when the
        # page exposed no playable media, while keeping JSON carousel images.
        if not entries:
            for key, media_url in previews:
                item = self._entry(media_url, key, page_url, force_image=True)
                if item and item["url"] not in seen:
                    seen.add(item["url"])
                    entries.append(item)

        if not entries:
            raise NoDirectMediaError("No downloadable public media was present in the page metadata.")

        path_parts = [part for part in urlparse(page_url).path.split("/") if part]
        post_id = next((part for part in reversed(path_parts) if part not in {"p", "reel", "spotlight", "story"}), "clipora")
        author = next((part[1:] for part in path_parts if part.startswith("@")), platform.value)
        title = self._first(meta, "og:title", "twitter:title")
        caption = self._first(meta, "og:description", "twitter:description", "description") or title
        return {
            "id": post_id,
            "uploader": author,
            "title": title,
            "description": caption,
            "webpage_url": page_url,
            "entries": entries[: self._MAX_MEDIA],
        }

    @staticmethod
    def _meta_values(source: str) -> dict[str, list[str]]:
        values: dict[str, list[str]] = {}
        for tag in re.findall(r"<meta\b[^>]*>", source, re.I):
            attrs = {
                key.lower(): html_lib.unescape(value)
                for key, _, value in re.findall(r"([:\w-]+)\s*=\s*(['\"])(.*?)\2", tag, re.S)
            }
            name = (attrs.get("property") or attrs.get("name") or attrs.get("itemprop") or "").lower()
            content = attrs.get("content", "").strip()
            if name and content:
                values.setdefault(name, []).append(PublicSocialPageExtractor._decode(content))
        return values

    @staticmethod
    def _entry(media_url: str, key: str, page_url: str, force_image: bool = False) -> dict[str, Any] | None:
        media_url = PublicSocialPageExtractor._decode(media_url).strip().strip('"\'')
        parsed = urlparse(media_url)
        if parsed.scheme != "https" or not parsed.hostname:
            return None
        lower = media_url.lower()
        hint = key.lower()
        if any(token in lower for token in ("profile_pic", "favicon", ".svg", ".css", ".js")):
            return None

        is_video = not force_image and (
            any(token in lower for token in (".mp4", "mime=video", "video/mp4", "video_mp4", "/video/"))
            or any(token in hint for token in ("video", "play", "downloadaddr"))
        )
        is_image = force_image or (
            any(token in lower for token in (".jpg", ".jpeg", ".png", ".webp", ".gif", "mime=image"))
            or any(token in hint for token in ("image", "display", "thumbnail"))
        )
        if not is_video and not is_image:
            return None
        if is_video:
            return {
                "url": media_url,
                "webpage_url": page_url,
                "ext": "mp4",
                "protocol": "https",
                "vcodec": "unknown",
                "acodec": "unknown",
                "format_note": "public-page",
            }
        extension = next((ext for ext in ("jpg", "jpeg", "png", "webp", "gif") if f".{ext}" in lower), "jpg")
        return {
            "url": media_url,
            "webpage_url": page_url,
            "ext": extension,
            "protocol": "https",
            "vcodec": "none",
            "format_note": "public-page-image",
        }

    @staticmethod
    def _first(meta: dict[str, list[str]], *keys: str) -> str | None:
        return next((value for key in keys for value in meta.get(key, []) if value.strip()), None)

    @staticmethod
    def _decode(value: str) -> str:
        decoded = html_lib.unescape(value).replace(r"\/", "/")
        replacements = {r"\u0026": "&", r"\u003d": "=", r"\u003D": "=", r"\u002F": "/"}
        for old, new in replacements.items():
            decoded = decoded.replace(old, new)
        return decoded


public_social_page_extractor = PublicSocialPageExtractor()
