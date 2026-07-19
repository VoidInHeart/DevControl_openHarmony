from __future__ import annotations

import base64
import binascii
import hashlib
import json
import secrets
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from cryptography.exceptions import InvalidSignature, InvalidTag
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import (
    decode_dss_signature,
    encode_dss_signature,
)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from .errors import (
    AUTH_FAILED,
    DEVICE_PROOF_INVALID,
    RATE_LIMITED,
    REPLAY_DETECTED,
    GatewayError,
)
from .models import (
    DeviceProvisionRequest,
    DeviceRegistrationRequest,
    PairResponse,
    SecureCommandEnvelope,
)
PROVISIONING_ISSUER = "devcontrol-virtual-gateway"
PROVISIONING_AUDIENCE = "devcontrol.device-registration"


def base64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def base64url_decode(value: str) -> bytes:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.urlsafe_b64decode(value + padding)


def now_ms() -> int:
    return int(time.time() * 1000)


@dataclass(frozen=True, slots=True)
class RegistrationCertificate:
    """Verified static device certificate used for audit correlation only."""

    fingerprint: str


class DeviceProvisioningAuthority:
    """Signs local device identity declarations and verifies registrations.

    The key lives only in the gateway's ignored data directory. QR generation
    requests a static certificate from the loopback admin API and never reads
    this key. The certificate deliberately has no expiry or one-time nonce: it
    is meant to be printed on the device and scanned again when needed.
    """

    def __init__(self, key_path: Path) -> None:
        self._key = self._load_or_create_key(key_path)

    def issue(self, declaration: DeviceProvisionRequest) -> str:
        claims: dict[str, Any] = {
            "iss": PROVISIONING_ISSUER,
            "aud": PROVISIONING_AUDIENCE,
            "certificateType": "device-identity-v1",
            "deviceId": declaration.deviceId,
            "deviceName": declaration.deviceName,
            "deviceType": declaration.deviceType,
            "categoryId": declaration.categoryId,
            "roomId": declaration.roomId,
            "capabilities": declaration.capabilities,
        }
        header = {"alg": "ES256", "kid": "local-device-provisioner", "typ": "JWT"}
        encoded_header = base64url_encode(
            json.dumps(header, separators=(",", ":")).encode("utf-8")
        )
        encoded_claims = base64url_encode(
            json.dumps(claims, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        )
        signed = f"{encoded_header}.{encoded_claims}".encode("ascii")
        der_signature = self._key.sign(signed, ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(der_signature)
        jose_signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        return f"{encoded_header}.{encoded_claims}.{base64url_encode(jose_signature)}"

    def verify(self, registration: DeviceRegistrationRequest) -> RegistrationCertificate:
        try:
            encoded_header, encoded_claims, encoded_signature = registration.gatewayProof.split(
                ".", 2
            )
            header = self._decode_object(encoded_header)
            claims = self._decode_object(encoded_claims)
            signature = base64url_decode(encoded_signature)
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError, binascii.Error) as exc:
            raise GatewayError(DEVICE_PROOF_INVALID, "设备认证证明格式无效", 401) from exc
        if header.get("alg") != "ES256" or header.get("typ") != "JWT":
            raise GatewayError(DEVICE_PROOF_INVALID, "设备认证证明算法不受支持", 401)
        if len(signature) != 64:
            raise GatewayError(DEVICE_PROOF_INVALID, "设备认证证明签名无效", 401)
        try:
            der_signature = encode_dss_signature(
                int.from_bytes(signature[:32], "big"),
                int.from_bytes(signature[32:], "big"),
            )
            self._key.public_key().verify(
                der_signature,
                f"{encoded_header}.{encoded_claims}".encode("ascii"),
                ec.ECDSA(hashes.SHA256()),
            )
        except InvalidSignature as exc:
            raise GatewayError(DEVICE_PROOF_INVALID, "设备认证证明签名无效", 401) from exc

        if (
            claims.get("iss") != PROVISIONING_ISSUER
            or claims.get("aud") != PROVISIONING_AUDIENCE
            or (
                "certificateType" in claims
                and claims.get("certificateType") != "device-identity-v1"
            )
        ):
            raise GatewayError(DEVICE_PROOF_INVALID, "设备身份证书不属于当前网关", 401)

        expected = {
            "deviceId": registration.deviceId,
            "deviceName": registration.deviceName,
            "deviceType": registration.deviceType,
            "categoryId": registration.categoryId,
            "roomId": registration.roomId,
            "capabilities": registration.capabilities,
        }
        if any(claims.get(key) != value for key, value in expected.items()):
            raise GatewayError(DEVICE_PROOF_INVALID, "设备身份证书与二维码声明不一致", 401)

        # Legacy QR codes signed before the static-certificate migration carry
        # iat/exp/jti claims. Their signature and declaration are still valid,
        # so deliberately ignore those former short-lived-token fields.
        fingerprint = hashlib.sha256(registration.gatewayProof.encode("ascii")).hexdigest()
        return RegistrationCertificate(fingerprint=fingerprint)

    @staticmethod
    def _decode_object(segment: str) -> dict[str, Any]:
        value = json.loads(base64url_decode(segment).decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError("JWS segment must contain an object")
        return value

    @staticmethod
    def _load_or_create_key(path: Path) -> ec.EllipticCurvePrivateKey:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            loaded = serialization.load_pem_private_key(path.read_bytes(), password=None)
            if (
                not isinstance(loaded, ec.EllipticCurvePrivateKey)
                or not isinstance(loaded.curve, ec.SECP256R1)
            ):
                raise ValueError("Provisioning signing key must be an ES256 private key")
            return loaded
        key = ec.generate_private_key(ec.SECP256R1())
        path.write_bytes(
            key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption(),
            )
        )
        return key


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
    expires_at: int


@dataclass(slots=True)
class PairAttempt:
    failures: int = 0
    locked_until: float = 0.0


class SessionRegistry:
    PAIRING_LIFETIME_SECONDS = 300
    LOCK_SECONDS = 600
    MAX_FAILURES = 5

    def __init__(
        self,
        initial_pairing_code: str | None = None,
        *,
        clock: Callable[[], float] = time.monotonic,
        wall_clock_ms: Callable[[], int] = now_ms,
        credential_ttl_seconds: int = 24 * 60 * 60,
        pairing_code_factory: Callable[[], str] | None = None,
    ) -> None:
        if credential_ttl_seconds <= 0:
            raise ValueError("Credential lifetime must be positive")
        self._clock = clock
        self._wall_clock_ms = wall_clock_ms
        self._credential_ttl_ms = credential_ttl_seconds * 1000
        self._pairing_code_factory = pairing_code_factory or self._random_pairing_code
        self._pairing_code = (
            self._validate_pairing_code(initial_pairing_code)
            if initial_pairing_code is not None
            else self._new_pairing_code()
        )
        self._pairing_expires_at = self._clock() + self.PAIRING_LIFETIME_SECONDS
        self._attempts: dict[str, PairAttempt] = {}
        self._sessions: dict[str, ClientSession] = {}

    @property
    def pairing_code(self) -> str:
        self._rotate_if_expired()
        return self._pairing_code

    @property
    def pairing_expires_in(self) -> int:
        return max(0, int(self._pairing_expires_at - self._clock()))

    @staticmethod
    def _random_pairing_code() -> str:
        return f"{secrets.randbelow(1_000_000):06d}"

    @staticmethod
    def _validate_pairing_code(pairing_code: str) -> str:
        if len(pairing_code) != 6 or not pairing_code.isdigit():
            raise ValueError("Pairing code must be six digits")
        return pairing_code

    def _new_pairing_code(self, previous: str | None = None) -> str:
        for _ in range(16):
            candidate = self._validate_pairing_code(self._pairing_code_factory())
            if candidate != previous:
                return candidate
        raise RuntimeError("Pairing-code generator did not rotate the code")

    def _rotate_if_expired(self) -> None:
        if self._clock() >= self._pairing_expires_at:
            self.rotate_pairing_code()

    def rotate_pairing_code(self) -> str:
        self._pairing_code = self._new_pairing_code(self._pairing_code)
        self._pairing_expires_at = self._clock() + self.PAIRING_LIFETIME_SECONDS
        return self._pairing_code

    def pair(
        self, source: str, client_id: str, pairing_code: str
    ) -> PairResponse:
        self._rotate_if_expired()
        attempt = self._attempts.setdefault(source, PairAttempt())
        now = self._clock()
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
        issued_at = self._wall_clock_ms()
        expires_at = issued_at + self._credential_ttl_ms
        self._sessions[digest] = ClientSession(
            client_id=client_id,
            credential_digest=digest,
            data_key=data_key,
            issued_at=issued_at,
            expires_at=expires_at,
        )
        self.rotate_pairing_code()
        return PairResponse(
            clientId=client_id,
            credential=credential,
            dataKey=base64url_encode(data_key),
            issuedAt=issued_at,
            expiresAt=expires_at,
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
        if self._wall_clock_ms() >= session.expires_at:
            self.revoke(digest)
            raise GatewayError(AUTH_FAILED, "客户端凭据已过期，请重新配对", 401)
        return session

    def remaining_seconds(self, session: ClientSession) -> float:
        return max(0.0, (session.expires_at - self._wall_clock_ms()) / 1000)

    def revoke(self, credential_digest: str) -> None:
        self._sessions.pop(credential_digest, None)

