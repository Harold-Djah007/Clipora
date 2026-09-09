from __future__ import annotations

import asyncio
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

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

    This provider deliberately does not implement watermark-removal behavior and does not
    accept platform passwords. It resolves public/share links through yt-dlp where that is
    supported, and keeps Threads on the existing local-session-aware resolver.
    """

    _ydl_opts: dict[str, Any] = {
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        "merge_output_format": "mp4",
        "user_agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/115.0.0.0 Safari/537.36"
        ),
    }

    async def resolve(self, url: str, session_blob: Optional[str] = None) -> UniversalPost:
        platform_info = ensure_supported_platform(url)
        if platform_info.platform == Platform.THREADS:
            return await self._resolve_threads(url, session_blob)
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

    async def _resolve_threads(self, url: str, session_blob: Optional[str]) -> UniversalPost:
        post = await threads_provider.resolve(url, session_blob)
        return UniversalPost(
            post_id=post.post_id,
            author=post.author,
            platform=Platform.THREADS.value,
            source_url=url,
            title=None,
            caption=post.caption,
            media=[
                UniversalMedia(
                    media_type=item.media_type,
                    url=item.url,
                    width=item.width,
                    height=item.height,
                    quality=self._quality_label(item.width, item.height),
                )
                for item in post.media
            ],
        )

    async def _resolve_with_ytdlp(self, url: str) -> UniversalPost:
        if yt_dlp is None:
            raise RuntimeError("yt-dlp is not installed. Run: pip install -r backend/requirements.txt")

        loop = asyncio.get_running_loop()
        info = await loop.run_in_executor(None, self._extract_info, url)
        media = self._extract_media_items(info)
        video_like = self._has_video_like_format(info, self._formats(info))

        if video_like:
            # Phone/CDN direct downloads can be rejected with 403 even when yt-dlp can
            # resolve the link. For universal video saves, make the PC backend fetch
            # the file first and let the phone download it from /api/files/{token}.
            # This fixes TikTok signed-CDN failures and keeps Threads on its old guard.
            try:
                media = await loop.run_in_executor(None, self._download_to_cache, url, info)
            except Exception:
                if not media:
                    raise

        if not media:
            # Additive fallback: download HLS/DASH to a local MP4 and let the phone
            # fetch /api/files/{token}. Direct-MP4 posts normally use the same cache
            # path above so platform CDNs do not reject the Android downloader.
            media = await loop.run_in_executor(None, self._download_to_cache, url, info)
        if not media:
            raise ValueError("No downloadable MP4/image media found for this link.")

        platform_info = ensure_supported_platform(url)
        post_id = safe_filename_part(str(info.get("id") or info.get("display_id") or "clipora"))
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
        with yt_dlp.YoutubeDL(self._ydl_opts) as ydl:  # type: ignore[union-attr]
            info = ydl.extract_info(url, download=False)
            if isinstance(info, dict) and "entries" in info and info["entries"]:
                first = next((entry for entry in info["entries"] if entry), None)
                if first:
                    return first
            if not isinstance(info, dict):
                raise ValueError("yt-dlp returned an unsupported response.")
            return info

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
            }
        )
        if direct_video:
            return [direct_video]

        formats = self._formats(info)
        candidates = [item for item in (self._media_from_format(fmt) for fmt in formats) if item]
        candidates.sort(key=lambda item: ((item.height or 0), (item.filesize or 0)), reverse=True)
        if candidates:
            return [candidates[0]]

        # If yt-dlp only found HLS/DASH, do not return a poster JPG. The file-fallback
        # path downloads a real video instead of saving the thumbnail.
        if self._has_video_like_format(info, formats):
            return []

        # Photo-only posts: use the largest thumbnail only when no video candidate exists.
        thumbnails = [thumb for thumb in info.get("thumbnails") or [] if isinstance(thumb, dict)]
        image_candidates = []
        for thumb in thumbnails:
            thumb_url = thumb.get("url")
            if not isinstance(thumb_url, str) or not thumb_url.startswith(("http://", "https://")):
                continue
            image_candidates.append(
                UniversalMedia(
                    media_type="image",
                    url=thumb_url,
                    width=self._int_or_none(thumb.get("width")),
                    height=self._int_or_none(thumb.get("height")),
                    quality=self._quality_label(thumb.get("width"), thumb.get("height")),
                )
            )
        image_candidates.sort(key=lambda item: ((item.width or 0) * (item.height or 0)), reverse=True)
        return image_candidates[:1]

    def _download_to_cache(self, url: str, info: dict[str, Any]) -> list[UniversalMedia]:
        if yt_dlp is None:
            raise RuntimeError("yt-dlp is not installed. Run: pip install -r backend/requirements.txt")

        cache_dir = Path(tempfile.gettempdir()) / "clipora-media"
        cache_dir.mkdir(parents=True, exist_ok=True)
        token = uuid.uuid4().hex
        opts = {
            **self._ydl_opts,
            "skip_download": False,
            "outtmpl": str(cache_dir / f"{token}.%(ext)s"),
            "merge_output_format": "mp4",
            "overwrites": True,
            "noprogress": True,
            "socket_timeout": 30,
        }
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:  # type: ignore[union-attr]
                downloaded = ydl.extract_info(url, download=True)
        except Exception as exc:
            raise ValueError(
                "Clipora resolved the post, but the backend could not prepare the media file. "
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
        media_type = "image" if suffix in {".jpg", ".jpeg", ".png", ".webp"} else "video"
        downloaded_info = downloaded if isinstance(downloaded, dict) else {}
        width = self._int_or_none(downloaded_info.get("width")) or self._int_or_none(info.get("width"))
        height = self._int_or_none(downloaded_info.get("height")) or self._int_or_none(info.get("height"))
        return [
            UniversalMedia(
                media_type=media_type,
                url=f"/api/files/{token}",
                width=width,
                height=height,
                filesize=path.stat().st_size,
                quality=str(downloaded_info.get("format_note") or self._quality_label(width, height) or "downloaded"),
            )
        ]

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
    def _formats(info: dict[str, Any]) -> list[dict[str, Any]]:
        return [fmt for fmt in info.get("formats") or [] if isinstance(fmt, dict)]

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
                }
            )
        for fmt in samples:
            url = str(fmt.get("url") or "")
            protocol = str(fmt.get("protocol") or "").lower()
            ext = str(fmt.get("ext") or "").lower()
            vcodec = str(fmt.get("vcodec") or "").lower()
            if vcodec == "none":
                continue
            if "m3u8" in protocol or url.endswith(".m3u8") or ext in {"mp4", "webm", "mkv", "mov"}:
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

        # Direct mobile downloads still prefer real MP4 files. HLS manifests are
        # skipped here and handled by the file-fallback downloader instead.
        if "m3u8" in protocol or url.endswith(".m3u8"):
            return None
        if ext != "mp4" and ".mp4" not in url.lower():
            return None
        if vcodec == "none" and acodec != "none":
            return None

        width = self._int_or_none(fmt.get("width"))
        height = self._int_or_none(fmt.get("height"))
        filesize = self._int_or_none(fmt.get("filesize") or fmt.get("filesize_approx"))
        return UniversalMedia(
            media_type="video",
            url=url,
            width=width,
            height=height,
            filesize=filesize,
            quality=str(fmt.get("format_note") or self._quality_label(width, height) or "mp4"),
        )

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
