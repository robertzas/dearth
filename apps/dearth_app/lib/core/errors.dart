import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Recent errors for diagnostics and Hub telemetry (SPEC FR-ADM-03).
final List<String> recentErrors = [];

void _record(String summary, Object error, StackTrace? stack) {
  final line = '$summary: $error';
  recentErrors.add(line);
  if (recentErrors.length > 20) recentErrors.removeAt(0);
  // Release builds print nothing by default; displays must leave a trail.
  debugPrint('Dearth error — $line\n${stack ?? ''}');
}

/// Installs global error handlers: everything is logged, nothing crashes the
/// shell, and a failed widget shows a calm "hiccup" card (SPEC §15.4).
void installErrorHandling() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _record(details.context?.toDescription() ?? 'Flutter error', details.exception, details.stack);
    if (kDebugMode) previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _record('Uncaught', error, stack);
    return true;
  };
  ErrorWidget.builder = (details) => const _HiccupCard();
}

class _HiccupCard extends StatelessWidget {
  const _HiccupCard();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('This part hiccuped 🙈', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Color(0xFF8C8794))),
      ),
    );
  }
}

/// Runs [body] and logs any error it throws (fire-and-forget UI actions).
Future<void> guarded(Future<void> Function() body, String what) async {
  try {
    await body();
  } on Object catch (e, st) {
    _record(what, e, st);
    rethrow;
  }
}
