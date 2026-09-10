from __future__ import annotations

import html as html_lib
import json
import re
from dataclasses import dataclass
from typing import List, Optional
from urllib.parse import urljoin, urlparse

import httpx


@dataclass
class ResolvedMedia:
    media_type: str
    url: str
    width: Optional[int] = None
    height: Optional[int] = None


@dataclass
class ResolvedPost:
    post_id: str
    author: str
    caption: Optional[str]
    media: List[ResolvedMedia]


class ThreadsProvider:
    """Resolver for public Threads post pages."""

    async def resolve(self, url: str) -> ResolvedPost:
        raise NotImplementedError


class ThreadsHtmlParser:
    _post_id = re.compile(r"/(?:post|t)/([^?/#]+)")
    _author = re.compile(r"threads\.(?:com|net)/@([^/]+)")
    _canonical_post = re.compile(
        r"https://(?:www\.)?threads\.(?:com|net)/@[^/\s\"'<>]+/post/[^?/#\s\"'<>]+",
        re.I,
    )
    _short_post = re.compile(
        r"https://(?:www\.)?threads\.(?:com|net)/t/[^?/#\s\"'<>]+",
        re.I,
    )
    _width = re.compile(r'"width"\s*:\s*(\d+)')
    _height = re.compile(r'"height"\s*:\s*(\d+)')

    @staticmethod
    def _unescape(value: str) -> str:
        value = html_lib.unescape(value)
        value = value.replace(r"\/", "/")
        replacements = {
            r"\u0026": "&",
            r"\u003D": "=",
            r"\u003F": "?",
            r"\u0025": "%",
            r"\u00253D": "%3D",
            r"\u002F": "/",
            r"\u003A": ":",
        }
        for old, new in replacements.items():
            value = value.replace(old, new)
        try:
            value = json.loads('"' + value.replace('"', r'\"') + '"')
        except Exception:
            pass
        return value

    def parse(self, source: str, post_url: str) -> ResolvedPost:
        source = html_lib.unescape(source)
        identity = self._identity_url(source, post_url)
        post_id_m = self._post_id.search(identity)
        author_m = self._author.search(identity)
        post_id = post_id_m.group(1) if post_id_m else "thread"
        author = author_m.group(1) if author_m else "threads"

        carousel = self._extract_carousel(source)
        if carousel:
            media = carousel
        else:
            videos = self._extract_videos(source)
            images = self._extract_images(source) if not videos else []
            media = videos or images

        unique: dict[str, ResolvedMedia] = {}
        for item in media:
            if not self._is_allowed_media_url(item.url):
                continue
            key = self._identity_key(item.url)
            existing = unique.get(key)
            if existing is None or self._score(item) > self._score(existing):
                unique[key] = item

        values = list(unique.values())[:20]
        # Single video posts often include a poster frame. Mixed carousels keep both.
        if not carousel and any(item.media_type == "video" for item in values):
            values = [item for item in values if item.media_type == "video"]
        if not values:
            if "error=invalid_post" in source.lower() or "error=invalid_post" in post_url.lower():
                raise ValueError(
                    "Threads returned an invalid or expired share page. Open the post in Threads, tap Share, and send it to Clipora again."
                )
            raise ValueError(
                "No downloadable media found. Threads did not return a public photo or video for this link. "
                "Open the post, tap Share, and send it to Clipora again."
            )
        return ResolvedPost(post_id=post_id, author=author, caption=self._caption(source), media=values)

    def _identity_url(self, source: str, post_url: str) -> str:
        for candidate in (
            self._meta_content(source, "og:url"),
            self._link_href(source, "canonical"),
            post_url,
        ):
            if candidate and self._looks_like_post_identity(candidate):
                return candidate
        match = self._canonical_post.search(source) or self._short_post.search(source)
        return match.group(0) if match else post_url

    def _extract_videos(self, source: str) -> list[ResolvedMedia]:
        videos: list[ResolvedMedia] = []
        for block in re.finditer(r'"video_versions"\s*:\s*\[(.*?)\]', source, re.S):
            best: Optional[ResolvedMedia] = None
            for obj in re.finditer(r"\{[^{}]*\}", block.group(1)):
                raw = obj.group(0)
                url_match = re.search(r'"url"\s*:\s*"(https?:[^"]+)"', raw)
                if not url_match:
                    continue
                url = self._unescape(url_match.group(1))
                if not self._looks_like_video(url):
                    continue
                item = ResolvedMedia(
                    "video",
                    url,
                    width=self._int_from(raw, self._width),
                    height=self._int_from(raw, self._height),
                )
                if best is None or self._score(item) > self._score(best):
                    best = item
            if best:
                videos.append(best)
        if videos:
            return videos

        for match in re.finditer(
            r'"(?:video_url|playable_url|og:video(?::secure_url)?)"\s*:\s*"(https?:[^"]+)"',
            source,
        ):
            url = self._unescape(match.group(1))
            if self._looks_like_video(url):
                videos.append(ResolvedMedia("video", url))
        for match in re.finditer(r'https?:\\?/\\?/[^"<\s]+?\.mp4[^"<\s]*', source):
            url = self._unescape(match.group(0))
            if self._looks_like_video(url):
                videos.append(ResolvedMedia("video", url))
        og_video = self._meta_content(source, "og:video") or self._meta_content(source, "og:video:secure_url")
        if og_video and self._looks_like_video(og_video):
            videos.append(ResolvedMedia("video", og_video))
        return videos

    def _extract_carousel(self, source: str) -> list[ResolvedMedia]:
        body = self._json_array_body(source, "carousel_media")
        if not body:
            return []
        slides: list[ResolvedMedia] = []
        for obj in self._json_objects(body)[:20]:
            videos = self._extract_videos(obj)
            if videos:
                slides.append(videos[0])
                continue
            images = self._extract_images(obj)
            if images:
                slides.append(images[0])
        return slides

    def _extract_images(self, source: str) -> list[ResolvedMedia]:
        images: list[ResolvedMedia] = []
        for block in re.finditer(
            r'"image_versions2"\s*:\s*\{.*?"candidates"\s*:\s*\[(.*?)\]',
            source,
            re.S,
        ):
            best: Optional[ResolvedMedia] = None
            for obj in re.finditer(r"\{[^{}]*\}", block.group(1)):
                raw = obj.group(0)
                url_match = re.search(r'"url"\s*:\s*"(https?:[^"]+)"', raw)
                if not url_match:
                    continue
                url = self._unescape(url_match.group(1))
                if not self._looks_like_image(url):
                    continue
                item = ResolvedMedia(
                    "image",
                    url,
                    width=self._int_from(raw, self._width),
                    height=self._int_from(raw, self._height),
                )
                if best is None or self._score(item) > self._score(best):
                    best = item
            if best:
                images.append(best)
        if images:
            return images
        for match in re.finditer(r'"(?:display_url|image_url)"\s*:\s*"(https?:[^"]+)"', source):
            url = self._unescape(match.group(1))
            if self._looks_like_image(url):
                images.append(ResolvedMedia("image", url))
        og_image = self._meta_content(source, "og:image")
        if og_image and self._looks_like_image(og_image) and not images:
            images.append(ResolvedMedia("image", og_image))
        return images

    def _caption(self, source: str) -> Optional[str]:
        for pattern in (
            r'"caption"\s*:\s*\{[^}]*"text"\s*:\s*"(.*?)"',
            r'"text_post_app_info".*?"text"\s*:\s*"(.*?)"',
            r'<meta[^>]+property="og:description"[^>]+content="([^"]+)"',
        ):
            match = re.search(pattern, source, re.S | re.I)
            if match:
                caption = self._unescape(match.group(1)).strip()
                if caption:
                    return caption
        return None

    @staticmethod
    def _meta_content(source: str, property_name: str) -> Optional[str]:
        match = re.search(
            rf'<meta[^>]+(?:property|name)="{re.escape(property_name)}"[^>]+content="([^"]+)"',
            source,
            re.I,
        )
        if not match:
            match = re.search(
                rf'<meta[^>]+content="([^"]+)"[^>]+(?:property|name)="{re.escape(property_name)}"',
                source,
                re.I,
            )
        return html_lib.unescape(match.group(1)).strip() if match else None

    @staticmethod
    def _link_href(source: str, rel: str) -> Optional[str]:
        match = re.search(rf'<link[^>]+rel="{re.escape(rel)}"[^>]+href="([^"]+)"', source, re.I)
        return html_lib.unescape(match.group(1)).strip() if match else None

    @staticmethod
    def _int_from(raw: str, pattern: re.Pattern[str]) -> Optional[int]:
        match = pattern.search(raw)
        return int(match.group(1)) if match else None

    @staticmethod
    def _looks_like_post_identity(url: str) -> bool:
        lower = url.lower()
        return "/post/" in lower or bool(re.search(r"/t/[A-Za-z0-9_-]+", url))

    @staticmethod
    def _json_array_body(source: str, key: str) -> Optional[str]:
        match = re.search(rf'"{re.escape(key)}"\s*:\s*\[', source)
        if not match:
            return None
        start = match.end()
        depth = 1
        in_str = False
        escape = False
        for index in range(start, len(source)):
            char = source[index]
            if in_str:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == '"':
                    in_str = False
                continue
            if char == '"':
                in_str = True
            elif char == "[":
                depth += 1
            elif char == "]":
                depth -= 1
                if depth == 0:
                    return source[start:index]
        return None

    @staticmethod
    def _json_objects(body: str) -> list[str]:
        objects: list[str] = []
        depth = 0
        start: Optional[int] = None
        in_str = False
        escape = False
        for index, char in enumerate(body):
            if in_str:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == '"':
                    in_str = False
                continue
            if char == '"':
                in_str = True
                continue
            if char == "{":
                if depth == 0:
                    start = index
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0 and start is not None:
                    objects.append(body[start : index + 1])
                    start = None
        return objects

    @staticmethod
    def _score(item: ResolvedMedia) -> int:
        width = item.width or 0
        height = item.height or 0
        area = width * height
        if area:
            return area
        return width or height or (1 if item.media_type == "video" else 0)

    @staticmethod
    def _identity_key(url: str) -> str:
        parsed = urlparse(url)
        return f"{(parsed.hostname or '').lower()}{parsed.path}"

    @staticmethod
    def _looks_like_video(url: str) -> bool:
        lower = url.lower()
        if not lower.startswith(("http://", "https://")):
            return False
        if ".jpg" in lower or ".jpeg" in lower or ".png" in lower or ".webp" in lower:
            return False
        return (
            ".mp4" in lower
            or "mime_type=video" in lower
            or "mime=video" in lower
            or "/t50." in lower
            or "/t16/" in lower
            or "/o1/v/" in lower
        )

    @staticmethod
    def _looks_like_image(url: str) -> bool:
        lower = url.lower()
        if "profile_pic" in lower or "sprite" in lower or "favicon" in lower:
            return False
        return ("cdninstagram" in lower or "fbcdn" in lower) and (
            ".jpg" in lower
            or ".jpeg" in lower
            or ".png" in lower
            or ".webp" in lower
            or "stp=dst-jpg" in lower
            or "mime_type=image" in lower
        )

    @staticmethod
    def _is_allowed_media_url(url: str) -> bool:
        lower = url.lower()
        if not lower.startswith(("http://", "https://")):
            return False
        if "static.cdninstagram.com" in lower or "/rsrc.php/" in lower or "/static/" in lower:
            return False
        if "mime_type=audio" in lower or "/audio/" in lower:
            return False
        host = (urlparse(url).hostname or "").lower()
        return "cdninstagram.com" in host or "fbcdn.net" in host


