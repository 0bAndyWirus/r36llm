#!/usr/bin/env python3
"""Summarize the native exactness report and optional device AB/BA evidence.

Usage: python scripts/vocab/summarize.py [--device-results DIRECTORY]
The device directory is a copy of bench-device.sh's result directory. RSS is
sampled peak VmRSS (KiB), not a model-size estimate or a claim of freed weights.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--selection', type=Path, default=ROOT / 'out/vocab/selection.json')
    parser.add_argument('--x86', type=Path, default=ROOT / 'out/vocab/compare-x86.json')
    parser.add_argument('--device-results', type=Path)
    args = parser.parse_args()
    selection, x86 = load(args.selection), load(args.x86)
    prompts = x86['prompts']
    timed = x86['timed_decode_tokens_per_prompt'] * len(prompts)
    result = {
        'selection': selection,
        'x86': {
            'threads': x86['threads'],
            'generation_tokens_per_prompt': x86['generation_tokens'],
            'prompt_count': len(prompts),
            'corpus_token_count': x86['corpus_token_count'],
            'corpus_unique_misses': x86['corpus_unique_misses'],
            'kept_logit_comparisons': x86['kept_count'] * x86['generation_tokens'] * len(prompts),
            'kept_logit_mismatches': sum(p['kept_logit_mismatches'] for p in prompts),
            'dropped_logit_mismatches': sum(p['dropped_logit_mismatches'] for p in prompts),
            'greedy_differing_prompts': sum(p['first_divergence_step'] >= 0 for p in prompts),
            'divergences': [dict(p) for p in prompts if p['first_divergence_step'] >= 0],
        },
    }
    for variant in ('full', 'restricted'):
        seconds = sum(p[f'{variant}_decode_seconds'] for p in prompts)
        profiled = sum(p[f'{variant}_profile_decode_seconds'] for p in prompts)
        head = sum(p[f'{variant}_profile_head_seconds'] for p in prompts)
        result['x86'][f'{variant}_tokens_per_second'] = timed / seconds
        result['x86'][f'{variant}_profile_head_share'] = head / profiled
        result['x86'][f'{variant}_profile_head_ms_per_token'] = head * 1000 / timed
    if args.device_results:
        runs = []
        for round_number, variants in ((1, ('full', 'restricted')), (2, ('restricted', 'full'))):
            for variant in variants:
                stem = args.device_results / f'round-{round_number}-{variant}'
                rows = load(stem.with_suffix('.json'))
                decode = [r for r in rows if r['n_prompt'] == 0 and r['n_gen'] > 0]
                if len(decode) != 1:
                    raise ValueError(f'Expected one decode result in {stem}.json')
                resources = stem.with_suffix('.resources').read_text(encoding='utf-8')
                rss = [int(n) for n in re.findall(r'^VmRSS:\s*(\d+)\s+kB', resources, re.MULTILINE)]
                if not rss:
                    raise ValueError(f'No RSS samples in {stem}.resources')
                start = int(stem.with_suffix('.start-temp-mC').read_text().strip())
                if start > 55000:
                    raise ValueError(f'Thermal ceiling exceeded before {stem}')
                runs.append({'round': round_number, 'variant': variant, 'decode_tps': decode[0]['avg_ts'],
                             'peak_rss_kib': max(rss), 'start_temp_mC': start})
        means = {}
        for variant in ('full', 'restricted'):
            matching = [r for r in runs if r['variant'] == variant]
            means[variant] = {key: sum(r[key] for r in matching) / len(matching)
                              for key in ('decode_tps', 'peak_rss_kib')}
        result['device'] = {
            'runs': runs, 'means': means,
            'decode_tps_delta_percent': 100 * (means['restricted']['decode_tps'] / means['full']['decode_tps'] - 1),
            'peak_rss_delta_kib': means['restricted']['peak_rss_kib'] - means['full']['peak_rss_kib'],
            'rss_method': 'maximum sampled VmRSS per fresh process; 0.2-second sampling',
        }
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
