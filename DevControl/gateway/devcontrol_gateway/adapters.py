from __future__ import annotations

from dataclasses import dataclass

from .errors import INVALID_COMMAND, GatewayError


VALID_MODES = {"auto", "cool", "heat", "dry", "fan"}


@dataclass(frozen=True, slots=True)
class NormalizedAcCommand:
    action: str
    power: bool | None = None
    mode: str | None = None
    temperature: int | None = None


class BrandAdapter:
    brand = "generic"

    def validate(self, command: NormalizedAcCommand) -> None:
        if command.action == "setMode" and command.mode not in VALID_MODES:
            raise GatewayError(INVALID_COMMAND, "空调模式不受支持")
        if command.action == "setTemperature" and (
            command.temperature is None
            or command.temperature < 16
            or command.temperature > 30
        ):
            raise GatewayError(INVALID_COMMAND, "目标温度必须在16到30摄氏度之间")

    def encode(self, command: NormalizedAcCommand) -> str:
        self.validate(command)
        return f"GENERIC_SIM|{command.action}|{command.mode or ''}|{command.temperature or ''}"


class HaierSimAdapter(BrandAdapter):
    brand = "haierSim"

    def encode(self, command: NormalizedAcCommand) -> str:
        self.validate(command)
        power = "ON" if command.power else "OFF"
        return (
            f"HAIER_SIM|POWER={power}|MODE={command.mode or ''}|"
            f"TEMP={command.temperature or ''}"
        )


class GreeSimAdapter(BrandAdapter):
    brand = "greeSim"

    def encode(self, command: NormalizedAcCommand) -> str:
        self.validate(command)
        power = "1" if command.power else "0"
        return (
            f"GREE_SIM|PWR:{power}|MODE:{command.mode or ''}|"
            f"T:{command.temperature or ''}"
        )


class MideaSimAdapter(BrandAdapter):
    brand = "mideaSim"

    def encode(self, command: NormalizedAcCommand) -> str:
        self.validate(command)
        power = "ON" if command.power else "OFF"
        return (
            f"MIDEA_SIM|{power};{command.mode or ''};"
            f"{command.temperature or ''}"
        )


ADAPTERS: dict[str, BrandAdapter] = {
    adapter.brand: adapter
    for adapter in (
        BrandAdapter(),
        HaierSimAdapter(),
        GreeSimAdapter(),
        MideaSimAdapter(),
    )
}


def get_adapter(brand: str) -> BrandAdapter:
    adapter = ADAPTERS.get(brand)
    if adapter is None:
        raise GatewayError(INVALID_COMMAND, "未知的模拟空调品牌")
    return adapter

