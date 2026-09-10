import asyncio

from app.services.universal_provider import UniversalMedia, UniversalProvider


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


def test_tiktok_short_link_follows_location_header_without_following_homepage(monkeypatch):
    provider = UniversalProvider()
    short = "https://vt.tiktok.com/ZSqU4uAMT/"
    canonical = "https://www.tiktok.com/@creator/video/7682000490246262048"

    class Response:
        def __init__(self, url, location=""):
            self.url = url
            self.headers = {"location": location} if location else {}
            self.text = ""

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def get(self, url):
            if "vt.tiktok.com" in url:
                return Response(url, location=canonical)
            return Response(url)

    monkeypatch.setattr("app.services.universal_provider.httpx.Client", Client)
    assert provider._expand_tiktok_short_url(short) == canonical


def test_tiktok_short_link_parses_video_id_from_homepage_html(monkeypatch):
    provider = UniversalProvider()
    short = "https://vt.tiktok.com/ZSqU4uAMT/"

    class Response:
        def __init__(self, url, location="", text=""):
            self.url = url
            self.headers = {"location": location} if location else {}
            self.text = text

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def get(self, url):
            if "vt.tiktok.com" in url:
                return Response(url, location="https://www.tiktok.com/?_r=1")
            return Response(
                "https://www.tiktok.com/?_r=1",
                text='<link rel="canonical" href="https://www.tiktok.com/@creator/video/7682000490246262048">',
            )

    monkeypatch.setattr("app.services.universal_provider.httpx.Client", Client)
    assert provider._expand_tiktok_short_url(short) == "https://www.tiktok.com/@creator/video/7682000490246262048"


def test_tiktok_webpage_download_is_enabled_for_photo_posts():
    provider = UniversalProvider()
    opts = provider._ydl_opts_for("https://www.tiktok.com/@creator/photo/1234567890123456789")
    assert opts["extractor_args"]["tiktok"]["webpage_download"] == ["True"]
    assert "User-Agent" not in opts["http_headers"]


def test_tiktok_slideshow_images_when_no_video_exists():
    provider = UniversalProvider()
    info = {
        "image_post_info": {
            "images": [
                {"imageURL": {"urlList": ["https://p16-sign.tiktokcdn.com/tos-a.jpeg"]}},
                {"display_image": {"url_list": ["https://p16-sign.tiktokcdn.com/tos-b.jpeg"]}},
            ]
        }
    }

    media = provider._extract_media_items(info)

    assert [item.url for item in media] == [
        "https://p16-sign.tiktokcdn.com/tos-a.jpeg",
        "https://p16-sign.tiktokcdn.com/tos-b.jpeg",
    ]
    assert all(item.media_type == "image" for item in media)


def test_instagram_carousel_media_keeps_each_slide():
    provider = UniversalProvider()
    info = {
        "carousel_media": [
            {
                "image_versions2": {
                    "candidates": [
                        {"url": "https://scontent.cdninstagram.com/v/t51/a.jpg", "width": 320, "height": 320},
                        {"url": "https://scontent.cdninstagram.com/v/t51/a-1080.jpg", "width": 1080, "height": 1080},
                    ]
                }
            },
            {
                "image_versions2": {
                    "candidates": [
                        {"url": "https://scontent.cdninstagram.com/v/t51/b.jpg", "width": 1080, "height": 1350},
                    ]
                }
            },
        ]
    }

    media = provider._extract_media_items(info)

    assert [item.url for item in media] == [
        "https://scontent.cdninstagram.com/v/t51/a-1080.jpg",
        "https://scontent.cdninstagram.com/v/t51/b.jpg",
    ]


def test_tiktok_photo_images_are_not_used_when_video_exists():
    provider = UniversalProvider()
    info = {
        "formats": [
            {"url": "https://cdn.example/video.mp4", "ext": "mp4", "vcodec": "h264", "height": 720, "width": 1280},
        ],
        "images": ["https://cdn.example/slide.jpg"],
    }

    media = provider._extract_media_items(info)

    assert len(media) == 1
    assert media[0].media_type == "video"
    assert media[0].url.endswith("video.mp4")


def test_tiktok_download_fallback_when_metadata_has_no_media(monkeypatch):
    provider = UniversalProvider()
    info = {"id": "7682000490246262048", "uploader": "creator", "title": "clip"}
    monkeypatch.setattr(provider, "_extract_info", lambda url: info)
    monkeypatch.setattr(
        provider,
        "_download_to_cache",
        lambda url, entry, index=1: [
            UniversalMedia(media_type="video", url="/api/files/abc", mime_type="video/mp4")
        ],
    )

    post = asyncio.run(provider._resolve_with_ytdlp("https://www.tiktok.com/@creator/video/7682000490246262048"))

    assert post.media[0].url == "/api/files/abc"
    assert post.platform == "tiktok"


