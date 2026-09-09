import pytest

from app.services.platforms import Platform, detect_platform, ensure_supported_platform, safe_filename_part


@pytest.mark.parametrize(
    ("url", "platform"),
    [
        ("https://www.threads.com/@creator/post/ABC123", Platform.THREADS),
        ("https://vm.tiktok.com/ZMtest/", Platform.TIKTOK),
        ("https://www.instagram.com/reel/ABC123/", Platform.INSTAGRAM),
        ("https://x.com/user/status/1234567890", Platform.X),
        ("https://twitter.com/user/status/1234567890", Platform.X),
        ("https://pin.it/abc123", Platform.PINTEREST),
        ("https://fb.watch/abc123/", Platform.FACEBOOK),
        ("https://story.snapchat.com/p/example", Platform.SNAPCHAT),
        ("https://youtu.be/abc123", Platform.YOUTUBE),
    ],
)
def test_detect_supported_platforms(url, platform):
    assert detect_platform(url).platform == platform


def test_unsupported_platform_is_rejected():
    with pytest.raises(ValueError):
        ensure_supported_platform("https://example.com/video/1")


def test_non_http_url_is_rejected():
    with pytest.raises(ValueError):
        detect_platform("file:///tmp/video.mp4")


def test_safe_filename_part():
    assert safe_filename_part("White Man's Daughter!!!") == "White_Man_s_Daughter"
