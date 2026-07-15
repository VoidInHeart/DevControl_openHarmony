from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import threading
import time
from dataclasses import dataclass

from .models import ClientSession


class PairingError(Exception):
    pass


@dataclass(slots=True)
class AttemptWindow:
    failures: int = 0
    locked_until: float = 0.0


class CredentialStore:
    def __init__(self, pairing_ttl_seconds: int, credential_ttl_seconds: int) -> None:
        self._pairing_ttl_seconds = pairing_ttl_seconds
        self._credential_ttl_seconds = credential_ttl_seconds
        self._sessions_by_digest: dict[str, ClientSession] = {}
        self._attempts: dict[str, AttemptWindow] = {}
        self._lock = threading.Lock()
        self._pairing_code = ""
        self._pairing_expires_at = 0.0
        self.rotate_pairing_code()

    @property
    def pairing_code(self) -> str:
        return self._pairing_code

    @property
    def pairing_expires_at(self) -> int:
        return int(self._pairing_expires_at * 1000)

    def rotate_pairing_code(self) -> str:
        with self._lock:
            self._pairing_code = f"{secrets.randbelow(1_000_000):06d}"
            self._pairing_expires_at = time.time() + self._pairing_ttl_seconds
            return self._pairing_code

    def pair(self, source: str, pairing_code: str, client_id: str) -> tuple[ClientSession, str, str]:
        now = time.time()
        with self._lock:
            attempts = self._attempts.setdefault(source, AttemptWindow())
            if attempts.locked_until > now:
                raise PairingError("RATE_LIMITED")
            valid = now <= self._pairing_expires_at and hmac.compare_digest(pairing_code, self._pairing_code)
            if not valid:
                attempts.failures += 1
                if attempts.failures >= 5:
                    attempts.failures = 0
                    attempts.locked_until = now + 600
                raise PairingError("AUTH_FAILED")

            attempts.failures = 0
            credential = secrets.token_urlsafe(32)
            data_key = secrets.token_bytes(32)
            digest = self._digest(credential)
            expires_at = int((now + self._credential_ttl_seconds) * 1000)
            session = ClientSession(client_id, digest, data_key, expires_at)
            self._sessions_by_digest[digest] = session
            self._pairing_code = ""
            self._pairing_expires_at = 0.0
            return session, credential, base64.b64encode(data_key).decode("ascii")

    def authenticate(self, credential: str) -> ClientSession | None:
        if not credential:
            return None
        digest = self._digest(credential)
        with self._lock:
            session = self._sessions_by_digest.get(digest)
            if session is None or session.expires_at < int(time.time() * 1000):
                self._sessions_by_digest.pop(digest, None)
                return None
            return session

    def revoke(self, credential: str) -> None:
        with self._lock:
            self._sessions_by_digest.pop(self._digest(credential), None)

    @staticmethod
    def _digest(credential: str) -> str:
        return hashlib.sha256(credential.encode("utf-8")).hexdigest()
