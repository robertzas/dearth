import 'dart:async';

import 'package:flutter/scheduler.dart';

/// A ticker for continuous motion at the display tier's ambient rate (SPEC
/// §12.3: 30 fps on T1).
///
/// Skipping every other update inside a plain ticker's callback doesn't
/// cap anything: a running ticker asks for a frame on every vsync, and each
/// of those frames is built, composited and rasterized in full even when
/// nothing changed (the kitchen frame drew Number Tracing's breathing guide
/// at 57 fps, every frame over budget). This one mutes itself after each
/// tick and wakes in time for the next frame it wants, so the frames in
/// between are never drawn at all.
class AmbientTicker {
  AmbientTicker(TickerProvider vsync, this.onTick, {required this.fps}) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;

  /// Called with the time since [start], at most [fps] times a second.
  final void Function(Duration elapsed) onTick;

  /// The rate to run at, read on every tick (the tier can change while a
  /// game is open: the device's memory is known a moment after start).
  final int Function() fps;

  Timer? _wake;

  bool get isActive => _ticker.isActive;

  TickerFuture start() => _ticker.isActive ? TickerFuture.complete() : _ticker.start();

  void stop() {
    _wake?.cancel();
    _ticker
      ..muted = false
      ..stop();
  }

  void dispose() {
    _wake?.cancel();
    _ticker.dispose();
  }

  void _tick(Duration elapsed) {
    onTick(elapsed);
    final rate = fps();
    if (rate >= 60 || !_ticker.isActive) return;
    _ticker.muted = true;
    _wake?.cancel();
    // Unmuting asks for the next vsync, so wake a little before the frame
    // that's due: about one 60 Hz frame early.
    final wait = Duration(microseconds: (1e6 / rate - 15000).round().clamp(1000, 1000000));
    _wake = Timer(wait, () {
      if (_ticker.isActive) _ticker.muted = false;
    });
  }
}
