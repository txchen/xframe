#!/usr/bin/env python3
"""Check two timestamped HUD samples captured through native UI inspection."""
import json, sys
samples = json.load(open(sys.argv[1]))
a, b = samples[0], samples[-1]
duration = (b['time'] - a['time']) / 1000
assert duration >= 10, 'Use at least ten seconds of steady foreground playback'
rate = (b['skipped'] - a['skipped']) / duration
print(f"duration={duration:.2f}s skipped={b['skipped']-a['skipped']} skip_rate={rate:.2f}/s limit=1.00/s")
# Investigation threshold, not the final long-term acceptance contract.
assert 0 <= rate <= 1, 'FAIL: sustained local skipping above one frame per second'
print('PASS')
