#!/usr/bin/env python3
"""Builds the Toybox's voice clips (SPEC FR-TOY-03) with Piper.

The kitchen frame has no text-to-speech, so every line the Toybox says is a
clip bundled with the app. The lines come from dearth_core (`kVoiceLines`,
printed by packages/dearth_core/tool/voice_lines.dart). Text in [[ ]] is in
the voice's own phonemes (espeak's IPA): letter sounds that no spelling
gives, like "buh" or a short "a". Piper (MIT) speaks every line with its
LJSpeech voice, trained on the LJ Speech dataset, which is in the public
domain. Each clip is trimmed, brought to the animal sounds' loudness and
written as a short mono MP3 to apps/dearth_app/assets/voice/.

Piper speaks a little differently every run, so only new or changed lines
are made again: tool/sounds/voice_index.json keeps a hash of each clip's
phonemes and settings. Clips that no line asks for any more are deleted.
`--all` remakes everything; naming clips (`voice.py letter_b find_b`)
remakes just those.

Piper and the voice download to ~/.cache/dearth/piper on first use. Needs
dart, curl, tar, ffmpeg (with libmp3lame) and numpy.
"""
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import wave

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "apps/dearth_app/assets/voice"
INDEX = ROOT / "tool/sounds/voice_index.json"
CACHE = pathlib.Path.home() / ".cache/dearth/piper"
PIPER_URL = "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz"
VOICE_URL = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ljspeech/high/en_US-ljspeech-high.onnx"
VOICE = CACHE / "en_US-ljspeech-high.onnx"
RATE = 22050

# A little slower than reading pace: these are for three-year-olds. The
# noise settings are the voice's own.
LENGTH_SCALE = 1.1
NOISE_SCALE = 0.667
NOISE_W = 0.333
# Bump to remake every clip after changing how they're cut or encoded.
VERSION = 1


def fetch(url: str, path: pathlib.Path) -> None:
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    print(f"downloading {url}")
    subprocess.run(["curl", "-sfL", "-m", "600", url, "-o", str(path)], check=True)


def ensure_piper() -> pathlib.Path:
    piper = CACHE / "piper/piper"
    if not piper.exists():
        archive = CACHE / "piper.tar.gz"
        fetch(PIPER_URL, archive)
        subprocess.run(["tar", "-xzf", str(archive), "-C", str(CACHE)], check=True)
        archive.unlink()
    fetch(VOICE_URL, VOICE)
    fetch(VOICE_URL + ".json", VOICE.with_suffix(".onnx.json"))
    # The same voice, reading phonemes instead of text.
    config = json.loads(VOICE.with_suffix(".onnx.json").read_text())
    config["phoneme_type"] = "text"
    (CACHE / "ipa.onnx.json").write_text(json.dumps(config))
    return piper


def env() -> dict:
    return dict(os.environ, LD_LIBRARY_PATH=str(CACHE / "piper"))


def voice_lines() -> dict:
    out = subprocess.run(["dart", "run", "tool/voice_lines.dart"], cwd=ROOT / "packages/dearth_core", check=True, capture_output=True, text=True)
    return json.loads(out.stdout)


def phonemize(texts: list) -> dict:
    """espeak's phonemes for each text, as Piper would read it."""
    if not texts:
        return {}
    out = subprocess.run(
        [str(CACHE / "piper/piper_phonemize"), "-l", "en", "--espeak_data", str(CACHE / "piper/espeak-ng-data")],
        input="\n".join(texts) + "\n", capture_output=True, text=True, env=env(), check=True,
    ).stdout.splitlines()
    result = {}
    for text, line in zip(texts, out):
        # One flat run of phonemes; sentences meet without a space.
        result[text] = re.sub(r"([.!?])(?=\S)", r"\1 ", "".join(json.loads(line)["phonemes"]))
    return result


PUNCT = re.compile(r"^[\s,.!?;:]*")


def segments(line: str) -> list:
    """(is_ipa, text) parts of a line, punctuation between them kept apart."""
    parts = []
    for i, part in enumerate(re.split(r"\[\[(.*?)\]\]", line)):
        if i % 2:
            parts.append((True, part))
            continue
        lead = PUNCT.match(part).group(0)
        if lead:
            parts.append((True, lead))
        rest = part[len(lead):]
        if rest.strip():
            parts.append((False, rest.strip()))
            if rest != rest.rstrip():
                parts.append((True, " "))
    return parts


