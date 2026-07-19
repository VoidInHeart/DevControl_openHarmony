from __future__ import annotations

import asyncio
import json
from pathlib import Path
from uuid import uuid4

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from fastapi.testclient import TestClient

import devcontrol_gateway.security as gateway_security
from devcontrol_gateway.app import create_admin_app, create_app
from devcontrol_gateway.config import GatewayConfig
from devcontrol_gateway.models import DeviceProvisionRequest, DeviceRegistrationRequest
from devcontrol_gateway.service import GatewayService


def make_config(tmp_path: Path) -> GatewayConfig:
    return GatewayConfig(
        database=tmp_path / "gateway.db",
        initial_pairing_code="123456",
        admin_token="test-admin-token",
        enable_background_tasks=False,
    )


def declaration(device_id: str) -> DeviceProvisionRequest:
    return DeviceProvisionRequest(
        deviceId=device_id,
        deviceName="浴室智能灯",
        deviceType="light",
        categoryId="lighting",
        capabilities=["setPower", "setBrightness", "setAutomationConfig"],
    )


def registration(service: GatewayService, device_id: str) -> DeviceRegistrationRequest:
    request = declaration(device_id)
    return DeviceRegistrationRequest(
        **request.model_dump(),
        roomId="bathroom",
        schema="devcontrol.device-registration",
        gatewayProof=service.issue_registration_proof(request),
    )


def paired_session(service: GatewayService):
    response = service.sessions.pair("127.0.0.1", f"client-{uuid4()}", "123456")
    return service.sessions.authenticate(response.credential)


def test_signed_bathroom_light_is_registered_and_can_be_removed(tmp_path: Path) -> None:
    service = GatewayService(make_config(tmp_path))
    try:
        request = registration(service, "LIGHT-BATHROOM-QR-001")
        session = paired_session(service)
        registered = asyncio.run(service.register_device(session, request))
        assert registered["id"] == request.deviceId
        assert registered["name"] == "浴室智能灯"
        assert registered["roomId"] == "bathroom"
        assert registered["removable"] is True
        assert registered["online"] is True

        removed = asyncio.run(service.delete_device(session, request.deviceId))
        assert removed["id"] == request.deviceId
        assert request.deviceId not in {item["id"] for item in service.devices.snapshot()}
    finally:
        asyncio.run(service.stop())


def test_signed_bathroom_environment_sensor_is_registered(tmp_path: Path) -> None:
    service = GatewayService(make_config(tmp_path))
    try:
        sensor_declaration = DeviceProvisionRequest(
            deviceId="ENV-BATHROOM-QR-001",
            deviceName="浴室环境监测器",
            deviceType="environment",
            categoryId="environment",
            capabilities=[
                "reportTemperature",
                "reportHumidity",
                "reportIlluminance",
                "reportPresence",
            ],
        )
        request = DeviceRegistrationRequest(
            **sensor_declaration.model_dump(),
            roomId="bathroom",
            schema="devcontrol.device-registration",
            gatewayProof=service.issue_registration_proof(sensor_declaration),
        )
        registered = asyncio.run(service.register_device(paired_session(service), request))
        assert registered["id"] == request.deviceId
        assert registered["roomId"] == "bathroom"
        assert registered["type"] == "environment"
        assert registered["temperatureCelsius"] == 24.0
        assert registered["humidityPercent"] == 62.0
        assert registered["illuminanceLux"] == 95.0
        assert registered["presence"] is False
        assert registered["removable"] is True
    finally:
        asyncio.run(service.stop())


def test_signed_bathroom_air_conditioner_is_registered(tmp_path: Path) -> None:
    service = GatewayService(make_config(tmp_path))
    try:
        declaration_request = DeviceProvisionRequest(
            deviceId="AC-BATHROOM-QR-001",
            deviceName="浴室空调",
            deviceType="airConditioner",
            categoryId="environment",
            capabilities=[
                "setPower",
                "setMode",
                "setTemperature",
                "setFanSpeed",
                "setDehumidify",
                "setBrand",
            ],
        )
        request = DeviceRegistrationRequest(
            **declaration_request.model_dump(),
            roomId="bathroom",
            schema="devcontrol.device-registration",
            gatewayProof=service.issue_registration_proof(declaration_request),
        )
        registered = asyncio.run(service.register_device(paired_session(service), request))
        assert registered["id"] == request.deviceId
        assert registered["brand"] == "generic"
        assert registered["mode"] == "auto"
        assert registered["targetTemperatureCelsius"] == 24
        assert registered["removable"] is True
    finally:
        asyncio.run(service.stop())


