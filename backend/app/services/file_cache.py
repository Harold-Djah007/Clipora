from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Optional

_TOKEN = re.compile(r"^[a-f0-9]{32}$")
_TTL_SECONDS = 2 * 60 * 60


class MediaFileCache:
    """Short-lived local files produced when yt-dlp has to download HLS/DASH."""

    def __init__(self) -> None:
        self._files: dict[str, tuple[Path, float]] = {}

    def put(self, path: Path, token: str) -> str:
        if not _TOKEN.fullmatch(token):
            raise ValueError("Invalid cache token")
        self.purge()
        self._files[token] = (path, time.time())
        return token

    def get(self, token: str) -> Optional[Path]:
        if not _TOKEN.fullmatch(token):
            return None
        item = self._files.get(token)
        if not item:
            return None
        path, created = item
        if time.time() - created > _TTL_SECONDS or not path.exists():
            self._files.pop(token, None)
            return None
        return path

    def purge(self) -> None:
        now = time.time()
        expired = [
            token
            for token, (path, created) in self._files.items()
            if now - created > _TTL_SECONDS or not path.exists()
        ]
        for token in expired:
            path, _ = self._files.pop(token)
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass


media_file_cache = MediaFileCache()
