import 'dart:convert';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';

/// Prints every Toybox voice line as JSON ({clip id: words}) for
/// tool/sounds/voice.py, which turns them into the app's voice clips.
void main() => stdout.write(const JsonEncoder.withIndent('  ').convert(kVoiceLines));
