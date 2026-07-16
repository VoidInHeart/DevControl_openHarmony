from devcontrol_gateway.adapters import (
    GreeSimAdapter,
    HaierSimAdapter,
    MideaSimAdapter,
    NormalizedAcCommand,
)


def test_simulated_brand_frames_are_distinct() -> None:
    command = NormalizedAcCommand(
        action="setTemperature", temperature=24
    )
    frames = {
        HaierSimAdapter().encode(command),
        GreeSimAdapter().encode(command),
        MideaSimAdapter().encode(command),
    }
    assert len(frames) == 3
    assert all("24" in frame for frame in frames)

