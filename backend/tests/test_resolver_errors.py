from app.services.resolver_errors import NoDirectMediaError, ResolverError, UnsupportedPlatformError, public_resolver_error


def test_resolver_errors_share_base_type():
    assert issubclass(UnsupportedPlatformError, ResolverError)
    assert issubclass(NoDirectMediaError, ResolverError)


def test_public_error_removes_ansi_and_caps_detail():
    error = RuntimeError("\x1b[0;31mERROR:\x1b[0m " + "failure " * 100)
    message = public_resolver_error(error)
    assert "\x1b" not in message
    assert not message.startswith("ERROR:")
    assert len(message) <= 360


def test_public_error_explains_tiktok_homepage_redirect():
    message = public_resolver_error(RuntimeError("ERROR: Unsupported URL: https://www.tiktok.com/?_r=1"))
    assert message.startswith("TikTok did not release")


def test_public_error_explains_tiktok_status_zero():
    message = public_resolver_error(RuntimeError("ERROR: Video not available, status code 0"))
    assert message.startswith("TikTok did not release")


def test_instagram_empty_response_does_not_leak_extractor_instructions():
    raw = (
        "[Instagram] abc: Instagram sent an empty media response. "
        "Use --cookies-from-browser or --cookies for authentication. "
        "See https://github.com/yt-dlp/yt-dlp/wiki/FAQ"
    )

    message = public_resolver_error(RuntimeError(raw))

    assert message == "The public post loaded, but the platform did not expose downloadable media to the resolver."
    assert "--cookies" not in message
    assert "github.com" not in message


def test_login_error_is_reduced_to_public_access_message():
    raw = "This post is only visible while logged-in; authentication is required."

    assert public_resolver_error(RuntimeError(raw)) == (
        "This post is private or requires an account login. Clipora resolves public/shareable links only."
    )
