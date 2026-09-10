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
    assert message.startswith("TikTok did not return a public video")


def test_public_error_explains_empty_tiktok_failure():
    message = public_resolver_error(ValueError("yt-dlp could not extract media from this tiktok link. "))
    assert "Open the post in TikTok" in message


def test_public_error_explains_instagram_extract_failure():
    message = public_resolver_error(ValueError("yt-dlp could not extract media from this instagram link."))
    assert message.startswith("Instagram did not return")


def test_public_error_hides_instagram_yt_dlp_issue_url():
    message = public_resolver_error(
        ValueError(
            "yt-dlp could not extract media from this instagram link. "
            "ERROR: [Instagram] DdFUKwBPwlI: No video formats found!; please report this issue on https://github.com/yt-dlp/yt-dlp/issues"
        )
    )
    assert message.startswith("Instagram did not return")
    assert "github.com" not in message
    assert "yt-dlp" not in message.lower()


def test_public_error_hides_x_no_video_dump():
    message = public_resolver_error(
        ValueError("yt-dlp could not extract media from this x link. ERROR: [twitter] 2097: No video could be found in this tweet")
    )
    assert message.startswith("X/Twitter did not return")
    assert "tweet" not in message.lower()


def test_public_error_facebook_registered_users_is_private():
    message = public_resolver_error(
        ValueError(
            "yt-dlp could not extract media from this facebook link. "
            "ERROR: [facebook] 108: This video is only available for registered users. Use --cookies-from-browser"
        )
    )
    assert "login" in message.lower() or "private" in message.lower()
    assert "cookies" not in message.lower()


def test_public_error_pinterest_ffmpeg_stays_on_pinterest():
    message = public_resolver_error(
        ValueError("No direct MP4 was available, and HLS/direct file fallback failed. Install ffmpeg. this pinterest link")
    )
    assert message.startswith("Pinterest did not return")
    assert "ffmpeg" not in message.lower()


def test_public_error_explains_threads_failure():
    message = public_resolver_error(ValueError("Threads did not return a public photo or video for this link."))
    assert message.startswith("Threads did not return")


def test_public_error_threads_share_miss_is_not_login_wall():
    message = public_resolver_error(
        ValueError(
            "No downloadable media found. Threads did not return a public photo or video for this link. "
            "Open the post, tap Share, and send it to Clipora again."
        )
    )
    assert message.startswith("Threads did not return")
    assert "account login" not in message


def test_public_error_threads_may_be_private_is_not_login_wall():
    message = public_resolver_error(ValueError("No downloadable media found. The post may be private or unavailable."))
    assert "account login" not in message
    assert "cookies" not in message.lower()


def test_public_error_empty_text_still_has_fallback():
    message = public_resolver_error(RuntimeError("ERROR:"))
    assert message == "The resolver could not extract downloadable media from this link."
