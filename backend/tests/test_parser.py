from app.services.threads_provider import ThreadsHtmlParser


def test_parses_progressive_video_and_metadata():
    source = r'''
    <html><head><meta property="og:description" content="hello world"></head>
    <script type="application/json">
    {"video_versions":[{"type":101,"url":"https:\/\/instagram.example.fbcdn.net\/x\/clip.mp4?a=1\u0026b=2"}]}
    </script></html>
    '''
    post = ThreadsHtmlParser().parse(source, "https://www.threads.com/@alice/post/ABC123")
    assert post.author == "alice"
    assert post.post_id == "ABC123"
    assert post.caption == "hello world"
    assert len(post.media) == 1
    assert post.media[0].url == "https://instagram.example.fbcdn.net/x/clip.mp4?a=1&b=2"


def test_rejects_source_without_media():
    try:
        ThreadsHtmlParser().parse("<html>none</html>", "https://www.threads.com/@a/post/b")
    except ValueError as exc:
        assert "No downloadable media" in str(exc)
    else:
        raise AssertionError("expected ValueError")


def test_threads_share_page_uses_canonical_url_and_open_graph_photo():
    source = """
    <meta content="https://www.threads.com/@alice/post/ABC123" property="og:url">
    <meta property="og:image" content="https://scontent.cdninstagram.com/photo.jpg?token=1">
    <meta content="Caption from share page" property="og:description">
    """
    post = ThreadsHtmlParser().parse(source, "https://www.threads.com/share/BAdSokyb0S/")
    assert post.post_id == "ABC123"
    assert post.author == "alice"
    assert post.caption == "Caption from share page"
    assert post.media[0].media_type == "image"


def test_threads_open_graph_video_does_not_return_poster():
    source = """
    <meta property="og:video" content="https://video.cdninstagram.com/clip.mp4?token=1">
    <meta property="og:image" content="https://scontent.cdninstagram.com/poster.jpg?token=1">
    """
    post = ThreadsHtmlParser().parse(source, "https://www.threads.com/@alice/post/ABC123")
    assert [item.media_type for item in post.media] == ["video"]
