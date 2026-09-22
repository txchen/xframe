#!/usr/bin/env python3
"""Replay schema-9 timing traces. No optical-flow or image quality simulation."""
import argparse
import bisect
import json
import math
from pathlib import Path


def evaluate(report, fps=60):
    events = report['frameTrace']
    stages = {name: sorted((e for e in events if e['stage'] == name), key=lambda e: e['seconds'])
              for name in ('decoderInput', 'decoded', 'delivered', 'presented')}
    inputs = stages['decoderInput']
    if len(inputs) < 2:
        raise ValueError('Need at least two decoder input frames')
    # Unwrap modulo 2^32. Reject reordering/reset rather than invent a timeline.
    source = [0.0]
    for a, b in zip(inputs, inputs[1:]):
        delta = (b['rtp'] - a['rtp']) & 0xffffffff
        if not 0 < delta <= 90000:
            raise ValueError('RTP duplicate/reorder/reset or >1 s gap: capture a continuous segment')
        source.append(source[-1] + delta / 90000)
    decoded = {e['rtp']: e['seconds'] for e in stages['decoded']}
    origin = inputs[0]['seconds']
    ticks = []
    for k in range(math.floor(source[-1] * fps + 1e-7) + 1):
        t = k / fps
        right = bisect.bisect_left(source, t - 1e-7)
        if right == len(source):
            break
        exact = abs(source[right] - t) < 1e-7
        left = right if exact else right - 1
        a, b = inputs[left], inputs[right]
        ready = [decoded.get(a['rtp']), decoded.get(b['rtp'])]
        available = all(v is not None for v in ready)
        ticks.append(dict(tick=k, sourceSeconds=t, kind='original' if exact else 'interpolate',
                          leftRTP=a['rtp'], rightRTP=b['rtp'],
                          alpha=0 if exact else (t-source[left])/(source[right]-source[left]),
                          futureSourceWaitMS=(source[right]-t)*1000,
                          available=available,
                          requiredDelayMS=max(0, max(ready)-origin-t)*1000 if available else None))
    # Common full one-second local windows make stage rates comparable.
    start = math.ceil(max(es[0]['seconds'] for es in stages.values() if es))
    end = math.floor(min(es[-1]['seconds'] for es in stages.values() if es))
    windows = []
    for second in range(start, end):
        row = {'localSecond': second}
        for name, es in stages.items():
            row[name + 'FPS'] = sum(second <= e['seconds'] < second + 1 for e in es)
        indices = [i for i, e in enumerate(inputs) if second <= e['seconds'] < second+1]
        row['sourceFPS'] = ((len(indices)-1)/(source[indices[-1]]-source[indices[0]])) if len(indices)>1 else None
        windows.append(row)
    delays = [t['requiredDelayMS'] for t in ticks if t['available']]
    return dict(targetFPS=fps, windows=windows, ticks=ticks,
                summary=dict(original=sum(t['kind']=='original' for t in ticks),
                             generated=sum(t['kind']=='interpolate' for t in ticks),
                             unavailable=sum(not t['available'] for t in ticks),
                             fixedDelayToCoverAvailableMS=max(delays, default=None)),
                assumptions=['Decoder input is post WebRTC jitter buffer, not packet receipt.',
                             'RTP cadence is not unique game-image cadence.',
                             'Delay is relative to first decoder input plus source time; includes local arrival jitter/decode.',
                             'Two-sided interpolation; excludes generation/GPU cost and display scheduling.',
                             'Unavailable reference ticks cannot be covered by the reported delay.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = evaluate(json.loads(args.report.read_text()))
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result['summary'], indent=2))


if __name__ == '__main__':
    main()
