from app.services.platform_matrix import SUPPORTED_PLATFORM_LABELS


def test_universal_platform_count():
    assert set(SUPPORTED_PLATFORM_LABELS) == {
        "threads",
        "tiktok",
        "instagram",
        "x",
        "pinterest",
        "facebook",
        "snapchat",
        "youtube",
    }
