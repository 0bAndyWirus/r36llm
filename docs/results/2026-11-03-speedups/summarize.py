#!/usr/bin/env python3
"""Summarize two-round engine AB/BA and instrumented headless timings."""
import argparse
import json
import re
import statistics
from pathlib import Path


def summarize(root):
    result = {"engine": [], "gap": [], "matched": []}
    for suite in ("speedups-rows", "speedups-state"):
        directory = root / suite
        grouped = {}
        for path in sorted(directory.glob("round-*.json")):
            match = re.fullmatch(r"round-(\d+)-(baseline|patched)-(.+)\.json", path.name)
            if not match:
                continue
            round_id, variant, model = match.groups()
            for test in json.loads(path.read_text()):
                key = model, test["n_prompt"], test["n_gen"]
                grouped.setdefault(key, {}).setdefault(variant, []).append({
                    "round": int(round_id), "avg_ts": test["avg_ts"],
                    "samples_ts": test.get("samples_ts", []),
                    "samples_ns": test.get("samples_ns", []),
                })
        for (model, prompt, generation), variants in grouped.items():
            row = {"suite": suite, "model": model, "n_prompt": prompt, "n_gen": generation, "trials": variants}
            for variant, trials in variants.items():
                row[variant + "_tps"] = statistics.mean(t["avg_ts"] for t in trials)
            if "baseline_tps" in row and "patched_tps" in row:
                row["delta_percent"] = 100*(row["patched_tps"]/row["baseline_tps"] - 1)
                row["round_delta_percent"] = [100*(p["avg_ts"]/b["avg_ts"] - 1) for b, p in zip(variants["baseline"], variants["patched"])]
            result["engine"].append(row)
        if (directory / "original-governors.tsv").exists():
            result[suite + "_governors_restored"] = (directory / "original-governors.tsv").read_bytes() == (directory / "restored-governors.tsv").read_bytes()
    for suite, category in (("speedups-gap", "gap"), ("speedups-matched", "matched")):
        for path in sorted((root / suite).glob("*.stderr")):
            match = re.search(r"^GAP (.+)$", path.read_text(), re.M)
            if not match:
                continue
            values = {key: float(value) for key, value in re.findall(r"(\w+)=([\d.]+)", match[1])}
            values["trial"] = path.stem
            values["kind"] = "app"
            values["sample_ms_per_token"] = values["sample_s"]*1000/values["generated"]
            values["decode_tps"] = values["generated"]/values["decode_s"]
            values["full_tps"] = values["generated"]/values["full_s"]
            values["non_decode_percent"] = 100*(values["full_s"]-values["decode_s"])/values["full_s"]
            result[category].append(values)
    for path in sorted((root / "speedups-matched").glob("bench*.json")):
        test = json.loads(path.read_text())[0]
        result["matched"].append({
            "trial": path.stem, "kind": "bench", "full_tps": test["avg_ts"],
            "n_depth": test["n_depth"], "n_gen": test["n_gen"],
        })
    if result["matched"]:
        app = [t for t in result["matched"] if t["kind"] == "app"]
        bench = [t for t in result["matched"] if t["kind"] == "bench"]
        app_tps = statistics.mean(t["full_tps"] for t in app)
        app_decode_tps = statistics.mean(t["decode_tps"] for t in app)
        bench_tps = statistics.mean(t["full_tps"] for t in bench)
        result["matched_means"] = {
            "app_tps": app_tps, "app_decode_tps": app_decode_tps, "bench_tps": bench_tps,
            "app_gap_percent": 100*(app_tps/bench_tps - 1),
            "decode_gap_percent": 100*(app_decode_tps/bench_tps - 1),
        }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.root), indent=2))
