from pathlib import Path


def test_universal_resolver_doc_mentions_detect_endpoint():
    path = Path(__file__).resolve().parents[1] / "docs" / "universal-resolver.md"
    text = path.read_text(encoding="utf-8")
    assert "/api/detect" in text
    assert "/api/resolve/universal" in text
