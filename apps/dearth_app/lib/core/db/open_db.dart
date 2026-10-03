import 'package:dearth_core/dearth_core.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Opens the device replica (SPEC §8.1): SQLite on a background isolate on
/// native platforms, sqlite3.wasm in a worker (OPFS, IndexedDB fallback) on
/// the web. The wasm module and `drift_worker.js` ship in `web/`.
DearthDb openDeviceDb({String name = 'dearth'}) => DearthDb(
      driftDatabase(
        name: name,
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      ),
    );
