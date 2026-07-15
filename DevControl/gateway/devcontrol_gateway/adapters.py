from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class BrandAdapter(ABC):
    brand: str

    @abstractmethod
    def encode(self, action: str, payload: dict[str, Any], state: dict[str, Any]) -> str:
        raise NotImplementedError


class HaierSimAdapter(BrandAdapter):
    brand = "haierSim"

    def encode(self, action: str, payload: dict[str, Any], state: dict[str, Any]) -> str:
        power = "ON" if _power_after(action, state) else "OFF"
        mode = str(payload.get("mode", state.get("mode", "auto"))).upper()
        temperature = int(payload.get("temperatureCelsius", state.get("targetTemperatureCelsius", 26)))
        return f"HAIER_SIM|POWER={power}|MODE={mode}|TEMP={temperature}"


class GreeSimAdapter(BrandAdapter):
    brand = "greeSim"

    def encode(self, action: str, payload: dict[str, Any], state: dict[str, Any]) -> str:
        power = 1 if _power_after(action, state) else 0
        mode = str(payload.get("mode", state.get("mode", "auto"))).upper()
        temperature = int(payload.get("temperatureCelsius", state.get("targetTemperatureCelsius", 26)))
        return f"GREE_SIM|PWR:{power}|MODE:{mode}|T:{temperature}"


class MideaSimAdapter(BrandAdapter):
    brand = "mideaSim"

    def encode(self, action: str, payload: dict[str, Any], state: dict[str, Any]) -> str:
        power = "ON" if _power_after(action, state) else "OFF"
        mode = str(payload.get("mode", state.get("mode", "auto"))).upper()
        temperature = int(payload.get("temperatureCelsius", state.get("targetTemperatureCelsius", 26)))
        return f"MIDEA_SIM|{power};{mode};{temperature}"


def adapter_for(brand: str) -> BrandAdapter:
    adapters: dict[str, BrandAdapter] = {
        "haierSim": HaierSimAdapter(),
        "greeSim": GreeSimAdapter(),
        "mideaSim": MideaSimAdapter(),
    }
    return adapters.get(brand, HaierSimAdapter())


def _power_after(action: str, state: dict[str, Any]) -> bool:
    if action == "acPowerOn":
        return True
    if action == "acPowerOff":
        return False
    return bool(state.get("power", False))
