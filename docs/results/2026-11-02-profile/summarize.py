import csv, json, statistics, collections
from pathlib import Path
ROOT = Path('docs/results/2026-11-02-profile')
MODELS = ['Ternary-Bonsai-2-2B-PTQ1_0', 'Ternary-Bonsai-1.7B-PQ2_0']
def rows(path):
    with path.open(newline='') as f: return list(csv.DictReader(f))
def emit(name, data):
    if not data: return
    with (ROOT/name).open('w', newline='') as f:
        w=csv.DictWriter(f, fieldnames=list(data[0])); w.writeheader(); w.writerows(data)
def category(r):
    op, src = r['op'], r['src0']
    if op == 'MUL_MAT':
        for key, label in [('attn_q.weight','attention q'),('attn_k.weight','attention k'),('attn_v.weight','attention v'),('attn_qkv.weight','linear attention fused qkv'),('attn_gate.weight','linear attention gate'),('ssm_out.weight','linear attention o'),('ssm_alpha.weight','linear attention alpha/beta'),('ssm_beta.weight','linear attention alpha/beta'),('attn_output.weight','attention o'),('ffn_gate.weight','ffn gate'),('ffn_up.weight','ffn up'),('ffn_down.weight','ffn down')]:
            if key in src: return label
        if src in ('output.weight', 'token_embd.weight'): return 'output / lm_head'
        if src.startswith('prism.hadamard.'): return 'Hadamard rotations'
        return 'attention scores / values'
    if op in ('RMS_NORM','NORM','GROUP_NORM','L2_NORM') or (op == 'MUL' and 'norm' in r['tensor'].lower()): return 'norms (including scale)'
    if op == 'ROPE': return 'rope'
    if op == 'SOFT_MAX': return 'softmax'
    if op == 'GET_ROWS': return 'get_rows'
    if op.startswith('GATED_DELTA_NET'): return 'gated delta net'
    if op == 'SSM_CONV': return 'linear attention convolution'
    if op == 'FLASH_ATTN_EXT': return 'attention core (fused softmax)'
    return 'other (' + op + ')'
summary, cats, ops, tensors = [], [], [], []
for model in MODELS:
    raw = rows(ROOT/(model+'-profile-nodes.csv'))
    for phase in ['decode','prompt8']:
        steps = [r for r in rows(ROOT/(model+'-profile-steps.csv')) if r['phase']==phase]
        plain = [float(r['wall_ms']) for r in rows(ROOT/(model+'-plain-steps.csv')) if r['phase']==phase]
        wall = statistics.median(float(r['wall_ms']) for r in steps)
        node = statistics.median(float(r['node_ms']) for r in steps)
        plain = statistics.median(plain)
        bench = json.loads((ROOT/(model+'-bench.json')).read_text())
        b = next(b for b in bench if (b['n_prompt']>0)==(phase=='prompt8'))
        bench_ms = b['avg_ns']/1e6/(b['n_gen'] if phase=='decode' else 1)
        summary.append(dict(model=model,phase=phase,trials=len(steps),profile_wall_ms=wall,profile_nodes_ms=node,plain_wall_ms=plain,bench_ms=bench_ms,bench_ts=b['avg_ts'],profile_vs_plain_pct=100*(wall/plain-1),profile_vs_bench_pct=100*(wall/bench_ms-1)))
        selected = [r for r in raw if r['phase']==phase]
        for kind, key_fn, output in [('category',category,cats),('op',lambda r:r['op'],ops)]:
            grouped=collections.defaultdict(lambda:collections.defaultdict(float))
            for r in selected: grouped[key_fn(r)][int(r['trial'])] += float(r['ms'])
            for key, vals in grouped.items():
                med=statistics.median(vals.values())
                output.append(dict(model=model,phase=phase,**{kind:key},median_ms=med,pct_wall=100*med/wall,pct_nodes=100*med/node))
        grouped=collections.defaultdict(list)
        for r in selected: grouped[(r['index'],r['tensor'],r['op'],r['src0'],r['src0_type'])].append(float(r['ms']))
        for key, vals in grouped.items():
            tensors.append(dict(model=model,phase=phase,index=key[0],tensor=key[1],op=key[2],src0=key[3],runtime_src0_type=key[4],median_ms=statistics.median(vals),pct_wall=100*statistics.median(vals)/wall))
emit('summary.csv',summary); emit('categories.csv',cats); emit('operations.csv',ops); emit('tensors.csv',tensors)
for row in summary: print(row)
for row in cats:
    if row['median_ms']>0.05: print(row)
