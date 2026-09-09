from app.services.universal_provider import UniversalProvider


def test_extract_highest_direct_mp4_format():
    provider = UniversalProvider()
    info = {
        "formats": [
            {"url": "https://cdn.example/video-360.mp4", "ext": "mp4", "height": 360, "width": 640, "filesize": 1000, "vcodec": "h264"},
            {"url": "https://cdn.example/video-720.mp4", "ext": "mp4", "height": 720, "width": 1280, "filesize": 2000, "vcodec": "h264"},
            {"url": "https://cdn.example/audio.m4a", "ext": "m4a", "height": None, "vcodec": "none", "acodec": "aac"},
            {"url": "https://cdn.example/stream.m3u8", "ext": "mp4", "height": 1080, "protocol": "m3u8_native"},
        ]
    }

    media = provider._extract_media_items(info)

    assert len(media) == 1
    assert media[0].media_type == "video"
    assert media[0].url.endswith("video-720.mp4")
    assert media[0].quality == "720p"


def test_image_thumbnail_used_only_when_no_video_exists():
    provider = UniversalProvider()
    info = {
        "thumbnails": [
            {"url": "https://cdn.example/small.jpg", "width": 320, "height": 320},
            {"url": "https://cdn.example/large.jpg", "width": 1080, "height": 1350},
        ]
    }

    media = provider._extract_media_items(info)

    assert len(media) == 1
    assert media[0].media_type == "image"
    assert media[0].url.endswith("large.jpg")
