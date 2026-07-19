from __future__ import annotations

import asyncio
from pathlib import Path
from uuid import uuid4

from devcontrol_gateway.config import GatewayConfig
from devcontrol_gateway.models import (
    DeviceProvisionRequest,
    DeviceRegistrationRequest,
    RoomCreateRequest,
)
from devcontrol_gateway.service import GatewayService


def make_config(tmp_path: Path) -> GatewayConfig:
    return GatewayConfig(
        database=tmp_path / "gateway.db",
        initial_pairing_code="123456",
        admin_token="test-admin-token",
        enable_background_tasks=False,
    )


def paired_session(service: GatewayService):
    response = service.sessions.pair("127.0.0.1", f"client-{uuid4()}", "123456")
    return service.sessions.authenticate(response.credential)


def test_default_rooms_keep_two_bedrooms_living_room_and_bathroom(
    tmp_path: Path,
) -> None:
    service = GatewayService(make_config(tmp_path))
    try:
        rooms = service.rooms_snapshot()
        selectable_ids = [room["id"] for room in rooms if room["selectable"]]
        assert selectable_ids == ["living", "masterBedroom", "bedroom", "bathroom"]
        assert [room["name"] for room in rooms if room["selectable"]] == [
            "客厅",
            "主卧",
            "次卧",
            "浴室",
        ]
    finally:
        asyncio.run(service.stop())


def test_created_room_is_selectable_for_device_registration(tmp_path: Path) -> None:
    service = GatewayService(make_config(tmp_path))
    try:
        session = paired_session(service)
        room = asyncio.run(
            service.create_room(
                session,
                RoomCreateRequest(roomId="room-study", name="书房"),
            )
        )
        assert room == {"id": "room-study", "name": "书房", "selectable": True}
        assert room in service.rooms_snapshot()

        declaration = DeviceProvisionRequest(
            deviceId="LIGHT-STUDY-QR-001",
            deviceName="书房台灯",
            deviceType="light",
            categoryId="lighting",
            capabilities=["setPower", "setBrightness", "setAutomationConfig"],
        )
        registration = DeviceRegistrationRequest(
            **declaration.model_dump(),
            roomId=room["id"],
            schema="devcontrol.device-registration",
            gatewayProof=service.issue_registration_proof(declaration),
        )
        registered = asyncio.run(service.register_device(session, registration))
        assert registered["roomId"] == "room-study"
    finally:
        asyncio.run(service.stop())
