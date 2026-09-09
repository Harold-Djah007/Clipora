from app.services.universal_provider import UniversalProvider


def test_hls_manifest_is_not_returned_as_direct_mobile_file():
    provider = UniversalProvider()
    info = {
        "formats": [
            {"url": "https://cdn.example/master.m3u8", "ext": "mp4", "height": 1080, "protocol": "m3u8_native"},
        ]
    }

    assert provider._extract_media_items(info) == []
