#!/usr/bin/env python3
"""Builds the Toybox's voice clips (SPEC FR-TOY-03) with Maya1.

The kitchen frame has no text-to-speech, so every line the Toybox says is a
clip bundled with the app. The lines come from dearth_core (`kVoiceLines`,
printed by packages/dearth_core/tool/voice_lines.dart). The voice is
Maya-1 (Maya Research, Apache-2.0) run locally through Transformers: a
text-to-speech model whose voice is *designed* in words (see DESCRIPTION —
a warm preschool teacher, so the games get the sunny, slow, sing-song
register the clips used to fake with Piper settings). No real person's
voice is cloned. Maya1 takes text, not phonemes, so lines keep [[ ]] spans
only at authoring time: RESPELL turns each one into a spelling the model
reads right ("buh" for [[bˈʌ]]), and the build fails on a span with no
entry rather than baking a clip that says the wrong thing.

Only new or changed lines are made again: tool/sounds/voice_index.json
keeps a hash of each clip's final text and settings. Clips that no line
asks for any more are deleted. `--all` remakes everything; naming clips
(`voice.py letter_b find_b`) remakes just those. Every run rewrites the
clips' lengths into dearth_core (voice_lengths.g.dart), which games use to
let a line finish (a new clip stops the one before).

The model downloads to the Hugging Face cache on first use (~7 GB); the
Python side (transformers, snac, soundfile, numpy) lives in
~/.cache/dearth/venv-voice, built and re-entered automatically. Needs dart,
curl, uv, ffmpeg (with libmp3lame) and an NVIDIA GPU (Maya1 is 3.3 B
parameters; CPU would crawl). `DEARTH_VOICE_DESC` swaps the voice
description for experiments.
"""
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

# Before torch's CUDA init: 7 GB of weights on an 8 GB card leaves little
# to fragment across 1,700 generations.
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

ROOT = pathlib.Path(__file__).resolve().parents[2]
VENV = pathlib.Path.home() / ".cache/dearth/venv-voice"


def _bootstrap() -> None:
    """Builds the voice venv on first use, then re-runs this script in it."""
    py = VENV / "bin/python"
    if not py.exists():
        env = dict(os.environ, VIRTUAL_ENV=str(VENV))
        subprocess.run(["uv", "venv", "--python", "3.12", str(VENV)], check=True)
        subprocess.run(["uv", "pip", "install", "torch", "transformers", "accelerate", "snac", "soundfile", "numpy"], check=True, env=env)
    os.environ["DEARTH_VOICE_BOOTSTRAPPED"] = "1"
    os.execv(str(py), [str(py), str(pathlib.Path(__file__).resolve()), *sys.argv[1:]])


try:
    import numpy as np
    import soundfile as sf
    import torch
    from snac import SNAC
    from transformers import AutoModelForCausalLM, AutoTokenizer
except ImportError:
    if os.environ.get("DEARTH_VOICE_BOOTSTRAPPED"):
        raise
    _bootstrap()  # never returns

OUT = ROOT / "apps/dearth_app/assets/voice"
INDEX = ROOT / "tool/sounds/voice_index.json"
# How long each clip runs, for games that wait for the voice before the next
# line (a new clip stops the one before).
LENGTHS = ROOT / "packages/dearth_core/lib/src/toybox/voice_lengths.g.dart"
MODEL_TAG = "maya1"

# The Toybox's voice, written as a Maya1 description (the engine designs an
# original voice from the words; it is not a clone of anyone). Maya1 has no
# speed knob: the slow, toddler-facing pacing lives in the wording.
DESCRIPTION = os.environ.get(
    "DEARTH_VOICE_DESC",
    "Female voice in her 30s with an American accent, a warm and sunny "
    "preschool teacher: bright, patient and encouraging, with very clear "
    "diction, a gentle sing-song melody, speaking slowly for toddlers",
)
# Low temperature keeps one voice across a thousand clips (the card's own
# generation config defaults to 0.6, which wandered too much clip to clip).
TEMPERATURE = 0.4
TOP_P = 0.9
# Ceiling on generated audio tokens (~7 per SNAC frame, ~42 frames a
# second). The true cap is per line (speak()): short lines that lose their
# speech-end token would otherwise ramble silence to any ceiling and OOM
# the GPU over a long batch.
MAX_NEW_TOKENS = 4096

