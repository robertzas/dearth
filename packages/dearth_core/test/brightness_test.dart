import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

void main() {
  group('FR-DSP-02 brightness curve', () {
    test('dark room → the floor, daylight → the ceiling, a lit kitchen in between', () {
      const c = BrightnessCurve(0.15, 1.0);
      expect(c.at(0), closeTo(0.15, 1e-9));
      expect(c.at(2), closeTo(0.15, 1e-9));
      expect(c.at(5000), closeTo(1.0, 1e-9));
      final kitchen = c.at(110);
      expect(kitchen, inInclusiveRange(0.6, 0.8));
      // Monotonic: more light, never dimmer.
      var last = 0.0;
      for (final lux in <double>[0, 1, 3, 10, 30, 100, 300, 800, 2000]) {
        final b = c.at(lux);
        expect(b, greaterThanOrEqualTo(last));
        last = b;
      }
    });

    test('the family can ask for dimmer or brighter, within 0…1', () {
      const c = BrightnessCurve(0.15, 1.0);
      expect(c.at(110, bias: -1), lessThan(c.at(110)));
      expect(c.at(110, bias: 1), greaterThan(c.at(110)));
      expect(c.at(0, bias: -1), lessThan(c.at(0)), reason: 'a lower floor in a dark room');
      expect(c.at(5000, bias: 1), 1.0);
      expect(c.at(0, bias: -1), greaterThan(0));
    });

    test('the night clock stays barely lit even with the lights on; off is black', () {
      expect(targetBrightness(BrightnessScene.night, 300)!, lessThanOrEqualTo(0.12));
      expect(targetBrightness(BrightnessScene.night, 0)!, closeTo(0.01, 1e-9));
      expect(targetBrightness(BrightnessScene.off, 1000), 0);
      expect(targetBrightness(BrightnessScene.screensaver, 110)!, lessThan(targetBrightness(BrightnessScene.active, 110)!));
    });

    test('without a light sensor the system keeps the day, and the night still dims', () {
      expect(targetBrightness(BrightnessScene.active, null), isNull);
      expect(targetBrightness(BrightnessScene.screensaver, null), isNull);
      expect(targetBrightness(BrightnessScene.night, null), 0.03);
      expect(targetBrightness(BrightnessScene.nightAwake, null), 0.2);
      expect(targetBrightness(BrightnessScene.off, null), 0);
    });
  });

  group('ambient light', () {
    test('a passing shadow barely moves it; lights on are followed within seconds', () {
      final a = AmbientLight();
      a.add(200, 0);
      // A hand over the sensor for half a second.
      expect(a.add(1, 500), greaterThan(100));
      a.add(200, 1000);
      // The lights go on: most of the way there in 4 s (ticks of 1 s).
      final b = AmbientLight()..add(5, 0);
      double lux = 5;
      for (var t = 1000; t <= 4000; t += 1000) {
        lux = b.add(400, t);
      }
      expect(lux, greaterThan(150));
    });

    test('a room going dark is followed more slowly than one lighting up', () {
      final up = AmbientLight()..add(10, 0);
      final down = AmbientLight()..add(400, 0);
      // Halfway on the log scale is 63 lux (√(10 × 400)).
      expect(up.add(400, 2000), greaterThan(63), reason: 'past halfway up in 2 s');
      expect(down.add(10, 2000), greaterThan(63), reason: 'not yet halfway down in 2 s');
    });
  });

  group('§10.12 night when the room is dark', () {
    test('two minutes below the threshold to go dark, twenty seconds of light to come back', () {
      final r = DarkRoom();
      expect(r.update(1, 0), isFalse);
      expect(r.update(1, 60 * 1000), isFalse);
      expect(r.update(1, 120 * 1000), isTrue);
      // A lamp for ten seconds doesn't wake it.
      expect(r.update(50, 130 * 1000), isTrue);
      expect(r.update(1, 140 * 1000), isTrue);
      expect(r.update(50, 150 * 1000), isTrue);
      expect(r.update(50, 171 * 1000), isFalse);
    });

    test('a moment of dark resets the count', () {
      final r = DarkRoom();
      r.update(1, 0);
      r.update(100, 100 * 1000);
      expect(r.update(1, 130 * 1000), isFalse);
      expect(r.update(1, 249 * 1000), isFalse);
      expect(r.update(1, 250 * 1000), isTrue);
    });
  });

  group('FR-DSP-02 no flicker', () {
    test('small changes are ignored; a real one ramps; a new scene jumps', () {
      final r = BrightnessRamp();
      expect(r.retarget(0.5), isTrue, reason: 'the first value applies at once');
      expect(r.current, 0.5);
      expect(r.retarget(0.52), isFalse);
      expect(r.step(const Duration(seconds: 1)), isNull);
      r.retarget(0.9);
      expect(r.step(const Duration(milliseconds: 200)), closeTo(0.6, 1e-9));
      expect(r.step(const Duration(seconds: 2)), closeTo(0.9, 1e-9));
      expect(r.settled, isTrue);
      expect(r.retarget(0.02, jump: true), isTrue);
      expect(r.current, 0.02);
      expect(r.retarget(null), isTrue, reason: 'back to the system at once');
      expect(r.current, isNull);
    });
  });
}
