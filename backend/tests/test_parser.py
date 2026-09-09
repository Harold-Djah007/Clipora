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
