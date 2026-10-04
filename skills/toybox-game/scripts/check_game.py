#!/usr/bin/env python3
"""Checks that a Toybox game is wired in everywhere it has to be.

Step 8 of the toybox-game skill (skills/toybox-game/SKILL.md): the
catalog, the registry, the tests (core, widget, layout, E2E), the docs, the
voice clips, and that the temporary screenshot test is gone. Prints a ✓ or
✗ for each and exits 1 if anything is missing.

    python3 skills/toybox-game/scripts/check_game.py <game-id>
    python3 skills/toybox-game/scripts/check_game.py <game-id> --no-voice   # skip the clip check (needs dart)
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
CORE = ROOT / "packages/dearth_core"
APP = ROOT / "apps/dearth_app"


def read(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def any_file(paths, test) -> list:
    return [p for p in paths if test(read(p))]


def rel(paths) -> str:
    return ", ".join(str(p.relative_to(ROOT)) for p in paths)


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__.strip())
        return 2
    gid = args[0]
    failures = []

    def ok(text):
        print(f"  \033[32m✓\033[0m {text}")

    def bad(text):
        print(f"  \033[31m✗\033[0m {text}")
        failures.append(text)

    games = read(CORE / "lib/src/toybox/games.dart")
    m = re.search(r"GameInfo\('" + re.escape(gid) + r"',\s*(['\"])(.*?)(?<!\\)\1,\s*(['\"])(.*?)\3,(.*?)\)", games, re.S)
    if not m:
        print(f"Toybox game '{gid}'")
        bad(f"catalog: no GameInfo('{gid}', …) in packages/dearth_core/lib/src/toybox/games.dart")
        return 1
    title, emoji, rest = m.group(2).replace("\\'", "'"), m.group(4), m.group(5)
    months = re.search(r"minMonths:\s*(\d+)", rest)
    levels = re.search(r"levels:\s*(\d+)", rest)
    free = "free play" if "freePlay: true" in rest else "rounds"
    print(f"Toybox game '{gid}' ({title})")
    ok(f"catalog: {emoji} {title}, from {months.group(1) if months else '?'} months, {levels.group(1) if levels else '?'} levels, {free}")

    registry = read(APP / "lib/features/toybox/games/registry.dart")
    if re.search(r"'" + re.escape(gid) + r"':\s*\w+\.new", registry):
        ok("registry: games/registry.dart")
    else:
        bad(f"registry: add '{gid}': <Game>.new to apps/dearth_app/lib/features/toybox/games/registry.dart")

    core_tests = sorted((CORE / "test").glob("toybox*_test.dart"))
    hits = any_file(core_tests, lambda s: title in s or f"gameById('{gid}')" in s)
    ok(f"core tests: {rel(hits)}") if hits else bad(f"core tests: none name '{title}' (packages/dearth_core/test/toybox_*_test.dart)")

    app_tests = sorted((APP / "test").glob("toybox*_test.dart"))
    opener = re.compile(r"openToyboxGame\(tester,\s*'" + re.escape(gid) + "'")
    hits = any_file(app_tests, lambda s: bool(opener.search(s)))
    ok(f"widget tests: {rel(hits)}") if hits else bad(f"widget tests: no openToyboxGame(tester, '{gid}', …) in apps/dearth_app/test/toybox_*_test.dart")
    hits = any_file(app_tests, lambda s: "lays out on a" in s and f"('{gid}'," in s)
    ok(f"layout check: {rel(hits)}") if hits else bad(f"layout check: add ('{gid}', 1) and its busiest level to a 'lays out on a W×H screen' loop")

    specs = sorted((ROOT / "e2e/tests").glob("toybox*.spec.ts"))
    e2e = re.compile(r"openToyboxGame\(page,\s*'" + re.escape(gid) + "'")
    hits = any_file(specs, lambda s: bool(e2e.search(s)))
    ok(f"E2E journey: {rel(hits)}") if hits else bad(f"E2E journey: no openToyboxGame(page, '{gid}', …) in e2e/tests/toybox*.spec.ts")

    spec = read(ROOT / "SPEC.md")
    ok("SPEC: Appendix B row") if f"| {title} |" in spec else bad(f"SPEC: no Appendix B row '| {title} | …' in SPEC.md")
    ok("README: Toybox list") if title in read(ROOT / "README.md") else bad(f"README: add {title} to the Toybox paragraph")
    progress = read(ROOT / "PROGRESS.md")
    ok("PROGRESS: mentioned") if title in progress else bad(f"PROGRESS: add {title} to the 6.2 line and the Log")

    shots = APP / "test/zz_shots_test.dart"
    bad("temporary screenshot test still in apps/dearth_app/test/zz_shots_test.dart") if shots.exists() else ok("no temporary screenshot test")

    if "--no-voice" not in sys.argv:
        check_voice(ok, bad)

    print()
    if failures:
        print(f"{len(failures)} to fix.")
        return 1
    print("All wired in.")
    return 0


def check_voice(ok, bad) -> None:
    """Every voice line has its clip and every clip a line, and clips are in LFS."""
    try:
        out = subprocess.run(["dart", "run", "tool/voice_lines.dart"], cwd=CORE, capture_output=True, text=True, check=True).stdout
        ids = set(json.loads(out[out.index("{"):]))
    except (OSError, subprocess.CalledProcessError, ValueError) as e:
        bad(f"voice: couldn't list the lines ({e}); try --no-voice")
        return
    files = {p.stem for p in (APP / "assets/voice").glob("*.mp3")}
    missing, extra = sorted(ids - files), sorted(files - ids)
    if missing:
        bad(f"voice: {len(missing)} line(s) without a clip, run python3 tool/sounds/voice.py ({', '.join(missing[:6])}{'…' if len(missing) > 6 else ''})")
    if extra:
        bad(f"voice: {len(extra)} clip(s) no line says ({', '.join(extra[:6])}{'…' if len(extra) > 6 else ''})")
    if not missing and not extra:
        ok(f"voice: {len(ids)} lines, a clip for each")
    if files:
        probe = APP / "assets/voice" / f"{sorted(files)[0]}.mp3"
        attr = subprocess.run(["git", "check-attr", "filter", "--", str(probe)], cwd=ROOT, capture_output=True, text=True).stdout
        ok("voice: clips go to Git LFS") if attr.strip().endswith("lfs") else bad("voice: clips aren't LFS-tracked (.gitattributes)")


if __name__ == "__main__":
    sys.exit(main())
