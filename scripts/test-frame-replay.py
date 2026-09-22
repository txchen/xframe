import importlib.util
import unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location('replay', Path(__file__).with_name('replay-frame-trace.py'))
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)


def fixture():
    events = []
    ticks = list(range(0, 90000, 1500)) + list(range(90000, 180000, 2250)) + list(range(180000, 270001, 1500))
    for tick in ticks:
        rtp = (0xffff0000 + tick) & 0xffffffff
        for stage, offset in [('decoderInput', 0), ('decoded', .004), ('delivered', .005), ('presented', .020)]:
            events.append(dict(stage=stage, rtp=rtp, seconds=tick/90000+offset))
    return {'frameTrace': events, 'provenance': 'SYNTHETIC 60-40-60; not Palworld gameplay'}


def variable_fixture():
    # Smoothly changing cadence, with RTP quantization; no fixed-rate plateaus.
    import math
    events = []
    time = 0.0
    while time <= 6:
        rate = 50 + 8 * math.cos(2 * math.pi * time / 6)
        tick = round(time * 90000)
        for stage, offset in [('decoderInput', 0), ('decoded', .004), ('delivered', .005), ('presented', .020)]:
            events.append(dict(stage=stage, rtp=tick, seconds=tick/90000+offset))
        time += 1 / rate
    return {'frameTrace': events, 'provenance': 'SYNTHETIC continuously variable approximately 58-42-58 fps; not Palworld gameplay'}


class ReplayTests(unittest.TestCase):
    def test_transition_and_wrap(self):
        result = replay.evaluate(fixture())
        middle = [t for t in result['ticks'] if 1 <= t['sourceSeconds'] < 2]
        self.assertEqual(sum(t['kind']=='interpolate' for t in middle), 40)
        self.assertAlmostEqual(max(t['futureSourceWaitMS'] for t in middle), 1000/60)
        self.assertAlmostEqual(result['summary']['fixedDelayToCoverAvailableMS'], 1000/60+4)
        self.assertEqual(result['summary']['unavailable'], 0)
    def test_continuously_variable_cadence(self):
        data = variable_fixture()
        result = replay.evaluate(data)
        inputs = [e for e in data['frameTrace'] if e['stage']=='decoderInput']
        times = {e['rtp']: e['seconds'] for e in inputs}
        rates = [1/(b['seconds']-a['seconds']) for a,b in zip(inputs, inputs[1:])]
        self.assertLess(min(rates), 42.1)
        self.assertGreater(max(rates), 57.9)
        self.assertEqual(result['summary']['unavailable'], 0)
        for tick in result['ticks']:
            left, right = times[tick['leftRTP']], times[tick['rightRTP']]
            self.assertLessEqual(left, tick['sourceSeconds'] + 1e-7)
            self.assertGreaterEqual(right, tick['sourceSeconds'] - 1e-7)
            self.assertAlmostEqual(left + tick['alpha']*(right-left), tick['sourceSeconds'], places=6)
            self.assertAlmostEqual(tick['requiredDelayMS'], (right+.004-tick['sourceSeconds'])*1000)
        self.assertLessEqual(result['summary']['fixedDelayToCoverAvailableMS'], 1000/42+4.02)

    def test_missing_reference(self):
        data = fixture()
        data['frameTrace'] = [e for e in data['frameTrace'] if not (e['stage']=='decoded' and abs(e['seconds']-1.029)<1e-8)]
        self.assertGreater(replay.evaluate(data)['summary']['unavailable'], 0)
    def test_discontinuity(self):
        data = fixture()
        data['frameTrace'][4]['rtp'] = data['frameTrace'][0]['rtp']
        with self.assertRaises(ValueError): replay.evaluate(data)


if __name__ == '__main__': unittest.main()
