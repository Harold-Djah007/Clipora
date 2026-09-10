from pathlib import Path


def test_local_backend_test_doc_mentions_pytest():
    text = (Path(__file__).resolve().parents[1] / "docs" / "local-backend-test.md").read_text(encoding="utf-8")
    assert "pytest -q" in text
    assert "threadvault_premium_0.6.0" in text
    assert 'powershell -ExecutionPolicy Bypass -File ".\\scripts\\start_api.ps1"' in text
    assert "adb.exe" in text
    assert "reverse tcp:8010 tcp:8010" in text
    assert "--dart-define=CLIPORA_RESOLVER_URL=http://127.0.0.1:8010" in text
    assert "flutter test" in text
    assert "Invoke-RestMethod \"http://127.0.0.1:8010/health\"" in text
    assert "TikTok → Share → More → Clipora" in text