RATE = 22050
# Shaped for a small speaker: it can't move air below ~150 Hz, so that
# energy only muddies; consonants live at 2-5 kHz, where it plays best.
# Light compression lifts the quiet syllables before levelling.
SHAPE = "highpass=f=150:p=2,equalizer=f=3000:t=q:w=1.2:g=5,acompressor=threshold=-24dB:ratio=3:attack=5:release=90"
# The loud part's RMS. Speech sits above the effects (-18 dBFS), so the
# words carry over them.
LEVEL_DB = -16
# Bump to remake every clip after changing how they're cut or encoded.
VERSION = 4

# Maya1 reads text, not phonemes: each [[ ]] span in kVoiceLines (letter
# sounds, words a fixed-up voice needed) becomes a spelling it says right.
# A span missing here fails the build — listen, pick the spelling, add it. A
# word respelled for Piper's British phonemes goes back to its plain
# spelling: this voice reads "zebra", "banana", "tomato" and "one"
# American-style on its own, and a lone word ("was", "the") gets its
# stressed reading by itself.
RESPELL = {
    # Letter sounds: a consonant with a short "uh" ("B. Buh, buh, ball.").
    "bˈʌ": "buh", "kˈʌ": "kuh", "dˈʌ": "duh", "fˈʌ": "fuh", "ɡˈʌ": "guh",
    "hˈʌ": "huh", "dʒˈʌ": "juh", "lˈʌ": "luh", "mˈʌ": "muh", "nˈʌ": "nuh",
    "pˈʌ": "puh", "kwˈʌ": "quh", "ɹˈʌ": "ruh", "sˈʌ": "suh", "tˈʌ": "tuh",
    "vˈʌ": "vuh", "wˈʌ": "wuh", "jˈʌ": "yuh", "zˈʌ": "zuh",
    "ʃˈʌ": "shuh", "tʃˈʌ": "chuh", "θˈʌ": "thuh",
    # Short vowels alone.
    "ˈa": "ahh", "ˈɛ": "eh", "ˈɪ": "ih", "ˈɒ": "ah", "ˈʌ": "uh",
    # Letter names mid-sentence.
    "ˈeɪ": "A", "zˈiː": "zee",
    # Plain words again (see above).
    "zˈiːbɹə": "zebra", "bɐnˈanə": "banana", "təmˈeɪtəʊ": "tomato",
    "wˈʌn": "one", "ˈand": "and", "ˈɑːɹ": "are", "ˈat": "at",
    "fˈɔːɹ": "for", "fɹˈʌm": "from", "ˈɪz": "is", "ˈɪt": "it",
    "ʃˈiː": "she", "ðˈʌ": "the", "tˈuː": "to", "wˈʌz": "was",
    "wˈiː": "we", "wˈʌt": "what", "wˈɪð": "with", "jˈuː": "you",
}


def voice_lines() -> dict:
    out = subprocess.run(["dart", "run", "tool/voice_lines.dart"], cwd=ROOT / "packages/dearth_core", check=True, capture_output=True, text=True)
    return json.loads(out.stdout)


def to_text(lines: dict) -> dict:
    """Each line's final text: [[ ]] spans replaced by their RESPELLing."""
    out = {}
    missing = set()
    for clip, line in lines.items():
        def sub(m):
            if m.group(1) in RESPELL:
                return RESPELL[m.group(1)]
            missing.add(m.group(1))
            return m.group(0)
        out[clip] = re.sub(r"\[\[(.*?)\]\]", sub, line)
    if missing:
        sys.exit("no RESPELL entry for these [[ ]]-spans — hear them, pick a spelling, add it:\n" + "\n".join(f"  [[{s}]]" for s in sorted(missing)))
    return out


def key(text: str) -> str:
    return hashlib.sha1(f"{VERSION}|{MODEL_TAG}|{DESCRIPTION}|{TEMPERATURE}|{TOP_P}|{SHAPE}|{LEVEL_DB}|{text}".encode()).hexdigest()[:16]


_MAYA = None

# Maya1's SNAC framing (from the model card's reference implementation).
CODE_START, CODE_END, CODE_OFFSET = 128257, 128258, 128266
SNAC_MIN, SNAC_MAX, SNAC_PER_FRAME = 128266, 156937, 7
SOH, EOH, SOA, TEXT_EOT = 128259, 128260, 128261, 128009


