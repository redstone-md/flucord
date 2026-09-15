"""Builds the bundled call sounds from Flucord design tokens.

The three sounds a call makes, ring, accept, and hang-up, are deterministic
synthesis rather than recorded audio: no third-party material to attribute,
and the same input always yields the same bytes, so the generated files in
``assets/sounds`` can be checked in and regenerated at any time.
"""

from pathlib import Path
import math
import struct
import wave

SAMPLE_RATE = 48000


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for sample in samples:
            value = int(max(-1.0, min(1.0, sample)) * 32767.0)
            frames += struct.pack("<h", value)
        handle.writeframes(bytes(frames))


def tone(frequency: float, seconds: float, volume: float) -> list[float]:
    count = int(SAMPLE_RATE * seconds)
    return [
        volume * math.sin(2.0 * math.pi * frequency * (i / SAMPLE_RATE))
        for i in range(count)
    ]


def silence(seconds: float) -> list[float]:
    return [0.0] * int(SAMPLE_RATE * seconds)


def with_fade(samples: list[float], seconds: float) -> list[float]:
    fade = int(SAMPLE_RATE * seconds)
    if fade <= 0 or len(samples) < 2 * fade:
        return samples
    step = 1.0 / fade
    for i in range(fade):
        samples[i] *= i * step
        samples[-1 - i] *= i * step
    return samples


def ring() -> list[float]:
    """A two-pulse ring: the shape a phone makes when it wants attention."""
    samples: list[float] = []
    for _ in range(2):
        samples += tone(600, 0.25, 0.35)
        samples += tone(800, 0.25, 0.35)
        samples += silence(0.2)
    return with_fade(samples, 0.02)


def accept() -> list[float]:
    """A rising two-note chirp: the sound of a call being answered."""
    samples = tone(520, 0.12, 0.3) + tone(780, 0.18, 0.3)
    return with_fade(samples, 0.02)


def hang_up() -> list[float]:
    """A falling two-note chirp: the sound of a call being ended."""
    samples = tone(780, 0.12, 0.3) + tone(520, 0.18, 0.3)
    return with_fade(samples, 0.02)


def main() -> None:
    root = Path(__file__).resolve().parents[1] / "assets" / "sounds"
    write_wav(root / "call_ring.wav", ring())
    write_wav(root / "call_accept.wav", accept())
    write_wav(root / "call_hang_up.wav", hang_up())
    print(f"wrote three sounds to {root}")


if __name__ == "__main__":
    main()
