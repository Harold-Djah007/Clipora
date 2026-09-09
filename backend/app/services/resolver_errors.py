class ResolverError(RuntimeError):
    """Base resolver error for clear API failures."""


class UnsupportedPlatformError(ResolverError):
    """Raised when Clipora cannot support a pasted URL yet."""


class NoDirectMediaError(ResolverError):
    """Raised when a resolver finds no direct downloadable media."""
