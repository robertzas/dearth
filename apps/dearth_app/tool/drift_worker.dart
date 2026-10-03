// Entry point of drift's web worker (compiled to web/drift_worker.js by
// tool/web_assets.sh). Runs SQLite (wasm) off the UI thread with OPFS or
// IndexedDB storage (SPEC §8.1).
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
