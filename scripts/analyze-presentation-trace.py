#!/usr/bin/env python3
"""Summarize actual presentation cadence and joined frame timings (schemas 9/10)."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path


def distribution(values):
    values = sorted(values)
    if not values:
        return None
    return dict(count=len(values), meanMS=sum(values) / len(values),
                p50MS=values[math.ceil(len(values) * .50) - 1],
                p95MS=values[math.ceil(len(values) * .95) - 1], maxMS=values[-1])


def analyze(report):
    frames = defaultdict(dict)
    events = report['frameTrace']
    for event in events:
        if event.get('frameID') is not None:
            frames[event['frameID']][event['stage']] = event['seconds']
    shown = sorted(e['seconds'] for e in events if e['stage'] == 'presented')
    intervals = [(b - a) * 1000 for a, b in zip(shown, shown[1:])]
    phases = {}
    for name, start, end in [('arrivalToSubmit', 'delivered', 'submitted'),
                             ('gpuQueue', 'submitted', 'gpuStarted'),
                             ('gpu', 'gpuStarted', 'gpuCompleted'),
                             ('displayWait', 'gpuCompleted', 'presented'),
                             ('arrivalToDisplay', 'delivered', 'presented')]:
        phases[name] = distribution([(f[end] - f[start]) * 1000 for f in frames.values()
                                     if start in f and end in f and f[end] >= f[start]])
    drop_stages = {'inboxOverflow', 'expired', 'catchUp', 'rendererReplaced', 'notPresented'}
    drops = Counter(e['stage'] for e in events if e['stage'] in drop_stages)
    # Match both endpoints so a truncated ring cannot invent negative occupancy.
    occupancy = []
    for frame in frames.values():
        if 'gpuCompleted' in frame and 'presented' in frame and frame['presented'] >= frame['gpuCompleted']:
            occupancy.extend([(frame['gpuCompleted'], 1), (frame['presented'], -1)])
    pending = peak = 0
    for _, delta in sorted(occupancy):
        pending += delta
        peak = max(peak, pending)
    return dict(schemaVersion=report['schemaVersion'], frameIntervals=distribution(intervals),
                gapsOver25MS=sum(x > 25 for x in intervals), phases=phases,
                discardedInTrace=dict(drops), peakCompletedAwaitingPresentation=peak if occupancy else None,
                notes=['Bounded trace tail; endpoints and stage populations may differ.',
                       '25 ms gaps are a 60 Hz diagnostic, not a refresh-independent failure threshold.',
                       'Presentation is the drawable timestamp, not physical input-to-photon latency.',
                       'Missing stages are unavailable, not zero.'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    print(json.dumps(analyze(json.loads(args.report.read_text())), indent=2))
