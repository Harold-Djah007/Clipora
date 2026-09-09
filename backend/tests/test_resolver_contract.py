from app.services.resolver_contract import PLATFORM_DETECT_ENDPOINT, UNIVERSAL_RESOLVE_ENDPOINT


def test_resolver_contract_paths_are_stable():
    assert PLATFORM_DETECT_ENDPOINT == "/api/detect"
    assert UNIVERSAL_RESOLVE_ENDPOINT == "/api/resolve/universal"
