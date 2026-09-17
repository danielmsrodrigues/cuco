"""Sintetiza o "cu-cu" do Cuco: duas notas, a segunda uma terceira menor abaixo."""
import math
import struct
import sys
import wave

RATE = 44100


def note(freq, duration, amplitude):
    total = int(RATE * duration)
    attack = int(RATE * 0.015)
    release = int(RATE * 0.10)
    samples = []
    for i in range(total):
        t = i / RATE
        # Envelope: ataque curto, corpo estável, queda suave (sem estalos).
        if i < attack:
            env = i / attack
        elif i > total - release:
            env = (total - i) / release
        else:
            env = 1.0
        env *= math.exp(-1.1 * t)
        # Timbre de assobio/ocarina: fundamental com dois harmónicos fracos.
        vibrato = 1 + 0.004 * math.sin(2 * math.pi * 5.5 * t)
        phase = 2 * math.pi * freq * vibrato * t
        value = math.sin(phase) + 0.17 * math.sin(2 * phase) + 0.03 * math.sin(3 * phase)
        samples.append(amplitude * env * value / 1.20)
    return samples


def silence(duration):
    return [0.0] * int(RATE * duration)


def main(path, high=520.0, low=415.0):
    # "cu" mais agudo, "cu" mais grave — o intervalo que faz o pássaro soar a pássaro.
    signal = note(high, 0.20, 0.55) + silence(0.055) + note(low, 0.34, 0.55) + silence(0.08)

    frames = bytearray()
    for value in signal:
        clipped = max(-1.0, min(1.0, value))
        frames += struct.pack("<h", int(clipped * 32767))

    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(bytes(frames))


if __name__ == "__main__":
    high = float(sys.argv[2]) if len(sys.argv) > 2 else 520.0
    low = float(sys.argv[3]) if len(sys.argv) > 3 else 415.0
    main(sys.argv[1], high, low)
