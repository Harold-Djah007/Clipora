import json

from app.services.platforms import Platform
from app.services.social_page_provider import PublicSocialPageExtractor


def test_instagram_photo_uses_open_graph_image_when_no_video_exists():
    source = """
    <meta content="Public photo caption" property="og:description">
    <meta property="og:image" content="https://scontent.cdninstagram.com/photo.webp?token=abc">
    """
    info = PublicSocialPageExtractor().parse(
        source, "https://www.instagram.com/p/DdS6nOnII6h/", Platform.INSTAGRAM
    )
    assert info["description"] == "Public photo caption"
    assert len(info["entries"]) == 1
    assert info["entries"][0]["ext"] == "webp"


def test_open_graph_video_wins_over_its_poster():
    source = """
    <meta property="og:image" content="https://cdn.example/poster.jpg">
    <meta content="https://cdn.example/story.mp4?token=abc" property="og:video">
    """
    info = PublicSocialPageExtractor().parse(
        source,
        "https://www.snapchat.com/spotlight/W7_EDlXWTBiXAEEniNoMPwAAY",
        Platform.SNAPCHAT,
    )
    assert len(info["entries"]) == 1
    assert info["entries"][0]["url"].startswith("https://cdn.example/story.mp4")
    assert info["entries"][0]["vcodec"] == "unknown"


def test_snapchat_hydration_media_url_is_detected_without_file_extension():
    source = json.dumps(
        {"snapList": [{"mediaUrl": "https://cf-st.sc-cdn.net/snap/video-token?mime=video_mp4"}]}
    )
    info = PublicSocialPageExtractor().parse(
        source,
        "https://www.snapchat.com/spotlight/W7_EDlXWTBiXAEEniNoMPwAAY",
        Platform.SNAPCHAT,
    )
    assert info["entries"][0]["url"].endswith("mime=video_mp4")
    assert info["entries"][0]["ext"] == "mp4"


def test_tiktok_oembed_recovers_canonical_url_when_short_redirect_is_homepage(monkeypatch):
    extractor = PublicSocialPageExtractor()
    canonical = "https://www.tiktok.com/@creator/video/7682000490246262048"

    class Response:
        status_code = 200
        url = "https://www.tiktok.com/?_r=1"
        headers = {}
        history = []
        text = ""

        @staticmethod
        def json():
            return {"html": f'<blockquote cite="{canonical}"></blockquote>'}

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def get(self, url, params=None):
            return Response()

        def head(self, url):
            return Response()

    monkeypatch.setattr("app.services.social_page_provider.httpx.Client", Client)
    assert extractor.expand_tiktok_short_url("https://vt.tiktok.com/ZSgXvo3cB/") == canonical


def test_public_page_parser_rejects_non_https_media():
    source = '<meta property="og:image" content="http://127.0.0.1/private.jpg">'
    try:
        PublicSocialPageExtractor().parse(
            source, "https://www.instagram.com/p/example/", Platform.INSTAGRAM
        )
    except Exception as error:
        assert "No downloadable" in str(error)
    else:
        raise AssertionError("Expected unsafe image URL to be rejected")
