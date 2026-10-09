import 'built_in_hub.dart';

const bool supported = false;

BuiltInHub? get current => null;

Future<BuiltInHub> start({int port = 0, String? timezone, List<SetupRow> setup = const [], ({String name, String role})? enroll}) =>
    throw UnsupportedError('The built-in Hub needs a native platform');

Future<void> erase() async {}
