from __future__ import annotations

import html as html_lib
import json
import re
from dataclasses import dataclass
from typing import List, Optional
from urllib.parse import urlparse

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
    _post_id = re.compile(r"/post/([^?/#]+)")
    _author = re.compile(r"threads\.(?:com|net)/@([^/]+)")

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
        }
        for old, new in replacements.items():
            value = value.replace(old, new)
        try:
            # Safely decode remaining JSON escapes.
            value = json.loads('"' + value.replace('"', r'\"') + '"')
        except Exception:
            pass
        return value

    def parse(self, source: str, post_url: str) -> ResolvedPost:
        source = html_lib.unescape(source)
        post_id_m = self._post_id.search(post_url)
        author_m = self._author.search(post_url)
        post_id = post_id_m.group(1) if post_id_m else "thread"
        author = author_m.group(1) if author_m else "threads"
        media: list[ResolvedMedia] = []

        for block in re.finditer(r'"video_versions"\s*:\s*\[(.*?)\]', source, re.S):
            match = re.search(r'"url"\s*:\s*"(https?:[^\"]+?\.mp4[^\"]*)"', block.group(1))
            if match:
                media.append(ResolvedMedia("video", self._unescape(match.group(1))))

        if not any(x.media_type == "video" for x in media):
            for match in re.finditer(r'https?:\\?/\\?/[^"<\s]+?\.mp4[^"<\s]*', source):
                value = self._unescape(match.group(0))
                if value.startswith("http"):
                    media.append(ResolvedMedia("video", value))

        image_blocks = re.finditer(
            r'"image_versions2"\s*:\s*\{.*?"candidates"\s*:\s*\[(.*?)\]',
            source,
            re.S,
        )
        for block in image_blocks:
            match = re.search(r'"url"\s*:\s*"(https?:[^\"]+)"', block.group(1))
            if match:
                value = self._unescape(match.group(1))
                if "cdninstagram" in value or "fbcdn" in value:
                    media.append(ResolvedMedia("image", value))

        # Some Threads payload variants use a direct display/image URL.
        for match in re.finditer(r'"(?:display_url|image_url)"\s*:\s*"(https?:[^\"]+)"', source):
            value = self._unescape(match.group(1))
            if ("cdninstagram" in value or "fbcdn" in value) and not value.endswith(".mp4"):
                media.append(ResolvedMedia("image", value))

        caption = None
        caption_patterns = [
            r'"caption"\s*:\s*\{[^}]*"text"\s*:\s*"(.*?)"',
            r'<meta[^>]+property="og:description"[^>]+content="([^"]+)"',
        ]
        for pattern in caption_patterns:
            match = re.search(pattern, source, re.S)
            if match:
                caption = self._unescape(match.group(1)).strip() or None
                if caption:
                    break

        # Keep stable order while removing duplicate CDN variants.
        unique: dict[str, ResolvedMedia] = {}
        for item in media:
            unique[item.url] = item
        if not unique:
            raise ValueError("No downloadable media found. The post may be private or unavailable.")
        return ResolvedPost(post_id=post_id, author=author, caption=caption, media=list(unique.values()))


class HttpThreadsProvider(ThreadsProvider):
    _allowed_hosts = {"threads.com", "www.threads.com", "threads.net", "www.threads.net"}

    def __init__(self):
        self.parser = ThreadsHtmlParser()

    async def resolve(self, url: str) -> ResolvedPost:
        parsed = urlparse(url)
        if parsed.scheme != "https" or parsed.hostname not in self._allowed_hosts:
            raise ValueError("Only https://threads.com post URLs are accepted")
        headers = {
            "User-Agent": "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36",
            "Accept-Language": "en-GB,en;q=0.9",
        }
        async with httpx.AsyncClient(follow_redirects=True, timeout=25.0, headers=headers) as client:
            response = await client.get(url)
            response.raise_for_status()
            if "threads." not in str(response.url):
                raise ValueError("Threads redirected away from the requested post")
            return self.parser.parse(response.text, url)


provider: ThreadsProvider = HttpThreadsProvider()
