from __future__ import annotations

import asyncio
import re
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional
from urllib.parse import unquote, urljoin, urlparse

import httpx

from app.services.file_cache import media_file_cache
from app.services.platforms import Platform, detect_platform, ensure_supported_platform, safe_filename_part
from app.services.threads_provider import provider as threads_provider

try:  # yt-dlp is optional at import time so tests can still exercise validation paths.
    import yt_dlp  # type: ignore
except Exception:  # pragma: no cover - depends on deployment environment
    yt_dlp = None  # type: ignore


@dataclass
class UniversalMedia:
    media_type: str
    url: str
    mime_type: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    filesize: Optional[int] = None
    quality: Optional[str] = None


@dataclass
class UniversalPost:
    post_id: str
    author: str
    platform: str
    source_url: str
    title: Optional[str]
    caption: Optional[str]
    media: list[UniversalMedia]


class UniversalProvider:
    """Safe resolver provider for Clipora's universal saver direction.

    Threads deliberately remains on Clipora's dedicated public-page resolver. All other
    supported services go through yt-dlp: expand the public URL, extract metadata, keep
    playlist/carousel entries, then tunnel files through `/api/files` when the phone
    cannot fetch them. Photo slideshows use gallery-dl-style image lists rather than
    video posters.
    """

    _MAX_PLAYLIST_MEDIA = 20
    _MAX_DEEP_SCAN_NODES = 5000
    _TIKTOK_SHORT_HOSTS = {"vt.tiktok.com", "vm.tiktok.com"}
    _TIKTOK_MEDIA_PATH = re.compile(
        r"/(?:@(?P<user>[^/]+)/)?(?P<kind>video|photo)/(?P<id>\d{8,30})",
        re.I,
    )
    _TIKTOK_MOBILE_V = re.compile(r"/v/(?P<id>\d{8,30})", re.I)
    _TIKTOK_AWEME = re.compile(
        r"""(?:aweme_id|itemId|item_id|video_id)["']?\s*[:=]\s*["']?(?P<id>\d{8,30})""",
        re.I,
    )

    _ydl_opts: dict[str, Any] = {
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        "merge_output_format": "mp4",
        "extract_flat": False,
        "socket_timeout": 30,
        "retries": 3,
        "fragment_retries": 3,
        "geo_bypass": True,
        "http_headers": {
            "Accept-Language": "en-US,en;q=0.9",
        },
    }

    async def resolve(self, url: str) -> UniversalPost:
        platform_info = ensure_supported_platform(url)
        if platform_info.platform == Platform.THREADS:
            return await self._resolve_threads(url)
        return await self._resolve_with_ytdlp(url)

    async def detect(self, url: str) -> dict[str, Any]:
        info = detect_platform(url)
        return {
            "platform": info.platform.value,
            "hostname": info.hostname,
            "supported": info.platform != Platform.UNKNOWN,
            "needs_local_session": info.needs_local_session,
            "supports_server_resolve": info.supports_server_resolve,
        }

    async def _resolve_threads(self, url: str) -> UniversalPost:
        post = await threads_provider.resolve(url)
        loop = asyncio.get_running_loop()
        media: list[UniversalMedia] = []
        for index, item in enumerate(post.media[: self._MAX_PLAYLIST_MEDIA], start=1):
            direct = UniversalMedia(
                media_type=item.media_type,
                url=item.url,
                mime_type="video/mp4" if item.media_type == "video" else self._image_mime_type(item.url),
                width=item.width,
                height=item.height,
                quality=self._quality_label(item.width, item.height),
            )
            try:
                cached = await loop.run_in_executor(
                    None,
                    self._cache_http_media,
                    item.url,
                    item.media_type,
                    url,
                    index,
                    item.width,
                    item.height,
                )
                media.append(cached)
            except Exception:
                media.append(direct)
        if not media:
            raise ValueError(self._no_media_message(Platform.THREADS))
        return UniversalPost(
            post_id=post.post_id,
            author=post.author,
            platform=Platform.THREADS.value,
            source_url=url,
            title=None,
            caption=post.caption,
            media=media,
        )

    async def _resolve_with_ytdlp(self, url: str) -> UniversalPost:
        platform_info = ensure_supported_platform(url)
        source_url = self._prepare_source_url(url, platform_info.platform)
        loop = asyncio.get_running_loop()
        try:
            info = await loop.run_in_executor(None, self._extract_info, source_url)
        except Exception as extract_error:
            try:
                media = await loop.run_in_executor(
                    None,
                    self._download_to_cache,
                    source_url,
                    {"id": self._post_id_from_url(source_url) or "clipora", "uploader": platform_info.platform.value},
                    1,
                )
            except Exception:
                media = []
            if media:
                return UniversalPost(
                    post_id=safe_filename_part(str(self._post_id_from_url(source_url) or "clipora")),
                    author=platform_info.platform.value,
                    platform=platform_info.platform.value,
                    source_url=url,
                    title=None,
                    caption=None,
                    media=media,
                )
            raise extract_error

        entries = self._entry_infos(info)

        media: list[UniversalMedia] = []
        for index, entry in enumerate(entries[: self._MAX_PLAYLIST_MEDIA], start=1):
            entry_url = self._entry_url(entry, source_url)
            entry_media = self._extract_media_items(entry)
            video_like = self._has_video_like_format(entry, self._formats(entry)) or any(
                item.media_type == "video" for item in entry_media
            )

            if video_like:
                try:
                    # Tunnel the file through the backend so the phone does not have to
                    # fetch CDN/HLS URLs that 403 outside a browser session.
                    entry_media = await loop.run_in_executor(None, self._download_to_cache, entry_url, entry, index)
                except Exception:
                    if not entry_media:
                        raise

            if not entry_media and video_like:
                entry_media = await loop.run_in_executor(None, self._download_to_cache, entry_url, entry, index)

            media.extend(entry_media)

        media = self._dedupe_media(media)[: self._MAX_PLAYLIST_MEDIA]
        if not media:
            try:
                media = await loop.run_in_executor(
                    None, self._download_to_cache, self._entry_url(info, source_url), info, 1
                )
            except Exception:
                media = []
        if not media:
            raise ValueError(self._no_media_message(platform_info.platform))

        post_id = safe_filename_part(str(info.get("id") or info.get("display_id") or self._post_id_from_url(url) or "clipora"))
        author = safe_filename_part(str(info.get("uploader") or info.get("channel") or platform_info.platform.value))
        title = info.get("title") or info.get("fulltitle")
        caption = info.get("description") or title

        return UniversalPost(
            post_id=post_id,
            author=author,
            platform=platform_info.platform.value,
            source_url=url,
            title=title,
            caption=caption,
            media=media,
        )

    def _extract_info(self, url: str) -> dict[str, Any]:
        platform = detect_platform(url).platform
        allow_playlist = platform not in {Platform.THREADS, Platform.YOUTUBE}
        extractor_url = self._prepare_source_url(url, platform)
        attempts = self._extract_attempts(extractor_url, url, platform, allow_playlist)

        last_error: Exception | None = None
        for attempt_url, attempt_opts in attempts:
            try:
                info = self._extract_info_with_opts(attempt_url, attempt_opts)
                if self._extracted_info_usable(info):
                    return info
                last_error = ValueError(f"yt-dlp returned no downloadable media for this {platform.value} link.")
            except Exception as exc:
                last_error = exc
                if self._should_retry_without_format(exc):
                    fallback_opts = dict(attempt_opts)
                    fallback_opts.pop("format", None)
                    fallback_opts["skip_download"] = True
                    try:
                        info = self._extract_info_with_opts(attempt_url, fallback_opts)
                        if self._extracted_info_usable(info):
                            return info
                        last_error = ValueError(
                            f"yt-dlp returned no downloadable media for this {platform.value} link."
                        )
                    except Exception as fallback_error:
                        last_error = fallback_error
        if last_error is None:
            detail = "unknown error"
        else:
            detail = str(last_error).strip() or type(last_error).__name__
        raise ValueError(
            f"yt-dlp could not extract media from this {platform.value} link. {detail}"
        ) from last_error

    def _extract_attempts(
        self, extractor_url: str, original_url: str, platform: Platform, allow_playlist: bool
    ) -> list[tuple[str, dict[str, Any]]]:
        attempts: list[tuple[str, dict[str, Any]]] = []
        urls_to_try: list[str] = []
        for candidate in (extractor_url, original_url):
            if candidate not in urls_to_try:
                urls_to_try.append(candidate)

        if platform == Platform.YOUTUBE:
            for clients in (["mweb", "tv"], ["android", "ios"], ["web"]):
                opts = self._ydl_opts_for(extractor_url, allow_playlist=False)
                opts["extractor_args"] = {"youtube": {"player_client": clients}}
                attempts.append((extractor_url, opts))
            return attempts

        impersonates: tuple[str, ...] = ()
        if platform == Platform.TIKTOK:
            impersonates = ("chrome", "chrome120")
        elif platform in {Platform.INSTAGRAM, Platform.FACEBOOK, Platform.SNAPCHAT, Platform.X, Platform.PINTEREST}:
            impersonates = ("chrome", "chrome120")

        for attempt_url in urls_to_try:
            for impersonate in impersonates:
                attempt_opts = self._ydl_opts_for(attempt_url, allow_playlist=allow_playlist)
                headers = dict(attempt_opts.get("http_headers") or {})
                headers["Accept-Language"] = "en-US,en;q=0.9"
                attempt_opts["http_headers"] = headers
                attempt_opts["impersonate"] = impersonate
                attempts.append((attempt_url, attempt_opts))
            attempts.append((attempt_url, self._ydl_opts_for(attempt_url, allow_playlist=allow_playlist)))
        return attempts or [(extractor_url, self._ydl_opts_for(extractor_url, allow_playlist=allow_playlist))]

    def _prepare_source_url(self, url: str, platform: Platform) -> str:
        if platform == Platform.THREADS:
            return url
        if platform == Platform.TIKTOK:
            return self._expand_tiktok_short_url(url)
        return self._expand_share_url(url)

    @staticmethod
    def _no_media_message(platform: Platform) -> str:
        return {
            Platform.THREADS: (
                "No downloadable media found. Threads did not return a public photo or video for this link. "
                "Open the post, tap Share, and send it to Clipora again."
            ),
            Platform.TIKTOK: (
                "TikTok did not return a public video or photo file for this link. "
                "Open the post in TikTok, tap Share, and send it to Clipora again."
            ),
            Platform.INSTAGRAM: (
                "Instagram did not return a public photo, reel, or carousel for this link. "
                "Open the post, tap Share, and send it to Clipora again."
            ),
            Platform.FACEBOOK: (
                "Facebook did not return a public video or photo for this link. "
                "Open the post, tap Share, and send it to Clipora again."
            ),
            Platform.X: (
                "X/Twitter did not return a public video or image for this link. "
                "Open the post, tap Share, and send it to Clipora again."
            ),
            Platform.YOUTUBE: (
                "YouTube did not return a downloadable file for this link. "
                "Public videos and Shorts work; private or age-gated videos do not."
            ),
            Platform.PINTEREST: (
                "Pinterest did not return a public pin image or video for this link. "
                "Open the pin, tap Share, and send it to Clipora again."
            ),
            Platform.SNAPCHAT: (
                "Snapchat did not return a public story or spotlight file for this link. "
                "Open the share link and send it to Clipora again."
            ),
        }.get(platform, "No downloadable MP4/image media found for this link.")

    @classmethod
    def _is_tiktok_short_url(cls, url: str) -> bool:
        parsed = urlparse(url)
        host = (parsed.hostname or "").lower()
        path = parsed.path or ""
        if host in cls._TIKTOK_SHORT_HOSTS:
            return True
        return host.endswith("tiktok.com") and path.startswith("/t/")

    @classmethod
    def _canonical_tiktok_media_url(cls, candidate: str) -> Optional[str]:
        if not candidate:
            return None
        parsed = urlparse(candidate.strip())
        host = (parsed.hostname or "").lower()
        if "tiktok.com" not in host:
            return None
        match = cls._TIKTOK_MEDIA_PATH.search(parsed.path or "")
        if match:
            user = match.group("user")
            kind = match.group("kind").lower()
            media_id = match.group("id")
            if user:
                return f"https://www.tiktok.com/@{user}/{kind}/{media_id}"
            return f"https://www.tiktok.com/{kind}/{media_id}"
        mobile = cls._TIKTOK_MOBILE_V.search(parsed.path or "")
        if mobile:
            return f"https://www.tiktok.com/video/{mobile.group('id')}"
        return None

    @classmethod
    def _tiktok_canonical_from_text(cls, text: str) -> Optional[str]:
        if not text:
            return None
        for match in re.findall(
            r"https?://(?:www\.|m\.)?tiktok\.com/@[^/\s\"'<>]+/(?:video|photo)/\d{8,30}",
            text,
            flags=re.I,
        ):
            canonical = cls._canonical_tiktok_media_url(match)
            if canonical:
                return canonical
        aweme = cls._TIKTOK_AWEME.search(text)
        if aweme:
            return f"https://www.tiktok.com/video/{aweme.group('id')}"
        return None

    @classmethod
    def _expand_tiktok_short_url(cls, url: str) -> str:
        """Resolve vt/vm/`/t/` links hop-by-hop without accepting homepage or off-site redirects."""

        if not cls._is_tiktok_short_url(url):
            return cls._canonical_tiktok_media_url(url) or url

        profiles = (
            {"User-Agent": "facebookexternalhit/1.1", "Accept": "text/html,*/*"},
            {"User-Agent": "Twitterbot/1.0", "Accept": "text/html,*/*"},
            {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
                ),
                "Accept-Language": "en-US,en;q=0.9",
            },
        )
        for headers in profiles:
            current = url
            seen: set[str] = set()
            try:
                with httpx.Client(follow_redirects=False, timeout=10.0, headers=headers) as client:
                    for _ in range(8):
                        if current in seen:
                            break
                        seen.add(current)
                        response = client.get(current)
                        location = str(response.headers.get("location") or "").strip()
                        try:
                            body = response.text or ""
                        except Exception:
                            body = ""
                        for blob in (str(response.url), location):
                            if not blob:
                                continue
                            canonical = cls._canonical_tiktok_media_url(urljoin(current, blob))
                            if canonical:
                                return canonical
                        canonical = cls._tiktok_canonical_from_text(" ".join([str(response.url), location, body]))
                        if canonical:
                            return canonical
                        if not location:
                            break
                        nxt = urljoin(current, location)
                        nxt_host = (urlparse(nxt).hostname or "").lower()
                        if "tiktok.com" not in nxt_host:
                            break
                        current = nxt
            except (httpx.HTTPError, ValueError):
                continue
        return url

    _SHORT_SHARE_HOSTS = {
        "pin.it",
        "www.pin.it",
        "fb.watch",
        "www.fb.watch",
        "fb.me",
        "l.instagram.com",
        "lm.facebook.com",
        "t.snapchat.com",
        "instagr.am",
        "www.instagr.am",
    }

    @classmethod
    def _expand_share_url(cls, url: str) -> str:
        """Follow public share/short links onto the same platform, cobalt-style."""

        parsed = urlparse(url)
        host = (parsed.hostname or "").lower()
        path = parsed.path or ""
        instagram_share = host.endswith("instagram.com") and path.startswith("/share")
        if host not in cls._SHORT_SHARE_HOSTS and not instagram_share:
            return url
        try:
            family = cls._host_family(detect_platform(url).platform)
        except Exception:
            return url
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,*/*",
            "Accept-Language": "en-US,en;q=0.9",
        }
        current = url
        best = url
        seen: set[str] = set()
        try:
            with httpx.Client(follow_redirects=False, timeout=10.0, headers=headers) as client:
                for _ in range(8):
                    if current in seen:
                        break
                    seen.add(current)
                    response = client.get(current)
                    location = str(response.headers.get("location") or "").strip()
                    for blob in (str(response.url), location):
                        if not blob:
                            continue
                        candidate = urljoin(current, blob)
                        if cls._host_in_family(candidate, family):
                            best = candidate
                    if not location:
                        break
                    nxt = urljoin(current, location)
                    if not cls._host_in_family(nxt, family):
                        break
                    current = nxt
                    best = current
        except (httpx.HTTPError, ValueError):
            return best
        return best

    @staticmethod
    def _host_family(platform: Platform) -> tuple[str, ...]:
        return {
            Platform.PINTEREST: ("pinterest.com", "pin.it"),
            Platform.FACEBOOK: ("facebook.com", "fb.watch", "fb.me"),
            Platform.INSTAGRAM: ("instagram.com", "instagr.am"),
            Platform.SNAPCHAT: ("snapchat.com",),
            Platform.YOUTUBE: ("youtube.com", "youtu.be"),
            Platform.X: ("x.com", "twitter.com"),
            Platform.TIKTOK: ("tiktok.com",),
            Platform.THREADS: ("threads.com", "threads.net"),
        }.get(platform, ())

    @staticmethod
    def _host_in_family(url: str, family: tuple[str, ...]) -> bool:
        host = (urlparse(url).hostname or "").lower()
        if not host or not family:
            return False
        return any(host == domain or host.endswith("." + domain) for domain in family)

    def _extract_info_with_opts(self, url: str, opts: dict[str, Any]) -> dict[str, Any]:
        with yt_dlp.YoutubeDL(opts) as ydl:  # type: ignore[union-attr]
            info = ydl.extract_info(url, download=False)
            if not isinstance(info, dict):
                raise ValueError("yt-dlp returned an unsupported response.")
            return info

    def _ydl_opts_for(self, url: str, allow_playlist: bool = False) -> dict[str, Any]:
        opts = dict(self._ydl_opts)
        headers = dict(self._ydl_opts.get("http_headers", {}))
        opts["http_headers"] = headers
        opts["noplaylist"] = not allow_playlist

        platform = detect_platform(url).platform
        if platform == Platform.X:
            opts["extractor_args"] = {"twitter": {"api": ["syndication"]}}
        elif platform == Platform.YOUTUBE:
            opts["extractor_args"] = {"youtube": {"player_client": ["mweb", "tv"]}}
        elif platform == Platform.TIKTOK:
            # TikTok's extractor owns its User-Agent and Referer. webpage_download
            # helps photo slideshows that have no playable video format.
            headers.pop("User-Agent", None)
            opts["extractor_args"] = {"tiktok": {"webpage_download": ["True"]}}
        elif platform in {Platform.INSTAGRAM, Platform.FACEBOOK, Platform.SNAPCHAT, Platform.PINTEREST}:
            headers["Referer"] = f"https://{urlparse(url).hostname or ''}/"

        return opts

    @staticmethod
    def _should_retry_without_format(error: Exception) -> bool:
        text = str(error).lower()
        return (
            "requested format is not available" in text
            or "requested format not available" in text
            or "no video could be found" in text
            or "no video formats found" in text
            or "no images found" in text
        )

    @staticmethod
    def _extracted_info_usable(info: dict[str, Any]) -> bool:
        if info.get("entries") or info.get("formats") or info.get("requested_formats"):
            return True
        if info.get("url") or info.get("images") or info.get("image_post_info") or info.get("carousel_media"):
            return True
        return bool(info.get("imagePostInfo") or info.get("aweme_detail"))

    def _entry_infos(self, info: dict[str, Any]) -> list[dict[str, Any]]:
        raw_entries = info.get("entries")
        if not isinstance(raw_entries, list) or not raw_entries:
            return [info]
        entries = [entry for entry in raw_entries if isinstance(entry, dict)]
        return entries or [info]

    @staticmethod
    def _entry_url(entry: dict[str, Any], fallback: str) -> str:
        for key in ("webpage_url", "original_url", "url"):
            value = entry.get(key)
            if isinstance(value, str) and value.startswith(("http://", "https://")):
                return value
        return fallback

    @staticmethod
    def _post_id_from_url(url: str) -> Optional[str]:
        try:
            parts = [part for part in url.split("?")[0].split("/") if part]
            return parts[-1] if parts else None
        except Exception:
            return None

    def _extract_media_items(self, info: dict[str, Any]) -> list[UniversalMedia]:
        direct_url = info.get("url")
        direct_ext = str(info.get("ext") or "").lower()
        direct_protocol = str(info.get("protocol") or "").lower()

        direct_video = self._media_from_format(
            {
                "url": direct_url,
                "ext": direct_ext,
                "protocol": direct_protocol,
                "width": info.get("width"),
                "height": info.get("height"),
                "filesize": info.get("filesize") or info.get("filesize_approx"),
                "format_note": info.get("format_note"),
                "vcodec": info.get("vcodec"),
                "acodec": info.get("acodec"),
                "mime_type": info.get("mime_type") or info.get("mimetype"),
            }
        )
        direct_image = self._media_from_url(
            str(direct_url or ""),
            key_hint="url image_url",
            width=info.get("width"),
            height=info.get("height"),
        )

        formats = self._formats(info)
        format_candidates = [item for item in (self._media_from_format(fmt) for fmt in formats) if item]
        format_candidates.sort(key=self._media_rank, reverse=True)

        scan_source = {key: value for key, value in info.items() if key not in {"formats", "thumbnails"}}
        nested = list(self._deep_media_candidates(scan_source))

        video_candidates: list[UniversalMedia] = []
        if direct_video:
            video_candidates.append(direct_video)
        if format_candidates:
            # Formats are normally quality variants for one video, so keep the best
            # one. Carousels/stories should arrive as entries or nested media URLs.
            video_candidates.append(format_candidates[0])
        video_candidates.extend(item for item in nested if item.media_type == "video")
        video_candidates = self._dedupe_media(video_candidates)
        if video_candidates:
            video_candidates.sort(key=self._media_rank, reverse=True)
            return video_candidates[: self._MAX_PLAYLIST_MEDIA]

        if self._has_video_like_format(info, formats):
            return []

        slideshow = self._slideshow_media(info)
        if slideshow:
            return slideshow[: self._MAX_PLAYLIST_MEDIA]

        image_candidates: list[UniversalMedia] = []
        if direct_image and direct_image.media_type == "image":
            image_candidates.append(direct_image)
        image_candidates.extend(item for item in nested if item.media_type == "image")
        image_candidates = self._dedupe_media(image_candidates)
        if image_candidates:
            image_candidates.sort(key=self._media_rank, reverse=True)
            return image_candidates[: self._MAX_PLAYLIST_MEDIA]

        thumbnails = [thumb for thumb in info.get("thumbnails") or [] if isinstance(thumb, dict)]
        for thumb in thumbnails:
            thumb_url = thumb.get("url")
            if not isinstance(thumb_url, str):
                continue
            image = self._media_from_url(
                thumb_url,
                key_hint="thumbnail image",
                width=thumb.get("width"),
                height=thumb.get("height"),
            )
            if image and image.media_type == "image":
                image_candidates.append(image)
        image_candidates = self._dedupe_media(image_candidates)
        image_candidates.sort(key=self._media_rank, reverse=True)
        return image_candidates[:1]

    def _slideshow_media(self, info: dict[str, Any]) -> list[UniversalMedia]:
        """Keep photo carousels/slideshows when yt-dlp has no playable video."""

        items: list[UniversalMedia] = []
        images = info.get("images")
        if isinstance(images, list):
            for image in images:
                media = self._media_from_image_node(image, key_hint="image_url slideshow")
                if media:
                    items.append(media)

        for slide in self._iter_image_post_slides(info):
            media = self._media_from_image_node(slide, key_hint="image_url photomode")
            if media:
                items.append(media)

        carousel = info.get("carousel_media")
        if isinstance(carousel, list):
            for slide in carousel:
                if not isinstance(slide, dict):
                    continue
                if self._has_video_like_format(slide, self._formats(slide)):
                    continue
                media = self._best_carousel_image(slide)
                if media:
                    items.append(media)

        sidecar = info.get("edge_sidecar_to_children")
        if isinstance(sidecar, dict):
            edges = sidecar.get("edges")
            if isinstance(edges, list):
                for edge in edges:
                    node = edge.get("node") if isinstance(edge, dict) else None
                    if isinstance(node, dict):
                        media = self._best_carousel_image(node)
                        if media:
                            items.append(media)

        return self._dedupe_media(items)[: self._MAX_PLAYLIST_MEDIA]

    def _iter_image_post_slides(self, info: dict[str, Any]) -> list[Any]:
        slides: list[Any] = []
        nodes: list[Any] = [info.get("image_post_info"), info.get("imagePostInfo")]
        aweme = info.get("aweme_detail")
        if isinstance(aweme, dict):
            nodes.append(aweme.get("image_post_info") or aweme.get("imagePostInfo"))
        for node in nodes:
            if not isinstance(node, dict):
                continue
            images = node.get("images") or node.get("image_list") or []
            if isinstance(images, list):
                slides.extend(images)
        return slides

    def _media_from_image_node(self, node: Any, key_hint: str) -> Optional[UniversalMedia]:
        if isinstance(node, str):
            media = self._media_from_url(node, key_hint=key_hint)
            return media if media and media.media_type == "image" else None
        if not isinstance(node, dict):
            return None
        width = node.get("width")
        height = node.get("height")
        for key in ("url", "image", "display_url", "src"):
            value = node.get(key)
            if isinstance(value, str):
                media = self._media_from_url(value, key_hint=key_hint, width=width, height=height)
                if media and media.media_type == "image":
                    return media
        for nested_key in ("imageURL", "image_url", "display_image", "displayImage"):
            nested = node.get(nested_key)
            media = self._media_from_image_node(nested, key_hint=f"{key_hint} {nested_key}")
            if media:
                return media
        for list_key in ("urlList", "url_list", "urls", "candidates"):
            values = node.get(list_key)
            if isinstance(values, list):
                for value in values:
                    media = self._media_from_image_node(value, key_hint=f"{key_hint} {list_key}")
                    if media:
                        return media
        return None

    def _best_carousel_image(self, slide: dict[str, Any]) -> Optional[UniversalMedia]:
        versions = slide.get("image_versions2")
        if isinstance(versions, dict):
            candidates = versions.get("candidates")
            if isinstance(candidates, list):
                ranked = [item for item in candidates if isinstance(item, dict)]
                ranked.sort(
                    key=lambda item: (self._int_or_none(item.get("width")) or 0)
                    * (self._int_or_none(item.get("height")) or 0),
                    reverse=True,
                )
                for candidate in ranked:
                    media = self._media_from_image_node(candidate, key_hint="carousel_media display_url")
                    if media:
                        return media
        return self._media_from_image_node(slide, key_hint="carousel_media image_url")

    @staticmethod
    def _formats(info: dict[str, Any]) -> list[dict[str, Any]]:
        return [fmt for fmt in info.get("formats") or [] if isinstance(fmt, dict)]

    def _download_to_cache(self, url: str, info: dict[str, Any], index: int = 1) -> list[UniversalMedia]:
        if yt_dlp is None:
            raise RuntimeError("yt-dlp is not installed. Run: pip install -r backend/requirements.txt")

        cache_dir = Path(tempfile.gettempdir()) / "clipora-media"
        cache_dir.mkdir(parents=True, exist_ok=True)
        token = uuid.uuid4().hex
        opts = {
            **self._ydl_opts_for(url),
            "skip_download": False,
            "outtmpl": str(cache_dir / f"{token}.%(ext)s"),
            "merge_output_format": "mp4",
            "overwrites": True,
            "noprogress": True,
            "socket_timeout": 45,
        }
        if detect_platform(url).platform in {
            Platform.TIKTOK,
            Platform.INSTAGRAM,
            Platform.FACEBOOK,
            Platform.SNAPCHAT,
            Platform.PINTEREST,
            Platform.X,
        }:
            opts["impersonate"] = "chrome"
            opts["http_headers"] = {"Accept-Language": "en-US,en;q=0.9"}
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:  # type: ignore[union-attr]
                downloaded = ydl.extract_info(url, download=True)
        except Exception as exc:
            if opts.get("impersonate"):
                retry_opts = dict(opts)
                retry_opts.pop("impersonate", None)
                try:
                    with yt_dlp.YoutubeDL(retry_opts) as ydl:  # type: ignore[union-attr]
                        downloaded = ydl.extract_info(url, download=True)
                except Exception as retry_error:
                    raise ValueError(
                        "No direct MP4 was available, and HLS/direct file fallback failed. "
                        "Install ffmpeg for YouTube/X/Facebook streams (winget install Gyan.FFmpeg) and retry. "
                        f"Detail: {retry_error}"
                    ) from retry_error
            else:
                raise ValueError(
                    "No direct MP4 was available, and HLS/direct file fallback failed. "
                    "Install ffmpeg for YouTube/X/Facebook streams (winget install Gyan.FFmpeg) and retry. "
                    f"Detail: {exc}"
                ) from exc

        if isinstance(downloaded, dict) and downloaded.get("entries"):
            downloaded = next((entry for entry in downloaded["entries"] if entry), downloaded)

        path = self._find_downloaded_file(cache_dir, token)
        if path is None:
            raise ValueError("yt-dlp finished without a saved media file.")

        media_file_cache.put(path, token)
        suffix = path.suffix.lower()
        media_type = "image" if suffix in {".jpg", ".jpeg", ".png", ".webp", ".gif"} else "video"
        downloaded_info = downloaded if isinstance(downloaded, dict) else {}
        width = self._int_or_none(downloaded_info.get("width")) or self._int_or_none(info.get("width"))
        height = self._int_or_none(downloaded_info.get("height")) or self._int_or_none(info.get("height"))
        return [
            UniversalMedia(
                media_type=media_type,
                url=f"/api/files/{token}",
                mime_type=self._image_mime_type(str(path)) if media_type == "image" else "video/mp4",
                width=width,
                height=height,
                filesize=path.stat().st_size,
                quality=str(downloaded_info.get("format_note") or self._quality_label(width, height) or f"downloaded-{index}"),
            )
        ]

    def _cache_http_media(
        self,
        url: str,
        media_type: str,
        source_url: str,
        index: int = 1,
        width: Optional[int] = None,
        height: Optional[int] = None,
    ) -> UniversalMedia:
        """Fetch a public CDN file on the resolver so the phone can save `/api/files`."""

        parsed_source = urlparse(source_url)
        referer = source_url if source_url.startswith("http") else "https://www.threads.com/"
        if parsed_source.scheme != "https":
            referer = "https://www.threads.com/"
        cache_dir = Path(tempfile.gettempdir()) / "clipora-media"
        cache_dir.mkdir(parents=True, exist_ok=True)
        token = uuid.uuid4().hex
        suffix = ".mp4" if media_type == "video" else self._image_suffix(url)
        dest = cache_dir / f"{token}{suffix}"
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
            ),
            "Accept": "video/mp4,image/avif,image/webp,image/*,*/*;q=0.8" if media_type != "video" else "video/mp4,video/*,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": referer,
        }
        with httpx.Client(follow_redirects=True, timeout=45.0, headers=headers) as client:
            response = client.get(url)
            response.raise_for_status()
            content_type = str(response.headers.get("content-type") or "").lower()
            if "text/html" in content_type or "application/json" in content_type:
                raise ValueError("Threads CDN returned a page instead of media")
            payload = response.content or b""
            if len(payload) < 256:
                raise ValueError("Threads CDN returned an empty media file")
            dest.write_bytes(payload)
        media_file_cache.put(dest, token)
        return UniversalMedia(
            media_type=media_type,
            url=f"/api/files/{token}",
            mime_type="video/mp4" if media_type == "video" else self._image_mime_type(url),
            width=width,
            height=height,
            filesize=dest.stat().st_size,
            quality=self._quality_label(width, height) or f"downloaded-{index}",
        )

    @staticmethod
    def _image_suffix(url: str) -> str:
        lower = url.lower()
        if ".png" in lower:
            return ".png"
        if ".webp" in lower:
            return ".webp"
        if ".gif" in lower:
            return ".gif"
        return ".jpg"

    @staticmethod
    def _find_downloaded_file(cache_dir: Path, token: str) -> Optional[Path]:
        matches = [
            path
            for path in cache_dir.glob(f"{token}.*")
            if path.is_file()
            and path.suffix.lower() not in {".part", ".json"}
            and not path.name.endswith(".info.json")
        ]
        if not matches:
            return None
        mp4 = [path for path in matches if path.suffix.lower() == ".mp4"]
        ranked = mp4 or matches
        ranked.sort(key=lambda path: path.stat().st_size, reverse=True)
        return ranked[0]

    @staticmethod
    def _has_video_like_format(info: dict[str, Any], formats: list[dict[str, Any]]) -> bool:
        samples = list(formats)
        if info.get("url"):
            samples.append(
                {
                    "url": info.get("url"),
                    "ext": info.get("ext"),
                    "protocol": info.get("protocol"),
                    "vcodec": info.get("vcodec"),
                    "acodec": info.get("acodec"),
                    "mime_type": info.get("mime_type") or info.get("mimetype"),
                    "format": info.get("format"),
                }
            )
        for fmt in samples:
            url = str(fmt.get("url") or "")
            protocol = str(fmt.get("protocol") or "").lower()
            ext = str(fmt.get("ext") or "").lower()
            vcodec = str(fmt.get("vcodec") or "").lower()
            acodec = str(fmt.get("acodec") or "").lower()
            mime_type = str(fmt.get("mime_type") or fmt.get("mimetype") or "").lower()
            label = str(fmt.get("format") or fmt.get("format_note") or "").lower()
            if vcodec == "none" and acodec != "none":
                continue
            if "m3u8" in protocol or url.endswith(".m3u8"):
                return True
            if ext in {"mp4", "webm", "mkv", "mov"}:
                return True
            if "video" in mime_type:
                return True
            if vcodec not in {"", "none", "unknown"} and url.startswith(("http://", "https://")):
                return True
            if "video" in label and url.startswith(("http://", "https://")):
                return True
        return False

    def _media_from_format(self, fmt: dict[str, Any]) -> Optional[UniversalMedia]:
        url = fmt.get("url")
        if not isinstance(url, str) or not url.startswith(("http://", "https://")):
            return None

        ext = str(fmt.get("ext") or "").lower()
        protocol = str(fmt.get("protocol") or "").lower()
        vcodec = str(fmt.get("vcodec") or "").lower()
        acodec = str(fmt.get("acodec") or "").lower()
        mime_type = str(fmt.get("mime_type") or fmt.get("mimetype") or "").lower()

        if "m3u8" in protocol or url.endswith(".m3u8"):
            return None
        if vcodec == "none" and acodec != "none":
            return None

        looks_video = (
            ext in {"mp4", "webm", "mkv", "mov"}
            or self._url_looks_like_video(url, key_hint=str(fmt.get("format") or fmt.get("format_note") or ""))
            or "video" in mime_type
            or vcodec not in {"", "none", "unknown"}
        )
        if not looks_video:
            return None

        width = self._int_or_none(fmt.get("width"))
        height = self._int_or_none(fmt.get("height"))
        filesize = self._int_or_none(fmt.get("filesize") or fmt.get("filesize_approx"))
        return UniversalMedia(
            media_type="video",
            url=url,
            mime_type="video/mp4",
            width=width,
            height=height,
            filesize=filesize,
            quality=str(fmt.get("format_note") or self._quality_label(width, height) or "video"),
        )

    def _deep_media_candidates(self, value: Any, key_hint: str = "", seen_nodes: Optional[set[int]] = None) -> list[UniversalMedia]:
        seen_nodes = seen_nodes if seen_nodes is not None else set()
        if len(seen_nodes) > self._MAX_DEEP_SCAN_NODES:
            return []

        obj_id = id(value)
        if isinstance(value, (dict, list, tuple, set)):
            if obj_id in seen_nodes:
                return []
            seen_nodes.add(obj_id)

        out: list[UniversalMedia] = []
        if isinstance(value, str):
            out.extend(self._media_from_text(value, key_hint=key_hint))
        elif isinstance(value, dict):
            width = self._int_or_none(value.get("width"))
            height = self._int_or_none(value.get("height"))
            for key, item in value.items():
                child_hint = f"{key_hint} {key}".strip()
                if isinstance(item, str):
                    direct = self._media_from_url(item, key_hint=child_hint, width=width, height=height)
                    if direct:
                        out.append(direct)
                    else:
                        out.extend(self._media_from_text(item, key_hint=child_hint))
                else:
                    out.extend(self._deep_media_candidates(item, key_hint=child_hint, seen_nodes=seen_nodes))
        elif isinstance(value, (list, tuple, set)):
            for item in value:
                out.extend(self._deep_media_candidates(item, key_hint=key_hint, seen_nodes=seen_nodes))
        return self._dedupe_media(out)

    def _media_from_text(self, text: str, key_hint: str = "") -> list[UniversalMedia]:
        text = self._decode_url_text(text)
        urls = re.findall(r"https?:\\?/\\?/[^\"'<>\s]+", text)
        return [item for raw in urls if (item := self._media_from_url(raw, key_hint=key_hint))]

    def _media_from_url(self, raw_url: str, key_hint: str = "", width: Any = None, height: Any = None) -> Optional[UniversalMedia]:
        url = self._decode_url_text(raw_url).strip().strip('"\'')
        if not url.startswith(("http://", "https://")) or self._is_static_asset_url(url):
            return None
        width_i = self._int_or_none(width)
        height_i = self._int_or_none(height)
        if self._url_looks_like_video(url, key_hint=key_hint):
            return UniversalMedia(
                media_type="video",
                url=url,
                mime_type="video/mp4",
                width=width_i,
                height=height_i,
                quality=self._quality_label(width_i, height_i) or "video",
            )
        if self._url_looks_like_image(url, key_hint=key_hint):
            return UniversalMedia(
                media_type="image",
                url=url,
                mime_type=self._image_mime_type(url),
                width=width_i,
                height=height_i,
                quality=self._quality_label(width_i, height_i) or "image",
            )
        return None

    @staticmethod
    def _decode_url_text(value: str) -> str:
        value = value.replace(r"\/", "/").replace(r"\u0026", "&").replace(r"\u003d", "=").replace(r"\u003D", "=")
        value = value.replace("&amp;", "&")
        try:
            return unquote(value)
        except Exception:
            return value

    @staticmethod
    def _is_static_asset_url(url: str) -> bool:
        lower = url.lower()
        blocked = (
            "/rsrc.php/",
            "/static/",
            "sprite",
            "favicon",
            "profile_pic",
            ".css",
            ".js",
            ".svg",
            "mime=audio",
            "mime_type=audio",
            "/audio/",
        )
        return any(token in lower for token in blocked)

    def _url_looks_like_video(self, url: str, key_hint: str = "") -> bool:
        lower = url.lower()
        hint = key_hint.lower()
        parsed = urlparse(url)
        host = parsed.hostname or ""
        snap_candidate = host.endswith("sc-cdn.net") and (
            "video" in hint or "play" in hint or "/media/" in lower or "/video/" in lower or "mime=video" in lower
        )
        return (
            lower.startswith(("http://", "https://"))
            and not self._is_static_asset_url(url)
            and ".m3u8" not in lower
            and "mpegurl" not in lower
            and (
                ".mp4" in lower
                or "mime_type=video" in lower
                or "mime=video" in lower
                or "video/mp4" in lower
                or "video_mp4" in lower
                or "format=mp4" in lower
                or "/video/" in lower
                or "playable_url" in hint
                or "playback_url" in hint
                or "video_url" in hint
                or snap_candidate
            )
        )

    def _url_looks_like_image(self, url: str, key_hint: str = "") -> bool:
        lower = url.lower()
        hint = key_hint.lower()
        return (
            lower.startswith(("http://", "https://"))
            and not self._is_static_asset_url(url)
            and (
                ".jpg" in lower
                or ".jpeg" in lower
                or ".png" in lower
                or ".webp" in lower
                or ".gif" in lower
                or "mime=image" in lower
                or "image/jpeg" in lower
                or "image/webp" in lower
                or "image/png" in lower
                or "image_url" in hint
                or "display_url" in hint
                or "thumbnail" in hint
                or "og:image" in hint
                or "url_list" in hint
                or "urllist" in hint
                or "carousel" in hint
                or "photomode" in hint
                or ("tiktokcdn" in lower and any(token in hint for token in ("image", "photo", "display", "slide")))
            )
        )

    @staticmethod
    def _image_mime_type(url: str) -> str:
        lower = url.lower()
        if ".gif" in lower or "image/gif" in lower:
            return "image/gif"
        if ".png" in lower or "image/png" in lower:
            return "image/png"
        if ".webp" in lower or "image/webp" in lower:
            return "image/webp"
        return "image/jpeg"

    def _dedupe_media(self, items: list[UniversalMedia]) -> list[UniversalMedia]:
        unique: dict[str, UniversalMedia] = {}
        for item in items:
            key = self._media_identity_key(item)
            existing = unique.get(key)
            if existing is None or self._media_rank(item) > self._media_rank(existing):
                unique[key] = item
        return list(unique.values())

    @staticmethod
    def _media_identity_key(item: UniversalMedia) -> str:
        parsed = urlparse(item.url)
        if not parsed.hostname:
            return f"{item.media_type}:{item.url}"
        host = parsed.hostname.lower()
        path = parsed.path or item.url
        return f"{item.media_type}:{host}{path}"

    @staticmethod
    def _media_rank(item: UniversalMedia) -> tuple[int, int, int]:
        pixels = (item.width or 0) * (item.height or 0)
        kind_score = 2 if item.media_type == "video" else 1
        return (kind_score, pixels, item.filesize or 0)

    @staticmethod
    def _int_or_none(value: Any) -> Optional[int]:
        try:
            return int(value) if value is not None else None
        except Exception:
            return None

    @staticmethod
    def _quality_label(width: Any, height: Any) -> Optional[str]:
        try:
            if height:
                return f"{int(height)}p"
            if width:
                return f"{int(width)}w"
        except Exception:
            return None
        return None


universal_provider = UniversalProvider()
