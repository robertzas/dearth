#!/usr/bin/env python3
"""Shows (and with --say, speaks) how the Toybox voice reads lines.

The voice is Maya-1, a text-to-speech model whose voice is the written
description in tool/sounds/voice.py. It reads text, not phonemes: [[ ]]
spans in a line (letter sounds, letters mid-sentence) pass through
voice.py's RESPELL table to a spelling the model says right — this prints
that final text, which is what gets synthesized. --say writes the clip to
/tmp/kilo/voice-preview/<name>.mp3 so it can be played.

    python3 skills/toybox-game/scripts/preview.py "Find the letter Z." "One, two, three!"
    python3 skills/toybox-game/scripts/preview.py --ids creature_    # every voice line whose id starts with creature_
    python3 skills/toybox-game/scripts/preview.py --say letter_b "B. Buh, buh, ball."

Adding a span the table doesn't know fails the build with the span listed;
the rule of thumb is a spelling any parent would say ("buh", "sss"), and
for a short vowel alone, audition two spellings and keep the true one.

Uses the voice venv: run python3 tool/sounds/voice.py once to build it
(--say also downloads ~7 GB of model).
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
VENV = pathlib.Path.home() / ".cache/dearth/venv-voice"


def in_venv() -> None:
    try:
        import snac  # noqa: F401
    except ImportError:
        if not (VENV / "bin/python").exists():
            sys.exit("The voice venv isn't built yet: run python3 tool/sounds/voice.py once.")
        os.execv(str(VENV / "bin/python"), [str(VENV / "bin/python"), str(pathlib.Path(__file__).resolve()), *sys.argv[1:]])


in_venv()
sys.path.insert(0, str(ROOT / "tool/sounds"))
import voice


def voice_lines(prefix: str) -> list:
    out = subprocess.run(["dart", "run", "tool/voice_lines.dart"], cwd=ROOT / "packages/dearth_core", capture_output=True, text=True, check=True).stdout
    import json
    lines = json.loads(out[out.index("{"):])
    return [(k, v) for k, v in sorted(lines.items()) if k.startswith(prefix)]


def main() -> int:
    args = sys.argv[1:]
    say = "--say" in args
    if say:
        args.remove("--say")
    if not args or args[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if args else 2
    if args[0] == "--ids":
        if len(args) != 2:
            print("usage: preview.py --ids <prefix>", file=sys.stderr)
            return 2
        items = voice_lines(args[1])
        if not items:
            print(f"No voice line's id starts with {args[1]!r}.", file=sys.stderr)
            return 1
    else:
        items = [(f"line{i}", a) for i, a in enumerate(args)]

    text = voice.to_text(dict(items))
    for cid, raw in items:
        print(f"{raw if cid.startswith('line') else cid + ': ' + raw}  ->  {text[cid]}")

    if say:
        out = pathlib.Path("/tmp/kilo/voice-preview")
        out.mkdir(parents=True, exist_ok=True)
        for i, (cid, _) in enumerate(items):
            wav = out / f"{cid or i}.wav"
            voice.speak_guarded(text[cid], wav)
            secs = voice.finish(wav, wav.with_suffix(".mp3"))
            wav.unlink()
            print(f"  -> {wav.with_suffix('.mp3')} ({secs:.2f}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
