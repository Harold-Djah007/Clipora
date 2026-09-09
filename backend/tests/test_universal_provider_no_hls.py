from pathlib import Path

from app.services.file_cache import MediaFileCache
from app.services.universal_provider import UniversalProvider


def test_hls_manifest_is_not_returned_as_direct_mobile_file():
    provider = UniversalProvider()
    info = {
        "formats": [
            {"url": "https://cdn.example/master.m3u8", "ext": "mp4", "height": 1080, "protocol": "m3u8_native"},
        ]
    }

    assert provider._extract_media_items(info) == []


def test_hls_video_does_not_fall_back_to_thumbnail():
    provider = UniversalProvider()
    info = {
        "formats": [
            {"url": "https://cdn.example/master.m3u8", "ext": "mp4", "height": 1080, "protocol": "m3u8_native", "vcodec": "h264"},
        ],
        "thumbnails": [
            {"url": "https://cdn.example/poster.jpg", "width": 1080, "height": 1920},
        ],
    }

    assert provider._extract_media_items(info) == []


def test_file_cache_roundtrip(tmp_path):
    cache = MediaFileCache()
    source = tmp_path / "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.mp4"
    source.write_bytes(b"ftypfake")
    token = cache.put(source, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    assert cache.get(token) == source
    assert cache.get("not-a-token") is None
