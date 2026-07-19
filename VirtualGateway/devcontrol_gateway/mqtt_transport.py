from __future__ import annotations

import asyncio
import json
import logging
import secrets
import ssl
from concurrent.futures import Future
from typing import TYPE_CHECKING, Any, Protocol

from pydantic import ValidationError

from .config import GatewayConfig
from .errors import GatewayError
from .models import PROTOCOL_VERSION, SecureCommandEnvelope

if TYPE_CHECKING:
    from .service import GatewayService


LOGGER = logging.getLogger(__name__)


class MqttClient(Protocol):
    on_connect: Any
    on_disconnect: Any
    on_message: Any

    def tls_set_context(self, context: ssl.SSLContext) -> None: ...

    def tls_insecure_set(self, value: bool) -> None: ...

    def username_pw_set(self, username: str, password: str) -> None: ...

    def connect_async(self, host: str, port: int, keepalive: int) -> Any: ...

    def loop_start(self) -> Any: ...

    def loop_stop(self) -> Any: ...

    def disconnect(self) -> Any: ...

    def subscribe(self, topic: str, qos: int) -> Any: ...

    def publish(self, topic: str, payload: str, qos: int, retain: bool) -> Any: ...


class MqttBridge:
    """MQTT 5 bridge that reuses the gateway's authenticated command pipeline."""

    def __init__(
        self,
        config: GatewayConfig,
        gateway: GatewayService,
        *,
        client: MqttClient | None = None,
    ) -> None:
        self.config = config
        self.gateway = gateway
        self.client = client
        self._loop: asyncio.AbstractEventLoop | None = None
        self._started = False

    @property
    def command_topic(self) -> str:
        return f"{self.config.mqtt_topic_prefix}/commands"

    async def start(self) -> None:
        if self._started:
            return
        self.config.validate()
        self._loop = asyncio.get_running_loop()
        client = self.client or self._create_paho_client()
        self.client = client
        self._configure_tls(client)
        client.on_connect = self._on_connect
        client.on_disconnect = self._on_disconnect
        client.on_message = self._on_message
        self.gateway.add_sink(self.publish_event)
        try:
            client.connect_async(
                self.config.mqtt_host,
                self.config.mqtt_port,
                keepalive=60,
            )
            client.loop_start()
        except Exception:
            self.gateway.remove_sink(self.publish_event)
            raise
        self._started = True

    async def stop(self) -> None:
        if not self._started:
            return
        self.gateway.remove_sink(self.publish_event)
        client = self.client
        self._started = False
        if client is not None:
            try:
                client.disconnect()
            finally:
                client.loop_stop()

    def _create_paho_client(self) -> MqttClient:
        try:
            from paho.mqtt import client as mqtt
        except ImportError as exc:
            raise RuntimeError(
                "MQTT is enabled but paho-mqtt is not installed"
            ) from exc
        return mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id=f"devcontrol-gateway-{secrets.token_hex(6)}",
            protocol=mqtt.MQTTv5,
        )

    def _configure_tls(self, client: MqttClient) -> None:
        context = ssl.create_default_context(cafile=str(self.config.mqtt_ca))
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.verify_mode = ssl.CERT_REQUIRED
        context.check_hostname = True
        if (
            self.config.mqtt_client_cert is not None
            and self.config.mqtt_client_key is not None
        ):
            context.load_cert_chain(
                str(self.config.mqtt_client_cert),
                str(self.config.mqtt_client_key),
            )
        client.tls_set_context(context)
        client.tls_insecure_set(False)
        if self.config.mqtt_username and self.config.mqtt_password:
            client.username_pw_set(
                self.config.mqtt_username,
                self.config.mqtt_password,
            )

    def _on_connect(
        self,
        client: MqttClient,
        userdata: object,
        flags: object,
        reason_code: object,
        properties: object,
    ) -> None:
        del userdata, flags, properties
        code = getattr(reason_code, "value", reason_code)
        if code != 0:
            LOGGER.error("MQTTS broker rejected the gateway connection")
            return
        client.subscribe(self.command_topic, qos=1)
        for device in self.gateway.devices.snapshot():
            self._publish_json(
                f"{self.config.mqtt_topic_prefix}/devices/{device['id']}/state",
                self.gateway.state_event(device),
                qos=1,
                retain=True,
            )

    def _on_disconnect(
        self,
        client: MqttClient,
        userdata: object,
        disconnect_flags: object,
        reason_code: object,
        properties: object,
    ) -> None:
        del client, userdata, disconnect_flags, properties
        code = getattr(reason_code, "value", reason_code)
        if code not in (0, None):
            LOGGER.warning("MQTTS broker connection was interrupted")

    def _on_message(
        self, client: MqttClient, userdata: object, message: object
    ) -> None:
        del client, userdata
        payload = getattr(message, "payload", b"")
        if not isinstance(payload, bytes):
            return
        if len(payload) > self.config.max_transport_message_bytes:
            LOGGER.warning("Rejected oversized MQTTS command")
            return
        if self._loop is None or self._loop.is_closed():
            return
        future = asyncio.run_coroutine_threadsafe(
            self.handle_message(payload), self._loop
        )
        future.add_done_callback(self._consume_future)

    @staticmethod
    def _consume_future(future: Future[None]) -> None:
        try:
            future.result()
        except Exception:
            LOGGER.exception("Failed to process an MQTTS command")

    async def handle_message(self, payload: bytes) -> None:
        """Validate an MQTT wrapper, execute it once, and publish its result."""
        if len(payload) > self.config.max_transport_message_bytes:
            return
        try:
            raw = json.loads(payload.decode("utf-8"))
            if not isinstance(raw, dict):
                raise ValueError("MQTT payload must be an object")
            if raw.get("protocolVersion") != PROTOCOL_VERSION:
                raise ValueError("Unsupported protocol version")
            credential = raw.get("credential")
            command = raw.get("command")
            if not isinstance(credential, str) or not isinstance(command, dict):
                raise ValueError("Missing MQTT credential or command")
            session = self.gateway.sessions.authenticate(credential)
            envelope = SecureCommandEnvelope.model_validate(command)
        except (
            GatewayError,
            ValidationError,
            UnicodeDecodeError,
            json.JSONDecodeError,
            ValueError,
        ):
            LOGGER.warning("Rejected invalid or unauthenticated MQTTS command")
            return

        result, events = await self.gateway.process_command(session, envelope)
        self._publish_json(
            (
                f"{self.config.mqtt_topic_prefix}/clients/"
                f"{session.credential_digest}/results"
            ),
            result,
            qos=1,
            retain=False,
        )
        for event in events:
            await self.gateway.broadcast(event)

    async def publish_event(self, event: dict[str, Any]) -> None:
        event_type = str(event.get("type", "event"))
        qos = 0 if event_type == "heartbeat" else 1
        self._publish_json(
            f"{self.config.mqtt_topic_prefix}/events/{event_type}",
            event,
            qos=qos,
            retain=False,
        )
        if event_type == "state.changed" and event.get("deviceId"):
            self._publish_json(
                (
                    f"{self.config.mqtt_topic_prefix}/devices/"
                    f"{event['deviceId']}/state"
                ),
                event,
                qos=1,
                retain=True,
            )

    def _publish_json(
        self,
        topic: str,
        value: dict[str, Any],
        *,
        qos: int,
        retain: bool,
    ) -> None:
        if self.client is None:
            return
        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        self.client.publish(topic, payload, qos=qos, retain=retain)
