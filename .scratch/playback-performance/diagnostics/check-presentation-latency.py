#!/usr/bin/env python3
"""Physical presentation timestamp gate; diagnostic target for this 60 Hz experiment."""
import json,sys
r=json.load(open(sys.argv[1]))
t=r['timings']['presentation']; v=r['video']
ratio=v['presented']/max(1,v['decoded'])
print(f"present mean={t['meanMS']:.2f}ms p95={t['p95MS']:.2f}ms delivered={ratio:.3%}")
assert r['durationSeconds'] >= 30 and t['recentCount'] >= 200
assert t['meanMS'] <= 25 and t['p95MS'] <= 40, 'FAIL: local presentation exceeds 25ms mean / 40ms p95 experiment target'
assert ratio >= .98 and v['decodeErrors'] == 0, 'FAIL: output coverage or decode stability regressed'
print('PASS (recent timing window; check steady foreground interval and long-session behavior separately)')
