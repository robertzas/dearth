package app.dearth

import android.content.pm.ActivityInfo
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The orientation the app chose last time, applied before Flutter's
        // first frame, so a wall display boots the right way up.
        applyOrientation(prefs().getString(ORIENTATION, null))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.dearth/display").setMethodCallHandler { call, result ->
            when (call.method) {
                "setOrientation" -> {
                    val mode = call.arguments as? String
                    prefs().edit().putString(ORIENTATION, mode).apply()
                    applyOrientation(mode)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun prefs() = getSharedPreferences("dearth_display", MODE_PRIVATE)

    // SPEC FR-DEV-05. "sensor" follows the accelerometer even when Android's
    // auto-rotate is off: some frame ROMs switch it off at every boot, and a
    // wall display has no one to switch it back. "user" keeps a phone's
    // rotation lock.
    private fun applyOrientation(mode: String?) {
        requestedOrientation = when (mode) {
            "sensor" -> ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
            "landscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            "portrait" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
            else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    private companion object {
        const val ORIENTATION = "orientation"
    }
}