def test_tiktok_download_fallback_when_extract_raises(monkeypatch):
    provider = UniversalProvider()
    monkeypatch.setattr(
        provider,
        "_expand_tiktok_short_url",
        lambda url: "https://www.tiktok.com/@creator/video/7682000490246262048",
    )
    monkeypatch.setattr(provider, "_extract_info", lambda url: (_ for _ in ()).throw(RuntimeError("")))
    monkeypatch.setattr(
        provider,
        "_download_to_cache",
        lambda url, entry, index=1: [
            UniversalMedia(media_type="video", url="/api/files/fallback", mime_type="video/mp4")
        ],
    )

    post = asyncio.run(provider._resolve_with_ytdlp("https://vt.tiktok.com/ZSqU4uAMT/"))

    assert post.media[0].url == "/api/files/fallback"
    assert post.platform == "tiktok"


def test_pin_it_share_link_stays_on_pinterest(monkeypatch):
    provider = UniversalProvider()
    canonical = "https://www.pinterest.com/pin/123456789/"

    class Response:
        def __init__(self, url, location=""):
            self.url = url
            self.headers = {"location": location} if location else {}
            self.text = ""

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def get(self, url):
            if "pin.it" in url:
                return Response(url, location=canonical)
            return Response(url)

    monkeypatch.setattr("app.services.universal_provider.httpx.Client", Client)
    assert provider._expand_share_url("https://pin.it/abc123") == canonical


def test_youtube_tries_multiple_player_clients():
    from app.services.platforms import Platform

    provider = UniversalProvider()
    attempts = provider._extract_attempts(
        "https://www.youtube.com/shorts/abc",
        "https://www.youtube.com/shorts/abc",
        Platform.YOUTUBE,
        False,
    )
    clients = [opts.get("extractor_args", {}).get("youtube", {}).get("player_client") for _, opts in attempts]
    assert ["mweb", "tv"] in clients
    assert ["android", "ios"] in clients


def test_instagram_download_fallback_when_extract_raises(monkeypatch):
    provider = UniversalProvider()
    monkeypatch.setattr(provider, "_extract_info", lambda url: (_ for _ in ()).throw(RuntimeError("")))
    monkeypatch.setattr(
        provider,
        "_download_to_cache",
        lambda url, entry, index=1: [
            UniversalMedia(media_type="video", url="/api/files/ig", mime_type="video/mp4")
        ],
    )

    post = asyncio.run(provider._resolve_with_ytdlp("https://www.instagram.com/reel/ABC123/"))

    assert post.media[0].url == "/api/files/ig"
    assert post.platform == "instagram"


def test_resolve_threads_tunnels_cdn_through_files(monkeypatch):
    from app.services.threads_provider import ResolvedMedia, ResolvedPost

    provider = UniversalProvider()
    resolved = ResolvedPost(
        post_id="ABC",
        author="alice",
        caption="hi",
        media=[ResolvedMedia("video", "https://scontent.cdninstagram.com/v/t1/real.mp4", 720, 1280)],
    )

    async def fake_resolve(url):
        return resolved

    monkeypatch.setattr("app.services.universal_provider.threads_provider.resolve", fake_resolve)
    monkeypatch.setattr(
        provider,
        "_cache_http_media",
        lambda url, media_type, source_url, index=1, width=None, height=None: UniversalMedia(
            media_type=media_type,
            url="/api/files/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            mime_type="video/mp4",
            width=width,
            height=height,
        ),
    )

    post = asyncio.run(provider._resolve_threads("https://www.threads.com/@alice/post/ABC"))

    assert post.platform == "threads"
    assert post.media[0].url == "/api/files/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    assert post.media[0].media_type == "video"


def test_resolve_threads_falls_back_to_direct_cdn_when_tunnel_fails(monkeypatch):
    from app.services.threads_provider import ResolvedMedia, ResolvedPost

    provider = UniversalProvider()
    resolved = ResolvedPost(
        post_id="ABC",
        author="alice",
        caption=None,
        media=[ResolvedMedia("image", "https://scontent.cdninstagram.com/v/t51/photo.jpg", 1440, 1440)],
    )

    async def fake_resolve(url):
        return resolved

    monkeypatch.setattr("app.services.universal_provider.threads_provider.resolve", fake_resolve)
    monkeypatch.setattr(provider, "_cache_http_media", lambda *args, **kwargs: (_ for _ in ()).throw(RuntimeError("403")))

    post = asyncio.run(provider._resolve_threads("https://www.threads.com/@alice/post/ABC"))

    assert post.media[0].url == "https://scontent.cdninstagram.com/v/t51/photo.jpg"