class HttpThreadsProvider(ThreadsProvider):
    _allowed_hosts = {"threads.com", "www.threads.com", "threads.net", "www.threads.net"}

    def __init__(self):
        self.parser = ThreadsHtmlParser()

    async def resolve(self, url: str) -> ResolvedPost:
        parsed = urlparse(url)
        host = (parsed.hostname or "").lower()
        if parsed.scheme != "https" or not self._is_allowed_page_host(host):
            raise ValueError("Only https://threads.com post URLs are accepted")

        last_error: Exception | None = None
        best_post: Optional[ResolvedPost] = None
        for candidate in self._candidate_urls(url):
            for headers in self._request_profiles(candidate):
                try:
                    page_url, html = await self._fetch_public_page(candidate, headers)
                    identity = self.parser._identity_url(html, page_url)
                    if (
                        identity
                        and identity.split("?", 1)[0].rstrip("/") != page_url.split("?", 1)[0].rstrip("/")
                        and self.parser._looks_like_post_identity(identity)
                    ):
                        try:
                            page_url, html = await self._fetch_public_page(identity, headers)
                        except Exception:
                            pass
                    post = self.parser.parse(html, page_url)
                except Exception as exc:
                    last_error = exc
                    continue
                if any(item.media_type == "video" for item in post.media):
                    return post
                best_post = post
        if best_post is not None:
            return best_post
        if last_error is not None:
            raise last_error
        raise ValueError(
            "No downloadable media found. Threads did not return a public photo or video for this link."
        )

    async def _fetch_public_page(self, url: str, headers: dict[str, str]) -> tuple[str, str]:
        async with httpx.AsyncClient(follow_redirects=False, timeout=25.0, headers=headers) as client:
            current = url
            html = ""
            seen: set[str] = set()
            for _ in range(8):
                if current in seen:
                    break
                seen.add(current)
                response = await client.get(current)
                html = response.text or html
                location = str(response.headers.get("location") or "").strip()
                final_url = str(response.url)
                if self._is_threads_url(final_url) and not self._is_login_url(final_url):
                    current = final_url
                if location:
                    nxt = urljoin(current, location)
                    if self._is_threads_url(nxt) and not self._is_login_url(nxt):
                        current = nxt
                        if response.status_code in {301, 302, 303, 307, 308}:
                            continue
                    if self._is_login_url(nxt):
                        break
                if response.status_code >= 400:
                    response.raise_for_status()
                break
            if not self._is_threads_url(current) or self._is_login_url(current):
                raise ValueError("Threads redirected away from the requested post")
            if "error=invalid_post" in current.lower() and "/post/" not in current and "/t/" not in current:
                raise ValueError(
                    "Threads returned an invalid or expired share page. Open the post in Threads, tap Share, and send it to Clipora again."
                )
            return current, html

    @classmethod
    def _candidate_urls(cls, url: str) -> list[str]:
        urls: list[str] = []
        parsed = urlparse(url.strip())
        path = parsed.path or "/"
        share = re.search(r"/share/([^/?#]+)", path, re.I)
        if share:
            token = share.group(1).strip("/")
            for host in ("www.threads.com", "www.threads.net", "threads.com", "threads.net"):
                candidate = f"https://{host}/share/{token}/"
                if candidate not in urls:
                    urls.append(candidate)
        host = (parsed.hostname or "").lower()
        swapped = url
        if host.endswith("threads.com"):
            swapped = url.replace("://www.threads.com", "://www.threads.net", 1).replace("://threads.com", "://threads.net", 1)
        elif host.endswith("threads.net"):
            swapped = url.replace("://www.threads.net", "://www.threads.com", 1).replace("://threads.net", "://threads.com", 1)
        for candidate in (url, swapped):
            if candidate not in urls:
                urls.append(candidate)
        return urls

    @classmethod
    def _is_allowed_page_host(cls, host: str) -> bool:
        host = (host or "").lower()
        return host in cls._allowed_hosts or host.endswith(".threads.com") or host.endswith(".threads.net")

    @classmethod
    def _is_threads_url(cls, url: str) -> bool:
        return cls._is_allowed_page_host((urlparse(url).hostname or "").lower())

    @staticmethod
    def _is_login_url(url: str) -> bool:
        path = (urlparse(url).path or "").lower()
        return "/login" in path or "/accounts/login" in path or "checkpoint" in path

    @classmethod
    def _request_profiles(cls, url: str) -> tuple[dict[str, str], ...]:
        referer = {"Referer": "https://www.threads.com/"}
        chrome = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            **referer,
        }
        android = {
            "User-Agent": "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
            "Accept-Language": "en-GB,en;q=0.9",
            **referer,
        }
        bot = {"User-Agent": "facebookexternalhit/1.1", "Accept": "text/html,*/*", **referer}
        if "/share/" in (urlparse(url).path or "").lower():
            return (bot, chrome, android)
        return (chrome, android, bot)


provider: ThreadsProvider = HttpThreadsProvider()
