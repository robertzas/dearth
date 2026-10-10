"""Compares a perf gate run with the device's baseline (tool/perf_gate.sh).

    compare.py RUN.jsonl BASELINE.json [--update] [--pss-kb N] [--model M]
               [--report REPORT.md] [--context CONTEXT.json]

Prints each scenario against the SPEC §12.1 budgets and the baseline, and
exits 1 when a scenario regressed. With --update the run becomes the
baseline instead. --report also writes it all as Markdown, headed by the
run's context (what perf_gate.sh did to the device, as {"title", "facts":
[[label, value]], "steps": [text]}).
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
    p.add_argument("--report")
    p.add_argument("--context")
    p.add_argument("--run-failed", help="why the run didn't finish: reported, and the gate fails")
    a = p.parse_args()

    run = {}
    run_path = pathlib.Path(a.run)
    for line in (run_path.read_text() if run_path.exists() else "").splitlines():
        line = line.strip()
        if line:
            r = json.loads(line)
            run[r["name"]] = r
    if not run:
        print("no scenario results", file=sys.stderr)
        if a.report:
            write_report(pathlib.Path(a.report), a, [], {}, a.pss_kb // 1024, f"✗ Failed: {a.run_failed or 'no scenario results'}.")
            print(f"Report: {a.report}")
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

    rows = []  # (name, result, over budget, worse than the baseline or None)
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
        worse = None
        if name in base and not a.update:
            worse = regressions(name, r, base[name])
            if worse:
                failed.append(name)
                print(f"{'':<14} ✗ worse than the baseline: {', '.join(worse)}")
        elif not a.update:
            print(f"{'':<14} (no baseline for this scenario)")
        for label, part in (r.get("parts") or {}).items():
            print(f"{'':<14}   {label:<12} {part['frames']:>4} frames, build p90 {part['buildP90']:.1f} ms, total p90 {part['totalP90']:.1f} ms")
        rows.append((name, r, [] if name == "soak" else over_budget(name, r), worse))
    print()
    print(f"Memory (PSS) at the end: {pss_mb} MB (budget {PSS_BUDGET_MB} MB steady)")
    if a.run_failed:
        verdict, code = f"✗ Failed: {a.run_failed}. The scenarios that finished are below.", 1
    elif a.update:
        verdict, code = "Baseline updated: this run is the device's new baseline (commit it).", 0
    elif not base:
        verdict, code = f"No baseline at {base_path.name}: run with --update-baseline to make one.", 1
    elif failed:
        verdict, code = f"✗ Failed: slower than the baseline in {', '.join(failed)}.", 1
    else:
        verdict, code = "✓ Passed: nothing slower than the baseline.", 0
    print(verdict.replace("Failed:", "Perf gate failed:").replace("Passed:", "Perf gate passed:"))
    if a.report:
        write_report(pathlib.Path(a.report), a, rows, base, pss_mb, verdict)
        print(f"Report: {a.report}")
    return code


def write_report(path, a, rows, base, pss_mb, verdict):
    ctx = json.loads(pathlib.Path(a.context).read_text()) if a.context else {}
    md = [f"# {ctx.get('title', 'Perf gate')}", "", f"**{verdict}**", ""]
    for label, value in ctx.get("facts", []):
        md.append(f"- **{label}:** {value}")
    if ctx.get("steps"):
        md += ["", "## What the gate did", ""] + [f"{i}. {step}" for i, step in enumerate(ctx["steps"], 1)]
    md += ["", "## Scenarios", "", "SPEC §12.1 budgets: build p90 ≤ 7 ms, raster p90 ≤ 10 ms, ≤ 1 % janky frames, no frame over 50 ms. "
           "A scenario fails the gate only when it got worse than the baseline; known misses are listed, not failed.", "",
           "| Scenario | fps | build p90 | raster p90 | total p90 (baseline) | janky % | > 50 ms | CPU % | RSS MB | Result |",
           "|---|---:|---:|---:|---:|---:|---:|---:|---:|---|"]
    for name, r, budget, worse in rows:
        if name == "soak":
            md.append(f"| soak | {r['minutes']} min | | | | | | | {r['rssMb'][0]} → {r['rssMb'][-1]} | growth {r['growthMb']} MB{'; ✗ ' + ', '.join(worse) if worse else ''} |")
            continue
        b = base.get(name, {})
        was = f" ({b['totalP90']:.1f})" if "totalP90" in b else ""
        result = "✗ " + ", ".join(worse) if worse else ("no baseline" if worse is None and not a.update else "✓")
        if budget:
            result += f"; over budget: {', '.join(budget)}"
        md.append(f"| {name} | {r['fps']} | {r['buildP90']:.1f} | {r['rasterP90']:.1f} | {r['totalP90']:.1f}{was} | {r['jankPct']:.1f} | {r['over50']} | {r.get('cpuPct', '-')} | {r['rssMb']} | {result} |")
    for name, r, _, _ in rows:
        parts, was = r.get("parts"), base.get(name, {}).get("parts", {})
        if parts:
            md += ["", f"### {name}, step by step", "", "| Step | frames | build p90 | total p90 (baseline) |", "|---|---:|---:|---:|"]
            for label, p in parts.items():
                b = f" ({was[label]['totalP90']:.1f})" if label in was else ""
                md.append(f"| `{label}` | {p['frames']} | {p['buildP90']:.1f} | {p['totalP90']:.1f}{b} |")
    md += ["", f"Memory (PSS) at the end: **{pss_mb} MB** (budget {PSS_BUDGET_MB} MB; baseline {json.loads(pathlib.Path(a.baseline).read_text()).get('pssMb', '?') if pathlib.Path(a.baseline).exists() else '?'} MB)."]
    if ctx.get("files"):
        md += ["", "## Files", ""] + [f"- {label}: `{value}`" for label, value in ctx["files"]]
    path.write_text("\n".join(md) + "\n")


if __name__ == "__main__":
    sys.exit(main())
