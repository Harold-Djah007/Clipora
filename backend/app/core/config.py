import os

class Settings:
    session_ttl_minutes: int = int(os.getenv("SESSION_TTL_MINUTES", "1440"))
    session_encryption_key: str = os.getenv("SESSION_ENCRYPTION_KEY", "dev-only-change-me")

settings = Settings()
