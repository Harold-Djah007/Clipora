from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from hashlib import sha256
from typing import Dict, Optional
from cryptography.fernet import Fernet
import base64

from app.core.config import settings


def _fernet() -> Fernet:
    digest = sha256(settings.session_encryption_key.encode()).digest()
    return Fernet(base64.urlsafe_b64encode(digest))

@dataclass
class SessionRecord:
    encrypted_blob: bytes
    expires_at: datetime

class SessionStore:
    def __init__(self):
        self._store: Dict[str, SessionRecord] = {}

    def put(self, user_id: str, session_blob: str, ttl_minutes: Optional[int] = None):
        ttl = ttl_minutes or settings.session_ttl_minutes
        self._store[user_id] = SessionRecord(
            encrypted_blob=_fernet().encrypt(session_blob.encode()),
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=ttl),
        )

    def get(self, user_id: str) -> Optional[str]:
        rec = self._store.get(user_id)
        if not rec:
            return None
        if datetime.now(timezone.utc) >= rec.expires_at:
            self.delete(user_id)
            return None
        return _fernet().decrypt(rec.encrypted_blob).decode()

    def delete(self, user_id: str):
        self._store.pop(user_id, None)

    def purge_expired(self):
        now = datetime.now(timezone.utc)
        for uid, rec in list(self._store.items()):
            if now >= rec.expires_at:
                self.delete(uid)

session_store = SessionStore()