def test_signed_bathroom_humidifier_is_registered(tmp_path: Path) -> None:
    service = GatewayService(make_config(tmp_path))
    try:
        declaration_request = DeviceProvisionRequest(
            deviceId="HUMIDIFIER-BATHROOM-QR-001",
            deviceName="浴室加湿器",
            deviceType="humidifier",
            categoryId="environment",
            capabilities=["setPower", "setTargetHumidity"],
        )
        request = DeviceRegistrationRequest(
            **declaration_request.model_dump(),
            roomId="bathroom",
            schema="devcontrol.device-registration",
            gatewayProof=service.issue_registration_proof(declaration_request),
        )
        registered = asyncio.run(service.register_device(paired_session(service), request))
        assert registered["id"] == request.deviceId
        assert registered["state"] == {
            "power": False,
            "targetHumidityPercent": 55,
        }
        assert registered["removable"] is True
    finally:
        asyncio.run(service.stop())


def test_static_device_certificate_is_idempotent_and_reusable_after_removal(
    tmp_path: Path,
) -> None:
    service = GatewayService(make_config(tmp_path))
    try:
        request = registration(service, "LIGHT-BATHROOM-QR-002")
        session = paired_session(service)
        first = asyncio.run(service.register_device(session, request))
        second = asyncio.run(service.register_device(session, request))
        assert second == first

        asyncio.run(service.delete_device(session, request.deviceId))
        re_registered = asyncio.run(service.register_device(session, request))
        assert re_registered["id"] == request.deviceId
        assert re_registered["online"] is True
    finally:
        asyncio.run(service.stop())


def test_new_device_certificate_has_no_expiry_or_one_time_claim(tmp_path: Path) -> None:
    service = GatewayService(make_config(tmp_path))
    try:
        request = registration(service, "LIGHT-BATHROOM-QR-STATIC")
        _, encoded_claims, _ = request.gatewayProof.split(".", 2)
        claims = json.loads(
            gateway_security.base64url_decode(encoded_claims).decode("utf-8")
        )
        assert claims["certificateType"] == "device-identity-v1"
        assert "exp" not in claims
        assert "iat" not in claims
        assert "jti" not in claims
        assert "roomId" not in claims
    finally:
        asyncio.run(service.stop())


def test_legacy_expired_qr_certificate_remains_usable_after_migration(
    tmp_path: Path,
) -> None:
    service = GatewayService(make_config(tmp_path))
    try:
        declaration_request = declaration("LIGHT-BATHROOM-QR-LEGACY")
        claims = {
            "iss": gateway_security.PROVISIONING_ISSUER,
            "aud": gateway_security.PROVISIONING_AUDIENCE,
            "iat": 1,
            "exp": 2,
            "jti": "legacy-one-time-token",
            "roomId": "bathroom",
            **declaration_request.model_dump(),
        }
        header = {"alg": "ES256", "kid": "local-device-provisioner", "typ": "JWT"}
        encoded_header = gateway_security.base64url_encode(
            json.dumps(header, separators=(",", ":")).encode("utf-8")
        )
        encoded_claims = gateway_security.base64url_encode(
            json.dumps(claims, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        )
        signed = f"{encoded_header}.{encoded_claims}".encode("ascii")
        der_signature = service.provisioning._key.sign(signed, ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(der_signature)
        encoded_signature = gateway_security.base64url_encode(
            r.to_bytes(32, "big") + s.to_bytes(32, "big")
        )
        legacy_request = DeviceRegistrationRequest(
            **declaration_request.model_dump(),
            roomId="living",
            schema="devcontrol.device-registration",
            gatewayProof=f"{encoded_header}.{encoded_claims}.{encoded_signature}",
        )

        registered = asyncio.run(
            service.register_device(paired_session(service), legacy_request)
        )
        assert registered["id"] == legacy_request.deviceId
        assert registered["roomId"] == "living"
    finally:
        asyncio.run(service.stop())


def test_admin_provisioning_and_device_routes_share_the_same_proof(tmp_path: Path) -> None:
    config = make_config(tmp_path)
    service = GatewayService(config)
    declaration_body = declaration("LIGHT-BATHROOM-QR-003").model_dump()
    try:
        admin = TestClient(create_admin_app(service, config.admin_token))
        proof_response = admin.post(
            "/admin/v1/devices/provision",
            headers={"X-Admin-Token": config.admin_token},
            json=declaration_body,
        )
        assert proof_response.status_code == 200

        app = TestClient(create_app(config, service))
        paired = app.post(
            "/api/v1/pair",
            json={
                "protocolVersion": "1.0",
                "pairingCode": "123456",
                "clientId": "registration-rest-client",
            },
        )
        credential = paired.json()["credential"]
        headers = {"Authorization": f"Bearer {credential}"}
        registration_body = {
            **declaration_body,
            "roomId": "bathroom",
            "schema": "devcontrol.device-registration",
            "gatewayProofFormat": "jws",
            "gatewayProof": proof_response.json()["gatewayProof"],
        }
        registered = app.post(
            "/api/v1/devices/register", json=registration_body, headers=headers
        )
        assert registered.status_code == 200
        assert registered.json()["accepted"] is True

        deleted = app.delete(
            "/api/v1/devices/LIGHT-BATHROOM-QR-003", headers=headers
        )
        assert deleted.status_code == 200
        assert deleted.json() == {"deviceId": "LIGHT-BATHROOM-QR-003", "deleted": True}
    finally:
        asyncio.run(service.stop())
