from app.services.resolver_errors import NoDirectMediaError, ResolverError, UnsupportedPlatformError


def test_resolver_errors_share_base_type():
    assert issubclass(UnsupportedPlatformError, ResolverError)
    assert issubclass(NoDirectMediaError, ResolverError)