def to_ipa(lines: dict) -> dict:
    texts = sorted({t for line in lines.values() for ipa, t in segments(line) if not ipa})
    spoken = phonemize(texts)
    return {clip: re.sub(r" +", " ", "".join(t if ipa else spoken[t] for ipa, t in segments(line))).strip() for clip, line in lines.items()}


def key(ipa: str) -> str:
    return hashlib.sha1(f"{VERSION}|{LENGTH_SCALE}|{NOISE_SCALE}|{NOISE_W}|{ipa}".encode()).hexdigest()[:16]


def synthesize(piper: pathlib.Path, todo: dict, tmp: pathlib.Path) -> None:
    """Speaks every {clip: phonemes} into tmp/<clip>.wav, in one Piper run."""
    jobs = "".join(json.dumps({"text": ipa, "output_file": str(tmp / f"{clip}.wav")}) + "\n" for clip, ipa in todo.items())
    subprocess.run(
        [str(piper), "-q", "--json-input", "-m", str(VOICE), "-c", str(CACHE / "ipa.onnx.json"), "--espeak_data", str(CACHE / "piper/espeak-ng-data"),
         "--length_scale", str(LENGTH_SCALE), "--noise_scale", str(NOISE_SCALE), "--noise_w", str(NOISE_W)],
        input=jobs.encode(), env=env(), check=True, capture_output=True,
    )


def finish(wav: pathlib.Path, target: pathlib.Path) -> float:
    """Trims, evens out and encodes one clip; returns its length in seconds."""
    with wave.open(str(wav)) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768
    hop = RATE // 100
    frames = x[: len(x) // hop * hop].reshape(-1, hop)
    rms = np.sqrt((frames**2).mean(axis=1))
    voiced = np.nonzero(rms > 0.008)[0]
    start = max(0, voiced[0] * hop - int(0.04 * RATE))
    end = min(len(x), (voiced[-1] + 1) * hop + int(0.12 * RATE))
    clip = x[start:end]
    # The loud part at -18 dBFS RMS (as the animal sounds), peaks under -1 dBFS.
    loud = rms[rms > 0.1 * rms.max()]
    gain = min(10 ** (-18 / 20) / np.sqrt((loud**2).mean()), 10 ** (-1 / 20) / np.abs(clip).max())
    ramp = np.minimum(1, np.minimum(np.arange(len(clip)) / (0.005 * RATE), (len(clip) - np.arange(len(clip))) / (0.02 * RATE)))
    pcm = np.clip(clip * gain * ramp * 32767, -32767, 32767).astype("<i2")
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-codec:a", "libmp3lame", "-b:a", "40k", str(target)],
        input=pcm.tobytes(), check=True,
    )
    return len(clip) / RATE


def main(args: list) -> None:
    piper = ensure_piper()
    lines = voice_lines()
    ipa = to_ipa(lines)
    index = json.loads(INDEX.read_text()) if INDEX.exists() else {}
    named = [a for a in args if not a.startswith("--")]
    if unknown := [a for a in named if a not in lines]:
        sys.exit(f"no such clips: {' '.join(unknown)}")
    OUT.mkdir(parents=True, exist_ok=True)
    todo = {
        clip: p
        for clip, p in ipa.items()
        if "--all" in args or clip in named or index.get(clip) != key(p) or not (OUT / f"{clip}.mp3").exists()
    }
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        if todo:
            print(f"speaking {len(todo)} of {len(lines)} lines")
            synthesize(piper, todo, tmp)
        for clip, p in todo.items():
            seconds = finish(tmp / f"{clip}.wav", OUT / f"{clip}.mp3")
            index[clip] = key(p)
            if len(todo) <= 40:
                print(f"{clip:28} {seconds:4.2f} s  {lines[clip]}")
    stale = [f for f in OUT.glob("*.mp3") if f.stem not in lines]
    for f in stale:
        f.unlink()
    index = {clip: index[clip] for clip in sorted(lines)}
    INDEX.write_text(json.dumps(index, indent=1) + "\n")
    total = sum(f.stat().st_size for f in OUT.glob("*.mp3"))
    print(f"{len(todo)} made, {len(lines) - len(todo)} kept, {len(stale)} removed; {len(lines)} clips, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main(sys.argv[1:])
