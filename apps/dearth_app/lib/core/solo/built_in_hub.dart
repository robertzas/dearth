import 'built_in_hub_stub.dart' if (dart.library.io) 'built_in_hub_io.dart' as impl;

/// Where the built-in Hub keeps its data instead of the app's support
/// folder. For tests only.
String? builtInHubDirOverride;

/// A row the built-in Hub writes when it is first set up: (table, id, fields).
typedef SetupRow = (String, String, Map<String, Object?>);

/// The Hub, running inside the app (SPEC §7.2 "Solo mode"): the same Hub
/// code a server runs, in a background isolate, listening on 127.0.0.1 only.
/// The app pairs with it like with any Hub, so weather, calendars, Google,
/// photos and recipe search work exactly as they do at home, and moving to
/// a server later is a copy from one Hub to another.
///
/// Not on the web: a browser can't run a server, and the web app is served
/// by a Hub anyway.
abstract class BuiltInHub {
  static bool get supported => impl.supported;

  /// The one running now, if any.
  static BuiltInHub? get current => impl.current;

  /// Starts the Hub over its data folder (stopping any running one). It
  /// listens on [port] when that is free, else on any free port; [url]
  /// says which. A new Hub's household gets [timezone]; [setup] rows are
  /// written once it is up. With [enroll], it hands back a one-time code
  /// that pairs this device as an admin (see [enrollCode]).
  static Future<BuiltInHub> start({int port = 0, String? timezone, List<SetupRow> setup = const [], ({String name, String role})? enroll}) =>
      impl.start(port: port, timezone: timezone, setup: setup, enroll: enroll);

  /// Deletes the Hub's data folder (stops it first when it is running).
  static Future<void> erase() => impl.erase();

  Uri get url;

  /// The enrollment code asked for in [start].
  String? get enrollCode;

  /// Completes when the Hub's isolate has ended (stopped, or crashed).
  Future<void> get exited;

  Future<void> stop();
}
