#!/usr/bin/env python3
"""Analyze actual presentations; sparse blocks are diagnostic, never ranked by FPS."""
import json
import math
import sys
from pathlib import Path

def stats(values):
    if not values:
        return None
    values = sorted(values)
    def p(q):
        x = (len(values)-1)*q
        low = math.floor(x)
        high = math.ceil(x)
        return round(values[low] + (values[high]-values[low])*(x-low), 4)
    return dict(n=len(values), mean=round(sum(values)/len(values), 4), p50=p(.5), p95=p(.95), p99=p(.99))

def analyze(path):
    report = json.loads(path.read_text())
    frames = {}
    for row in report['events']:
        if 'id' in row:
            frames.setdefault(int(row['id']), {}).update(row)
    blocks = []
    for block, mode in enumerate(report['modes']):
        lo = report['start'] + block*report['blockSeconds'] + 3
        hi = report['start'] + (block+1)*report['blockSeconds'] - 1
        rows = [r for r in frames.values() if r.get('block') == block and lo <= r.get('submit', -1) < hi]
        valid = [r for r in rows if r.get('error') == 0 and r.get('actual', 0) > 0 and r.get('gpuEnd', 0) > 0 and r['actual'] >= r['gpuEnd']]
        actuals = sorted(r['actual'] for r in valid)
        gaps = [(b-a)*1000 for a,b in zip(actuals, actuals[1:])]
        ticks = [r for r in report['events'] if 'tick' in r and lo <= r['time'] < hi]
        blocks.append(dict(block=block, mode='continuous60' if mode == 0 else ('isolated' if mode == 1 else f'isolated-offset-{(mode-2)*2}ms'), submitted=len(rows), invalid=len(rows)-len(valid),
            fullscreen=all(r['fullscreen'] == 1 for r in rows) and bool(rows),
            pending_before=stats([r['pendingBefore'] for r in rows]),
            requested_wake_error_ms=stats([(r['submit']-r['intended'])*1000 for r in valid if r.get('intended',0)>0]),
            gpu_to_clock_target_ms=stats([(r['refreshTarget']-r['gpuEnd'])*1000 for r in valid if r.get('refreshTarget',0)>0]),
            actual_minus_clock_target_ms=stats([(r['actual']-r['refreshTarget'])*1000 for r in valid if r.get('refreshTarget',0)>0]),
            gpu_ms=stats([(r['gpuEnd']-r['gpuStart'])*1000 for r in valid]),
            gpu_to_display_ms=stats([(r['actual']-r['gpuEnd'])*1000 for r in valid]),
            submit_to_display_ms=stats([(r['actual']-r['submit'])*1000 for r in valid]),
            acquire_ms=stats([(r['acquired']-r['acquire'])*1000 for r in rows]),
            presented_callback_lag_ms=stats([(r['presentCallback']-r['actual'])*1000 for r in valid]),
            intervals_ms=stats(gaps), long_intervals_over25ms=sum(g>25 for g in gaps) if mode == 0 else None,
            tick_intervals_ms=stats([(b['time']-a['time'])*1000 for a,b in zip(ticks,ticks[1:])]),
            fps=(len(actuals)-1)/(actuals[-1]-actuals[0]) if mode == 0 and len(actuals)>1 else None))
    return dict(source=str(path), status=report['status'], device=report['device'], screen=report['screen'], drawable=report['drawableSize'], pending_at_export=report['pendingAtExport'], log_overflow=report.get('logOverflow', 0), blocks=blocks)

if __name__ == '__main__':
    print(json.dumps(analyze(Path(sys.argv[1])), indent=2))
