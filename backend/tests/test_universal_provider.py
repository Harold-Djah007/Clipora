import asyncio

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


def test_gif_is_preserved_as_downloadable_image():
    provider = UniversalProvider()
    media = provider._extract_media_items({"url": "https://cdn.example/animation.gif", "ext": "gif"})

    assert len(media) == 1
    assert media[0].media_type == "image"
    assert media[0].mime_type == "image/gif"


def test_resolve_keeps_every_video_entry(monkeypatch):
    provider = UniversalProvider()
    info = {
        "id": "carousel",
        "uploader": "creator",
        "entries": [
            {
                "id": "one",
                "webpage_url": "https://x.com/creator/status/1",
                "formats": [
                    {"url": "https://cdn.example/clip-a.mp4", "ext": "mp4", "height": 720, "width": 1280, "vcodec": "h264"},
                ],
            },
            {
                "id": "two",
                "webpage_url": "https://x.com/creator/status/2",
                "formats": [
                    {"url": "https://cdn.example/clip-b.mp4", "ext": "mp4", "height": 1080, "width": 1920, "vcodec": "h264"},
                ],
            },
        ],
    }

    monkeypatch.setattr(provider, "_extract_info", lambda url: info)
    monkeypatch.setattr(provider, "_download_to_cache", lambda url, entry, index=1: provider._extract_media_items(entry))

    post = asyncio.run(provider._resolve_with_ytdlp("https://x.com/creator/status/carousel"))

    assert [item.url for item in post.media] == [
        "https://cdn.example/clip-a.mp4",
        "https://cdn.example/clip-b.mp4",
    ]


def test_resolve_caps_carousel_entries_at_twenty(monkeypatch):
    provider = UniversalProvider()
    entries = [
        {
            "id": str(index),
            "webpage_url": f"https://x.com/creator/status/{index}",
            "formats": [
                {"url": f"https://cdn.example/clip-{index}.mp4", "ext": "mp4", "height": 720, "width": 1280, "vcodec": "h264"},
            ],
        }
        for index in range(25)
    ]
    info = {"id": "big-carousel", "uploader": "creator", "entries": entries}

    monkeypatch.setattr(provider, "_extract_info", lambda url: info)
    monkeypatch.setattr(provider, "_download_to_cache", lambda url, entry, index=1: provider._extract_media_items(entry))

    post = asyncio.run(provider._resolve_with_ytdlp("https://x.com/creator/status/big-carousel"))

    assert len(post.media) == 20
    assert post.media[0].url.endswith("clip-0.mp4")
    assert post.media[-1].url.endswith("clip-19.mp4")

def test_tiktok_does_not_force_headers_that_break_short_link_expansion():
    provider = UniversalProvider()

    opts = provider._ydl_opts_for("https://vt.tiktok.com/example/")
    headers = opts["http_headers"]

    assert "User-Agent" not in headers
    assert "Referer" not in headers
    assert headers["Accept-Language"] == "en-US,en;q=0.9"


def test_tiktok_short_link_expansion_accepts_only_canonical_video(monkeypatch):
    provider = UniversalProvider()

    class Response:
        url = "https://www.tiktok.com/@creator/video/7682000490246262048"
        headers = {}
        text = ""

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def get(self, url):
            return Response()

    monkeypatch.setattr("app.services.universal_provider.httpx.Client", Client)
    expanded = provider._expand_tiktok_short_url("https://vt.tiktok.com/ZSgU4uAMT/")
    assert expanded == Response.url


def test_tiktok_short_link_expansion_rejects_homepage_redirect(monkeypatch):
    provider = UniversalProvider()

    class Response:
        url = "https://www.tiktok.com/?_r=1"
        headers = {}
        text = ""

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def get(self, url):
            return Response()

    monkeypatch.setattr("app.services.universal_provider.httpx.Client", Client)
    short = "https://vt.tiktok.com/ZSgU4uAMT/"
    assert provider._expand_tiktok_short_url(short) == short