def maya():
    """Loads the model and SNAC decoder once."""
    global _MAYA
    if _MAYA is None:
        if not torch.cuda.is_available():
            print("warning: no CUDA; Maya1 on CPU is glacial")
        model = AutoModelForCausalLM.from_pretrained("maya-research/maya1", torch_dtype=torch.bfloat16, device_map="auto", trust_remote_code=True)
        tokenizer = AutoTokenizer.from_pretrained("maya-research/maya1", trust_remote_code=True)
        snac = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").eval()
        if torch.cuda.is_available():
            snac = snac.to("cuda")
        _MAYA = (model, tokenizer, snac)
    return _MAYA


def prompt(tokenizer, text: str) -> str:
    return (
        tokenizer.decode([SOH]) + tokenizer.bos_token + f'<description="{DESCRIPTION}"> {text}'
        + tokenizer.decode([TEXT_EOT]) + tokenizer.decode([EOH]) + tokenizer.decode([SOA]) + tokenizer.decode([CODE_START])
    )


def speak(text: str, wav: pathlib.Path) -> None:
    """One line through Maya1 into wav (24 kHz)."""
    model, tokenizer, snac = maya()
    inputs = tokenizer(prompt(tokenizer, text), return_tensors="pt", add_special_tokens=False)
    if torch.cuda.is_available():
        inputs = {k: v.to("cuda") for k, v in inputs.items()}
    # ~180 tokens a word at teacher pace, plus headroom; caps a runaway.
    max_new = min(MAX_NEW_TOKENS, 500 + 180 * len(text.split()))
    with torch.inference_mode():
        outputs = model.generate(
            **inputs, max_new_tokens=max_new, min_new_tokens=28,
            temperature=TEMPERATURE, top_p=TOP_P, repetition_penalty=1.1,
            do_sample=True, eos_token_id=CODE_END, pad_token_id=tokenizer.pad_token_id,
        )
    gen = outputs[0, inputs["input_ids"].shape[1]:].tolist()
    try:
        gen = gen[: gen.index(CODE_END)]
    except ValueError:
        pass
    tokens = [t for t in gen if SNAC_MIN <= t <= SNAC_MAX]
    frames = len(tokens) // SNAC_PER_FRAME
    if not frames:
        raise RuntimeError(f"Maya1 gave no audio for {text!r}")
    tokens = tokens[: frames * SNAC_PER_FRAME]
    l1, l2, l3 = [], [], []
    for i in range(frames):
        s = tokens[i * 7 : (i + 1) * 7]
        l1.append((s[0] - CODE_OFFSET) % 4096)
        l2 += [(s[1] - CODE_OFFSET) % 4096, (s[4] - CODE_OFFSET) % 4096]
        l3 += [(s[2] - CODE_OFFSET) % 4096, (s[3] - CODE_OFFSET) % 4096, (s[5] - CODE_OFFSET) % 4096, (s[6] - CODE_OFFSET) % 4096]
    device = "cuda" if torch.cuda.is_available() else "cpu"
    codes = [torch.tensor(level, dtype=torch.long, device=device).unsqueeze(0) for level in (l1, l2, l3)]
    with torch.inference_mode():
        z_q = snac.quantizer.from_codes(codes)
        audio = snac.decoder(z_q)[0, 0].cpu().numpy()
    audio = audio[2048:] if len(audio) > 2048 else audio
    if len(audio) == 0 or np.abs(audio).max() < 1e-3:
        raise RuntimeError("silent generation")
    sf.write(str(wav), audio, 24000)


def speak_guarded(text: str, wav: pathlib.Path) -> None:
    """speak() with retries: sampling sometimes goes silent, and long
    generations can OOM the card's headroom."""
    err = None
    for attempt in range(3):
        try:
            speak(text, wav)
            return
        except (torch.OutOfMemoryError, RuntimeError) as e:
            err = e
        finally:
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
    raise RuntimeError(f"Maya1 could not say {text!r} after 3 tries: {err}")


