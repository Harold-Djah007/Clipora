import pytest

from app.services.universal_provider import UniversalProvider


@pytest.mark.asyncio
async def test_universal_provider_detect_method():
    provider = UniversalProvider()
    detected = await provider.detect("https://www.tiktok.com/@creator/video/1234567890")

    assert detected["platform"] == "tiktok"
    assert detected["supported"] is True
    assert detected["supports_server_resolve"] is True
