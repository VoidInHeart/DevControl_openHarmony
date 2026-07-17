from __future__ import annotations

import base64
import hashlib
import json
import secrets
import time
from dataclasses import dataclass

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from .errors import AUTH_FAILED, RATE_LIMITED, REPLAY_DETECTED, GatewayError
from .models import PairResponse, SecureCommandEnvelope


def base64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def base64url_decode(value: str) -> bytes:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.urlsafe_b64decode(value + padding)


def now_ms() -> int:
    return int(time.time() * 1000)


def canonical_aad(envelope: SecureCommandEnvelope) -> bytes:
    aad = {
        "protocolVersion": envelope.protocolVersion,
        "messageId": envelope.messageId,
        "deviceId": envelope.deviceId,
        "timestamp": envelope.timestamp,
        "type": envelope.type,
        "action": envelope.action,
        "expectedStateVersion": envelope.expectedStateVersion,
    }
    return json.dumps(
        aad, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")


def encrypt_payload(
    key: bytes, payload: dict[str, object], envelope_header: dict[str, object]
) -> dict[str, str]:
    envelope = SecureCommandEnvelope(
        **envelope_header,
        nonce=base64url_encode(secrets.token_bytes(12)),
        ciphertext="placeholder",
        authTag=base64url_encode(b"0" * 16),
    )
    nonce = base64url_decode(envelope.nonce)
    plaintext = json.dumps(
        payload, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    sealed = AESGCM(key).encrypt(nonce, plaintext, canonical_aad(envelope))
    return {
        "nonce": envelope.nonce,
        "ciphertext": base64url_encode(sealed[:-16]),
        "authTag": base64url_encode(sealed[-16:]),
    }


def decrypt_payload(
    key: bytes, envelope: SecureCommandEnvelope
) -> dict[str, object]:
    try:
        nonce = base64url_decode(envelope.nonce)
        if len(nonce) != 12:
            raise ValueError("nonce must be 96 bits")
        ciphertext = base64url_decode(envelope.ciphertext)
        tag = base64url_decode(envelope.authTag)
        if len(tag) != 16:
            raise ValueError("tag must be 128 bits")
        plaintext = AESGCM(key).decrypt(
            nonce, ciphertext + tag, canonical_aad(envelope)
        )
        value = json.loads(plaintext.decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError("payload must be an object")
        return value
    except (InvalidTag, ValueError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GatewayError(
            REPLAY_DETECTED,
            "命令认证失败，消息可能已被篡改或重放",
            400,
        ) from exc


@dataclass(slots=True)
class ClientSession:
    client_id: str
    credential_digest: str
    data_key: bytes
    issued_at: int


@dataclass(slots=True)
class PairAttempt:
    failures: int = 0
    locked_until: float = 0.0


class SessionRegistry:
    PAIRING_LIFETIME_SECONDS = 300
    LOCK_SECONDS = 600
    MAX_FAILURES = 5

    def __init__(self, fixed_pairing_code: str | None = None) -> None:
        self._fixed_pairing_code = fixed_pairing_code
        self._pairing_code = self._new_pairing_code()
        self._pairing_expires_at = time.monotonic() + self.PAIRING_LIFETIME_SECONDS
        self._attempts: dict[str, PairAttempt] = {}
        self._sessions: dict[str, ClientSession] = {}

    @property
    def pairing_code(self) -> str:
        self._rotate_if_expired()
        return self._pairing_code

    @property
    def pairing_expires_in(self) -> int:
        return max(0, int(self._pairing_expires_at - time.monotonic()))

    def _new_pairing_code(self) -> str:
        if self._fixed_pairing_code is not None:
            if (
                len(self._fixed_pairing_code) != 6
                or not self._fixed_pairing_code.isdigit()
            ):
                raise ValueError("DEVCONTROL_PAIRING_CODE must be six digits")
            return self._fixed_pairing_code
        return f"{secrets.randbelow(1_000_000):06d}"

    def _rotate_if_expired(self) -> None:
        if time.monotonic() >= self._pairing_expires_at:
            self.rotate_pairing_code()

    def rotate_pairing_code(self) -> str:
        self._pairing_code = self._new_pairing_code()
        self._pairing_expires_at = time.monotonic() + self.PAIRING_LIFETIME_SECONDS
        return self._pairing_code

    def pair(
        self, source: str, client_id: str, pairing_code: str
    ) -> PairResponse:
        self._rotate_if_expired()
        attempt = self._attempts.setdefault(source, PairAttempt())
        now = time.monotonic()
        if attempt.locked_until > now:
            retry_after = max(1, int(attempt.locked_until - now))
            raise GatewayError(
                RATE_LIMITED,
                "配对失败次数过多，请稍后重试",
                429,
                retry_after,
            )

        if not secrets.compare_digest(pairing_code, self._pairing_code):
            attempt.failures += 1
            if attempt.failures >= self.MAX_FAILURES:
                attempt.failures = 0
                attempt.locked_until = now + self.LOCK_SECONDS
                raise GatewayError(
                    RATE_LIMITED,
                    "配对失败次数过多，来源已锁定10分钟",
                    429,
                    self.LOCK_SECONDS,
                )
            raise GatewayError(AUTH_FAILED, "配对码无效或已过期", 401)

        attempt.failures = 0
        attempt.locked_until = 0.0
        credential_bytes = secrets.token_bytes(32)
        credential = base64url_encode(credential_bytes)
        digest = hashlib.sha256(credential_bytes).hexdigest()
        data_key = secrets.token_bytes(32)
        issued_at = now_ms()
        self._sessions[digest] = ClientSession(
            client_id=client_id,
            credential_digest=digest,
            data_key=data_key,
            issued_at=issued_at,
        )
        self.rotate_pairing_code()
        return PairResponse(
            clientId=client_id,
            credential=credential,
            dataKey=base64url_encode(data_key),
            issuedAt=issued_at,
        )

    def authenticate(self, credential: str) -> ClientSession:
        try:
            credential_bytes = base64url_decode(credential)
        except Exception as exc:
            raise GatewayError(AUTH_FAILED, "客户端凭据无效", 401) from exc
        digest = hashlib.sha256(credential_bytes).hexdigest()
        session = self._sessions.get(digest)
        if session is None:
            raise GatewayError(AUTH_FAILED, "客户端凭据无效或网关已重启", 401)
        return session

    def revoke(self, credential_digest: str) -> None:
        self._sessions.pop(credential_digest, None)

