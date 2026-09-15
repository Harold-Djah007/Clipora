from app.services.session_config import cookie_file, httpx_session_options, outbound_proxy, session_status, ytdlp_session_options


def test_session_is_optional_by_default(monkeypatch):
    monkeypatch.delenv("CLIPORA_COOKIES_FILE", raising=False)
    monkeypatch.delenv("CLIPORA_OUTBOUND_PROXY", raising=False)
    assert cookie_file() is None
    assert outbound_proxy() is None
    assert session_status() == {"cookies_configured": False, "proxy_configured": False}
    assert ytdlp_session_options() == {}
    assert httpx_session_options() == {"trust_env": False}


def test_netscape_cookie_file_is_shared_by_ytdlp_and_httpx(monkeypatch, tmp_path):
    cookies = tmp_path / "cookies.txt"
    cookies.write_text(
        "# Netscape HTTP Cookie File\n.example.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\ttest-value\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("CLIPORA_COOKIES_FILE", str(cookies))
    assert ytdlp_session_options()["cookiefile"] == str(cookies)
    assert "cookies" in httpx_session_options()
    assert session_status()["cookies_configured"] is True


def test_explicit_http_proxy_is_shared(monkeypatch):
    monkeypatch.setenv("CLIPORA_OUTBOUND_PROXY", "https://user:pass@proxy.example:8443")
    assert ytdlp_session_options()["proxy"].startswith("https://")
    assert httpx_session_options()["proxy"].startswith("https://")


def test_invalid_proxy_is_rejected(monkeypatch):
    monkeypatch.setenv("CLIPORA_OUTBOUND_PROXY", "not-a-proxy")
    try:
        outbound_proxy()
    except ValueError as error:
        assert "valid HTTP(S) or SOCKS" in str(error)
    else:
        raise AssertionError("Expected invalid proxy to be rejected")
