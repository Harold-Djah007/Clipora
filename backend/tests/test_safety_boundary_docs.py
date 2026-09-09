from pathlib import Path


def test_safety_boundary_doc_exists():
    path = Path(__file__).resolve().parents[1] / "docs" / "safety-boundary.md"
    assert path.exists()
    text = path.read_text(encoding="utf-8").lower()
    assert "no watermark-removal" in text
    assert "no private access bypass" in text
