from pathlib import Path


def test_ytdlp_dependency_is_declared():
    requirements = Path(__file__).resolve().parents[1] / "requirements.txt"
    text = requirements.read_text(encoding="utf-8")
    assert "yt-dlp" in text
