import asyncio

from app.services.threads_provider import HttpThreadsProvider, ThreadsHtmlParser


def test_threads_parser_keeps_highest_video_variant():
    source = r'''
      <html><script>
      {"video_versions":[
        {"width":360,"height":640,"url":"https:\/\/scontent.cdninstagram.com\/v\/t1\/low.mp4?x=1"},
        {"width":1080,"height":1920,"url":"https:\/\/scontent.cdninstagram.com\/v\/t1\/hd.mp4?x=2"}
      ]}
      </script></html>
    '''
    post = ThreadsHtmlParser().parse(source, "https://www.threads.com/@alice/post/ABC")
    assert post.author == "alice"
    assert post.post_id == "ABC"
    assert len(post.media) == 1
    assert post.media[0].media_type == "video"
    assert "hd.mp4" in post.media[0].url


def test_threads_parser_uses_canonical_share_identity():
    source = '''
      <link rel="canonical" href="https://www.threads.com/@bob/post/XYZ">
      <script>{"video_versions":[{"url":"https://scontent.cdninstagram.com/v/t1/real.mp4"}]}</script>
    '''
    post = ThreadsHtmlParser().parse(source, "https://www.threads.com/share/short123")
    assert post.author == "bob"
    assert post.post_id == "XYZ"
    assert post.media[0].media_type == "video"


def test_threads_parser_uses_short_t_identity():
    source = '''
      <link rel="canonical" href="https://www.threads.net/t/CuABC123">
      <script>{"video_versions":[{"url":"https://scontent.cdninstagram.com/v/t1/real.mp4"}]}</script>
    '''
    post = ThreadsHtmlParser().parse(source, "https://www.threads.net/t/CuABC123")
    assert post.post_id == "CuABC123"
    assert post.media[0].media_type == "video"


def test_threads_parser_keeps_photo_carousel():
    source = r'''
      {"image_versions2":{"candidates":[
        {"width":320,"url":"https://scontent.cdninstagram.com/v/t51/a.jpg"},
        {"width":1440,"url":"https://scontent.cdninstagram.com/v/t51/a-hi.jpg"}
      ]}}
      {"image_versions2":{"candidates":[
        {"width":1440,"url":"https://scontent.cdninstagram.com/v/t51/b.jpg"}
      ]}}
    '''
    post = ThreadsHtmlParser().parse(source, "https://www.threads.com/@alice/post/PHOTO1")
    assert [item.media_type for item in post.media] == ["image", "image"]
    assert post.media[0].url.endswith("a-hi.jpg")
    assert post.media[1].url.endswith("b.jpg")


def test_threads_parser_keeps_mixed_carousel_slides():
    source = r'''
      {"carousel_media":[
        {"video_versions":[{"url":"https://scontent.cdninstagram.com/v/t1/clip.mp4","width":720,"height":1280}],
         "image_versions2":{"candidates":[{"url":"https://scontent.cdninstagram.com/v/t51/poster.jpg"}]}},
        {"image_versions2":{"candidates":[{"width":1440,"url":"https://scontent.cdninstagram.com/v/t51/photo.jpg"}]}}
      ]}
    '''
    post = ThreadsHtmlParser().parse(source, "https://www.threads.com/@alice/post/MIX1")
    assert [item.media_type for item in post.media] == ["video", "image"]
    assert post.media[0].url.endswith("clip.mp4")
    assert post.media[1].url.endswith("photo.jpg")


def test_threads_parser_drops_poster_when_video_exists():
    source = r'''
      {"video_versions":[{"url":"https://scontent.cdninstagram.com/v/t1/real.mp4"}],
       "image_versions2":{"candidates":[{"url":"https://scontent.cdninstagram.com/v/t51/poster.jpg"}]}}
    '''
    post = ThreadsHtmlParser().parse(source, "https://www.threads.com/@alice/post/ABC")
    assert len(post.media) == 1
    assert post.media[0].media_type == "video"


def test_threads_parser_rejects_static_assets():
    source = '{"video_versions":[{"url":"https://static.cdninstagram.com/rsrc.php/v4/ui.mp4"}]}'
    try:
        ThreadsHtmlParser().parse(source, "https://www.threads.com/@a/post/b")
        assert False, "expected parser to reject static assets"
    except ValueError as exc:
        assert "No downloadable media" in str(exc)
        assert "did not return a public photo or video" in str(exc)


def test_http_threads_follows_share_redirect(monkeypatch):
    html = '{"video_versions":[{"url":"https://scontent.cdninstagram.com/v/t1/real.mp4"}]}'
    canonical = "https://www.threads.com/@bob/post/XYZ"

    class Response:
        def __init__(self, url, location="", text="", status=200):
            self.url = url
            self.headers = {"location": location} if location else {}
            self.text = text
            self.status_code = status

        def raise_for_status(self):
            if self.status_code >= 400:
                raise RuntimeError(f"HTTP {self.status_code}")

    class Client:
        def __init__(self, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return False

        async def get(self, url):
            if "/share/" in url:
                return Response(url, location=canonical, status=302)
            return Response(canonical, text=html)

    monkeypatch.setattr("app.services.threads_provider.httpx.AsyncClient", Client)
    post = asyncio.run(HttpThreadsProvider().resolve("https://www.threads.com/share/short123"))
    assert post.post_id == "XYZ"
    assert post.author == "bob"
    assert post.media[0].media_type == "video"


def test_http_threads_prefers_video_html_over_og_image(monkeypatch):
    poster = '<meta property="og:image" content="https://scontent.cdninstagram.com/v/t51/poster.jpg">'
    video = '{"video_versions":[{"url":"https://scontent.cdninstagram.com/v/t1/real.mp4"}]}'

    class Response:
        def __init__(self, text):
            self.url = "https://www.threads.com/@alice/post/ABC"
            self.headers = {}
            self.text = text
            self.status_code = 200

        def raise_for_status(self):
            return None

    class Client:
        def __init__(self, **kwargs):
            self.headers = kwargs.get("headers") or {}

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return False

        async def get(self, url):
            ua = str(self.headers.get("User-Agent") or "")
            if "Chrome/131" in ua:
                return Response(poster)
            return Response(video)

    monkeypatch.setattr("app.services.threads_provider.httpx.AsyncClient", Client)
    post = asyncio.run(HttpThreadsProvider().resolve("https://www.threads.com/@alice/post/ABC"))
    assert len(post.media) == 1
    assert post.media[0].media_type == "video"
    assert post.media[0].url.endswith("real.mp4")
