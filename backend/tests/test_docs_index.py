from pathlib import Path


def test_backend_docs_index_exists():
    path = Path(__file__).resolve().parents[1] / "docs" / "README.md"
    assert path.exists()
    text = path.read_text(encoding="utf-8")
    assert "universal-resolver.md" in text
    assert "safety-boundary.md" in text
