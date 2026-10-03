import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/data/household.dart';

/// Grown-up mode (SPEC §9.3): adult actions on shared displays need a PIN,
/// relock after 2 minutes idle, and show a visible lock state.
@immutable
class GrownUpState {
  const GrownUpState({this.profileId, this.untilMs = 0, this.failures = 0, this.lockedUntilMs = 0});

  /// The adult who unlocked (stamped as the actor on gated ops).
  final String? profileId;
  final int untilMs;
  final int failures;
  final int lockedUntilMs;

  bool unlockedAt(int nowMs) => profileId != null && untilMs > nowMs;
}

class GrownUpController extends Notifier<GrownUpState> {
  static const unlockFor = Duration(minutes: 2);
  static const maxFailures = 5;
  static const lockout = Duration(seconds: 30);
  Timer? _relock;

  @override
  GrownUpState build() {
    ref.onDispose(() => _relock?.cancel());
    return const GrownUpState();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Whether adult actions are allowed right now without a prompt.
  bool get isOpen {
    final s = ref.read(deviceSettingsProvider);
    if (s.isPersonal) return true;
    if (!ref.read(pinsConfiguredProvider)) return true;
    return state.unlockedAt(_now);
  }

  /// Verifies [pin] against every adult's hash. Returns success.
  Future<bool> unlock(String pin) async {
    if (state.lockedUntilMs > _now) return false;
    final adults = ref.read(profilesProvider).value?.where(_isAdult).where((p) => p.pinHash != null).toList() ?? const <Profile>[];
    // Off the UI isolate where available: PBKDF2 takes ~100 ms on T1.
    final match = await compute(_findMatch, (pin, [for (final p in adults) (p.id, p.pinHash!)]));
    if (match == null) {
      final failures = state.failures + 1;
      state = GrownUpState(
        failures: failures >= maxFailures ? 0 : failures,
        lockedUntilMs: failures >= maxFailures ? _now + lockout.inMilliseconds : 0,
      );
      return false;
    }
    _grant(match);
    return true;
  }

  static String? _findMatch((String, List<(String, String)>) args) {
    final (pin, hashes) = args;
    for (final (id, hash) in hashes) {
      if (verifyPin(pin, hash)) return id;
    }
    return null;
  }

  void _grant(String profileId) {
    state = GrownUpState(profileId: profileId, untilMs: _now + unlockFor.inMilliseconds);
    _scheduleRelock();
  }

  /// Extends the unlock window on activity while unlocked.
  void touch() {
    if (!state.unlockedAt(_now)) return;
    state = GrownUpState(profileId: state.profileId, untilMs: _now + unlockFor.inMilliseconds);
    _scheduleRelock();
  }

  void lock() {
    _relock?.cancel();
    state = const GrownUpState();
  }

  void _scheduleRelock() {
    _relock?.cancel();
    _relock = Timer(Duration(milliseconds: state.untilMs - _now), lock);
  }
}

bool _isAdult(Profile p) => p.role == ProfileRole.adult || p.role == ProfileRole.caregiver;

final grownUpProvider = NotifierProvider<GrownUpController, GrownUpState>(GrownUpController.new);

/// Whether any adult has a PIN (without one, grown-up mode is open).
final pinsConfiguredProvider = Provider<bool>((ref) {
  final list = ref.watch(profilesProvider).value ?? const <Profile>[];
  return list.any((p) => _isAdult(p) && p.pinHash != null && p.pinHash!.isNotEmpty);
});

/// Lock indicator state for the shell (null = no PINs configured).
final grownUpUnlockedProvider = Provider<bool?>((ref) {
  if (!ref.watch(pinsConfiguredProvider)) return null;
  if (ref.watch(deviceSettingsProvider.select((s) => s.isPersonal))) return true;
  final s = ref.watch(grownUpProvider);
  return s.unlockedAt(DateTime.now().millisecondsSinceEpoch);
});

/// The actor for gated ops: the unlocked adult, else the device owner on a
/// personal device, else the first adult when no PINs exist.
final grownUpActorProvider = Provider<String?>((ref) {
  final s = ref.watch(grownUpProvider);
  if (s.profileId != null) return 'profile:${s.profileId}';
  final device = ref.watch(thisDeviceProvider).value;
  if (device?.ownerProfileId != null) return 'profile:${device!.ownerProfileId}';
  if (!ref.watch(pinsConfiguredProvider)) {
    final adult = (ref.watch(profilesProvider).value ?? const <Profile>[]).where(_isAdult).firstOrNull;
    return adult == null ? null : 'profile:${adult.id}';
  }
  return null;
});

/// Runs the grown-up gate: returns true at once when open, otherwise shows
/// the PIN pad and returns whether it was unlocked.
Future<bool> ensureGrownUp(BuildContext context, WidgetRef ref, {String? reason}) async {
  final c = ref.read(grownUpProvider.notifier);
  if (c.isOpen) {
    c.touch();
    return true;
  }
  final ok = await showDSheet<bool>(
    context,
    title: 'Grown-up mode',
    id: 'grownup.sheet',
    builder: (context) => _PinSheet(reason: reason),
  );
  return ok ?? false;
}

class _PinSheet extends ConsumerWidget {
  const _PinSheet({this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final s = ref.watch(grownUpProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.lg),
      child: Center(
        child: DPinPad(
          title: '🔒',
          subtitle: reason ?? 'Enter a grown-up PIN',
          lockedUntil: s.lockedUntilMs > 0 ? DateTime.fromMillisecondsSinceEpoch(s.lockedUntilMs) : null,
          onSubmit: (pin) async {
            final ok = await ref.read(grownUpProvider.notifier).unlock(pin);
            if (ok && context.mounted) Navigator.of(context).pop(true);
            return ok;
          },
        ),
      ),
    );
  }
}
