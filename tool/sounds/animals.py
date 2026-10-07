#!/usr/bin/env python3
"""Builds the Animal Farm sounds (SPEC FR-TOY-02, FR-TOY-07) from CC0 recordings.

Every source is a recording by Joseph Sardin on BigSoundBank.com, released
under CC0 1.0 (public domain: credit appreciated, not required). The script
fetches each original, cuts the animal's call by its loudness envelope, evens
out the loudness across animals, and writes short mono MP3s to
apps/dearth_app/assets/sounds/animals/. Run it again to rebuild them; the
originals are cached in ~/.cache/dearth/sounds/bsb.

Needs curl and ffmpeg (with libmp3lame). `animals.py beats` makes only the
Music Sequencer's short beats.
"""
import array
import math
import pathlib
import subprocess
import sys
import tempfile
import wave

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "apps/dearth_app/assets/sounds/animals"
CACHE = pathlib.Path.home() / ".cache/dearth/sounds/bsb"
RATE = 22050

# animal: (BigSoundBank sound id, calls to keep, longest clip in seconds)
SOURCES = {
    "cow": ("2384", 1, 2.2),  # "Cow moos 4"
    "pig": ("1658", 2, 1.3),  # "Grumpy pig 1"
    "sheep": ("2344", 1, 1.2),  # "Sheep 2"
    "rooster": ("0440", 3, 2.6),  # "Cock song 1"
    "chicken": ("0453", 4, 1.4),  # "Annoyed hen"
    "horse": ("1541", 1, 1.6),  # "Horse neighing 4"
    "dog": ("2954", 2, 1.0),  # "Barking dog 2"
    "cat": ("1472", 1, 1.2),  # "Little meow of a cat 2"
    "frog": ("0819", 2, 1.4),  # "One frog"
    "owl": ("1763", 1, 1.5),  # "Tawny owl 1"
}

# Music Sequencer's beats: one short call each, from the same recordings, so
# a step every 0.3 s never piles calls on top of each other.
BEATS = {
    "dogBeat": ("2954", 1, 0.4),
    "catBeat": ("1472", 1, 0.55),
    "frogBeat": ("0819", 1, 0.45),
    "chickenBeat": ("0453", 1, 0.35),
}


def fetch(sound_id: str) -> pathlib.Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    for ext in ("flac", "mp3"):
        path = CACHE / f"{sound_id}.{ext}"
        if path.exists():
            return path
        url = f"https://bigsoundbank.com/UPLOAD/{ext}/{sound_id}.{ext}"
        if subprocess.run(["curl", "-sfL", "-m", "60", url, "-o", str(path)]).returncode == 0:
            return path
        path.unlink(missing_ok=True)
    sys.exit(f"couldn't download BigSoundBank sound {sound_id}")


def decode(path: pathlib.Path) -> array.array:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(RATE), "-f", "s16le", "-"], check=True, capture_output=True).stdout
    samples = array.array("h")
    samples.frombytes(raw)
    return samples


def calls(samples: array.array, hop: int = RATE // 100) -> list[tuple[int, int]]:
    """Loud stretches (start, end) in samples: frames over 15% of the peak
    level, gaps under 60 ms merged, blips under 30 ms dropped."""
    levels = []
    for i in range(0, len(samples) - hop, hop):
        frame = samples[i : i + hop]
        levels.append(math.sqrt(sum(s * s for s in frame) / hop))
    threshold = 0.15 * max(levels)
    runs, start = [], None
    for i, level in enumerate(levels + [0]):
        if level > threshold and start is None:
            start = i
        elif level <= threshold and start is not None:
            runs.append([start, i])
            start = None
    merged = []
    for run in runs:
        if merged and run[0] - merged[-1][1] < 6:
            merged[-1][1] = run[1]
        else:
            merged.append(run)
    return [(a * hop, b * hop) for a, b in merged if b - a >= 3]


def build(animal: str, sound_id: str, keep: int, longest: float) -> None:
    samples = decode(fetch(sound_id))
    found = calls(samples)
    if len(found) < keep:
        sys.exit(f"{animal}: found {len(found)} calls in {sound_id}, wanted {keep}")
    start = max(0, found[0][0] - int(0.03 * RATE))
    end = min(len(samples), found[keep - 1][1] + int(0.15 * RATE), start + int(longest * RATE))
    clip = [float(s) for s in samples[start:end]]
    # Even loudness: the loud part at -18 dBFS RMS, peaks no higher than -1 dBFS.
    loud = [s for s in clip if abs(s) > 0.05 * 32767] or clip
    rms = math.sqrt(sum(s * s for s in loud) / len(loud))
    gain = min(32767 * 10 ** (-18 / 20) / rms, 32767 * 10 ** (-1 / 20) / max(abs(s) for s in clip))
    fade_in, fade_out = int(0.008 * RATE), int(0.08 * RATE)
    out = array.array("h")
    for i, s in enumerate(clip):
        g = gain * min(1.0, i / fade_in, (len(clip) - i) / fade_out)
        out.append(max(-32767, min(32767, int(s * g))))
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(out.tobytes())
        target = OUT / f"{animal}.mp3"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp.name, "-codec:a", "libmp3lame", "-b:a", "64k", str(target)], check=True)
    print(f"{animal:8} {sound_id}  {len(clip) / RATE:.2f} s  {target.stat().st_size // 1024} KB")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    # `animals.py beats` makes only the sequencer's beats.
    todo = BEATS if sys.argv[1:] == ["beats"] else {**SOURCES, **BEATS}
    for name, (sid, keep, longest) in todo.items():
        build(name, sid, keep, longest)
