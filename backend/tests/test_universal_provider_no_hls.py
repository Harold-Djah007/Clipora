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


def test_video_like_url_without_mp4_extension_is_detected():
    provider = UniversalProvider()
    info = {
        "formats": [
            {
                "url": "https://cf-st.sc-cdn.net/story-media-token",
                "protocol": "https",
                "vcodec": "h264",
                "acodec": "aac",
                "height": 1920,
            },
        ],
        "thumbnails": [
            {"url": "https://cf-st.sc-cdn.net/story-poster.jpg", "width": 1080, "height": 1920},
        ],
    }

    assert provider._has_video_like_format(info, provider._formats(info)) is True
    media = provider._extract_media_items(info)
    assert len(media) == 1
    assert media[0].media_type == "video"
    assert media[0].url == "https://cf-st.sc-cdn.net/story-media-token"


def test_snapchat_story_entries_are_not_collapsed_to_one_item():
    provider = UniversalProvider()
    info = {
        "entries": [
            {
                "id": "snap-1",
                "url": "https://cf-st.sc-cdn.net/story-photo.jpg",
                "thumbnails": [
                    {"url": "https://cf-st.sc-cdn.net/story-photo.jpg", "width": 1080, "height": 1920},
                ],
            },
            {
                "id": "snap-2",
                "url": "https://cf-st.sc-cdn.net/story-video-token",
                "vcodec": "h264",
                "acodec": "aac",
                "height": 1920,
            },
        ]
    }

    entries = provider._entry_infos(info)
    assert len(entries) == 2
    media = []
    for entry in entries:
        media.extend(provider._extract_media_items(entry))

    assert [item.media_type for item in media] == ["image", "video"]


def test_metadata_retry_is_used_for_format_only_failures():
    assert UniversalProvider._should_retry_without_format(Exception("Requested format is not available")) is True
    assert UniversalProvider._should_retry_without_format(Exception("No video could be found in this tweet")) is True


def test_file_cache_roundtrip(tmp_path):
    cache = MediaFileCache()
    source = tmp_path / "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.mp4"
    source.write_bytes(b"ftypfake")
    token = cache.put(source, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    assert cache.get(token) == source
    assert cache.get("not-a-token") is None