def synthesize(todo: dict, index: dict, tmp: pathlib.Path) -> None:
    """Speaks, encodes and indexes every {clip: text}, one clip at a time.

    The index is rewritten after each clip and finished clips land straight
    in OUT, so an interrupted run (hours on a big corpus) keeps its work:
    the next run skips them.
    """
    import time
    start = time.time()
    for i, (clip, text) in enumerate(todo.items(), 1):
        speak_guarded(text, tmp / f"{clip}.wav")
        seconds = finish(tmp / f"{clip}.wav", OUT / f"{clip}.mp3")
        index[clip] = key(text)
        INDEX.write_text(json.dumps({c: index[c] for c in sorted(index)}, indent=1) + "\n")
        # A clip far longer than its words is a looping model, not a
        # talkative one: said out loud, so it can be re-made or the line
        # rewritten, instead of shipped.
        expect = 0.45 * len(text.split()) + 2.0
        flag = "  <-- long for its words; re-check" if seconds > expect else ""
        if len(todo) <= 40 or flag:
            print(f"{clip:28} {seconds:4.2f} s  {text}{flag}")
        elif i % 50 == 0:
            done = time.time() - start
            print(f"  {i} of {len(todo)} ({done / i:.1f} s/clip, ~{(len(todo) - i) * done / i / 60:.0f} min left)")


def finish(wav: pathlib.Path, target: pathlib.Path) -> float:
    """Trims, evens out and encodes one clip; returns its length in seconds."""
    shaped = subprocess.run(["ffmpeg", "-v", "error", "-i", str(wav), "-af", SHAPE, "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"], check=True, capture_output=True).stdout
    x = np.frombuffer(shaped, "<f4").astype(np.float64)
    hop = RATE // 100
    frames = x[: len(x) // hop * hop].reshape(-1, hop)
    rms = np.sqrt((frames**2).mean(axis=1))
    voiced = np.nonzero(rms > 0.008)[0]
    start = max(0, voiced[0] * hop - int(0.04 * RATE))
    end = min(len(x), (voiced[-1] + 1) * hop + int(0.12 * RATE))
    clip = x[start:end]
    # The loud part at LEVEL_DB RMS, peaks under -1 dBFS.
    loud = rms[rms > 0.1 * rms.max()]
    gain = min(10 ** (LEVEL_DB / 20) / np.sqrt((loud**2).mean()), 10 ** (-1 / 20) / np.abs(clip).max())
    ramp = np.minimum(1, np.minimum(np.arange(len(clip)) / (0.005 * RATE), (len(clip) - np.arange(len(clip))) / (0.02 * RATE)))
    pcm = np.clip(clip * gain * ramp * 32767, -32767, 32767).astype("<i2")
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-codec:a", "libmp3lame", "-b:a", "48k", str(target)],
        input=pcm.tobytes(), check=True,
    )
    return len(clip) / RATE


def length_ms(mp3: pathlib.Path) -> int:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(mp3)], check=True, capture_output=True, text=True)
    return round(float(out.stdout) * 1000)


def write_lengths(clips: list) -> None:
    body = "".join(f"  '{clip}': {length_ms(OUT / f'{clip}.mp3')},\n" for clip in clips)
    LENGTHS.write_text(
        "// GENERATED by tool/sounds/voice.py. Do not edit.\n"
        "// How long each Toybox voice clip runs, in milliseconds.\n\n"
        f"const Map<String, int> kVoiceMs = {{\n{body}}};\n"
    )


def main(args: list) -> None:
    lines = voice_lines()
    text = to_text(lines)
    index = json.loads(INDEX.read_text()) if INDEX.exists() else {}
    named = [a for a in args if not a.startswith("--")]
    if unknown := [a for a in named if a not in lines]:
        sys.exit(f"no such clips: {' '.join(unknown)}")
    OUT.mkdir(parents=True, exist_ok=True)
    # "--just" limits a run to the named clips, whatever the index says: for
    # auditioning a handful after an engine or setting change before the rest
    # of the corpus follows.
    just = "--just" in args
    todo = {
        clip: t
        for clip, t in text.items()
        if ((clip in named) if just else ("--all" in args or clip in named or index.get(clip) != key(t) or not (OUT / f"{clip}.mp3").exists()))
    }
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        if todo:
            print(f"speaking {len(todo)} of {len(lines)} lines")
            synthesize(todo, index, tmp)
    stale = [f for f in OUT.glob("*.mp3") if f.stem not in lines]
    for f in stale:
        f.unlink()
    index = {clip: index[clip] for clip in sorted(lines)}
    INDEX.write_text(json.dumps(index, indent=1) + "\n")
    write_lengths(sorted(lines))
    total = sum(f.stat().st_size for f in OUT.glob("*.mp3"))
    print(f"{len(todo)} made, {len(lines) - len(todo)} kept, {len(stale)} removed; {len(lines)} clips, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main(sys.argv[1:])
