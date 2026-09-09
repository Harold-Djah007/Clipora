from app.core.version import API_SERVICE_NAME, API_VERSION


def test_api_version_marker():
    assert API_SERVICE_NAME == "clipora"
    assert API_VERSION.startswith("0.8.4")
