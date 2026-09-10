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


def test_extracts_nested_story_media_urls_like_server_downloader_apis():
    provider = UniversalProvider()
    info = {
        "id": "story-1",
        "snapList": [
            {"mediaUrl": "https://cf-st.sc-cdn.net/snap/video-token?mime=video_mp4", "width": 1080, "height": 1920},
            {"imageUrl": "https://cf-st.sc-cdn.net/snap/photo.webp?mime=image", "width": 1080, "height": 1920},
        ],
    }

    media = provider._extract_media_items(info)

    assert [item.media_type for item in media] == ["video"]
    assert media[0].url.startswith("https://cf-st.sc-cdn.net/snap/video-token")


def test_photo_carousel_keeps_multiple_images_when_no_video_hint_exists():
    provider = UniversalProvider()
    info = {
        "items": [
            {"display_url": "https://cdn.example/slide-1.jpg", "width": 1080, "height": 1350},
            {"display_url": "https://cdn.example/slide-2.jpg", "width": 1080, "height": 1350},
        ],
    }

    media = provider._extract_media_items(info)

    assert [item.url for item in media] == ["https://cdn.example/slide-1.jpg", "https://cdn.example/slide-2.jpg"]


def test_video_format_variants_keep_best_quality_only():
    provider = UniversalProvider()
    info = {
        "formats": [
            {"url": "https://video.example/clip.mp4?token=low", "ext": "mp4", "height": 360, "width": 640},
            {"url": "https://video.example/clip.mp4?token=high", "ext": "mp4", "height": 1080, "width": 1920},
        ]
    }

    media = provider._extract_media_items(info)

    assert len(media) == 1
    assert media[0].height == 1080
    assert media[0].url.endswith("token=high")


def test_dedupe_uses_host_and_path_for_signed_media_tokens():
    provider = UniversalProvider()
    items = [
        provider._media_from_url("https://cdn.example/path/video.mp4?token=old", key_hint="video", width=640, height=360),
        provider._media_from_url("https://cdn.example/path/video.mp4?token=new", key_hint="video", width=1080, height=1920),
    ]

    media = provider._dedupe_media([item for item in items if item])

    assert len(media) == 1
    assert media[0].height == 1920
    assert media[0].url.endswith("token=new")


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
