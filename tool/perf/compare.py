"""Compares a perf gate run with the device's baseline (tool/perf_gate.sh).

    compare.py RUN.jsonl BASELINE.json [--update] [--pss-kb N] [--model M]

Prints each scenario against the SPEC §12.1 budgets and the baseline, and
exits 1 when a scenario regressed. With --update the run becomes the
baseline instead.
"""

import argparse
import datetime
import json
import pathlib
import sys

# SPEC §12.1, per scenario where they differ.
BUDGET = {"buildP90": 7.0, "rasterP90": 10.0, "jankPct": 1.0, "over50": 0}
CPU_BUDGET = {"home_idle": 3.0, "screensaver": 12.0, "bubbles": 45.0, "paint": 45.0}
PSS_BUDGET_MB = 220

# What counts as worse than the baseline. Measured on the JT215M, three
# runs apart differ by up to ~20 % in p90 times and ~10 % in frames over
# 50 ms, and the share of frames over budget swings by 50 points where a
# scenario's frames sit at the budget (Bubble Pop's random bubbles): that
# share is shown against the budget but isn't a regression rule.
def regressions(name, now, base):
    out = []
    for key in ("totalP90", "buildP90", "rasterP90"):
        if key in now and key in base and now[key] > base[key] * 1.25 + 2:
            out.append(f"{key} {base[key]:.1f} → {now[key]:.1f} ms")
    if now.get("over50", 0) > base.get("over50", 0) * 1.3 + 5:
        out.append(f"frames over 50 ms {base['over50']} → {now['over50']}")
    if name in CPU_BUDGET and "cpuPct" in now and "cpuPct" in base and now["cpuPct"] > base["cpuPct"] + 3:
        out.append(f"CPU {base['cpuPct']:.1f} → {now['cpuPct']:.1f} %")
    if "rssMb" in now and "rssMb" in base and now["rssMb"] > base["rssMb"] * 1.15:
        out.append(f"memory {base['rssMb']} → {now['rssMb']} MB")
    if name == "soak" and now.get("growthMb", 0) > max(20, base.get("growthMb", 0) * 1.5):
        out.append(f"soak growth {base.get('growthMb', 0)} → {now['growthMb']} MB")
    return out


def over_budget(name, r):
    out = [f"{k} {r[k]}" for k, limit in BUDGET.items() if k in r and r[k] > limit]
    if name in CPU_BUDGET and r.get("cpuPct", 0) > CPU_BUDGET[name]:
        out.append(f"cpuPct {r['cpuPct']}")
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("run")
    p.add_argument("baseline")
    p.add_argument("--update", action="store_true")
    p.add_argument("--pss-kb", type=int, default=0)
    p.add_argument("--model", default="")
    a = p.parse_args()

    run = {}
    for line in pathlib.Path(a.run).read_text().splitlines():
        line = line.strip()
        if line:
            r = json.loads(line)
            run[r["name"]] = r
    if not run:
        print("no scenario results", file=sys.stderr)
        return 1
    pss_mb = a.pss_kb // 1024

    base_path = pathlib.Path(a.baseline)
    if a.update:
        base_path.parent.mkdir(parents=True, exist_ok=True)
        base_path.write_text(json.dumps({
            "model": a.model,
            "date": datetime.date.today().isoformat(),
            "pssMb": pss_mb,
            "scenarios": run,
        }, indent=2, ensure_ascii=False) + "\n")
        print(f"Baseline written: {base_path} (commit it)")
    base = json.loads(base_path.read_text())["scenarios"] if base_path.exists() else {}

    print()
    print(f"{'scenario':<14} {'fps':>5} {'build p90':>9} {'raster p90':>10} {'total p90':>9} {'jank %':>6} {'>50ms':>5} {'cpu %':>5} {'rss MB':>6}  notes")
    failed = []
    for name, r in run.items():
        if name == "soak":
            print(f"{'soak':<14} {r['minutes']} min, memory {r['rssMb'][:1]} → {r['rssMb'][-1:]} MB (growth {r['growthMb']} MB)")
            notes = []
        else:
            notes = []
            budget = over_budget(name, r)
            if budget:
                notes.append("over budget: " + ", ".join(budget))
            print(f"{name:<14} {r['fps']:>5} {r['buildP90']:>9.1f} {r['rasterP90']:>10.1f} {r['totalP90']:>9.1f} {r['jankPct']:>6.1f} {r['over50']:>5} {r.get('cpuPct', '-'):>5} {r['rssMb']:>6}  {'; '.join(notes)}")
        if name in base and not a.update:
            worse = regressions(name, r, base[name])
            if worse:
                failed.append(name)
                print(f"{'':<14} ✗ worse than the baseline: {', '.join(worse)}")
        elif not a.update:
            print(f"{'':<14} (no baseline for this scenario)")
    print()
    print(f"Memory (PSS) at the end: {pss_mb} MB (budget {PSS_BUDGET_MB} MB steady)")
    if a.update:
        return 0
    if not base:
        print(f"No baseline at {base_path}: run with --update-baseline to make one.")
        return 1
    if failed:
        print(f"✗ Perf gate failed: {', '.join(failed)}")
        return 1
    print("✓ Perf gate passed: nothing slower than the baseline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
