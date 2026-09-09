from app.services.platform_matrix import SUPPORTED_PLATFORM_LABELS


def test_platform_matrix_has_expected_labels():
    assert SUPPORTED_PLATFORM_LABELS["threads"] == "Threads"
    assert SUPPORTED_PLATFORM_LABELS["tiktok"] == "TikTok"
    assert SUPPORTED_PLATFORM_LABELS["x"] == "X / Twitter"
    assert SUPPORTED_PLATFORM_LABELS["snapchat"] == "Snapchat"
