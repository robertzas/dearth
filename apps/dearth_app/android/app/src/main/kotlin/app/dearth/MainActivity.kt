package app.dearth

import android.app.ActivityManager
import android.content.Intent
import android.content.pm.ActivityInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The orientation the app chose last time, applied before Flutter's
        // first frame, so a wall display boots the right way up.
        applyOrientation(prefs().getString(ORIENTATION, null))
        takeKioskKey(intent)
        takeToolExtras(intent)
    }

    override fun onResume() {
        super.onResume()
        inFront = true
    }

    override fun onPause() {
        inFront = false
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeKioskKey(intent)
        if (takeToolExtras(intent)) tool?.invokeMethod("nudge", null)
    }

    // Tool commands from the developer's machine over ADB (tool/perf_gate.sh):
    // `--es dearth_tool session|rejoin` asks Dart to report on logcat (tag
    // DearthTool); `--es dearth_hub URL --es dearth_enroll CODE` lets an
    // unpaired app claim an enrollment code by itself. Kept until Dart takes
    // them (takeTool), so a cold start doesn't lose them.
    private fun takeToolExtras(intent: Intent): Boolean {
        val command = intent.getStringExtra(TOOL_COMMAND)
        val hub = intent.getStringExtra(TOOL_HUB)
        val code = intent.getStringExtra(TOOL_ENROLL)
        if (command == null && (hub == null || code == null)) return false
        toolPrefs().edit().apply {
            if (command != null) putString(TOOL_COMMAND, command)
            if (hub != null && code != null) {
                putString(TOOL_HUB, hub)
                putString(TOOL_ENROLL, code)
            }
        }.apply()
        return true
    }

    // FreeKiosk's REST key, handed over by tool/deploy_frame.sh with
    // `am start -n app.dearth/.MainActivity --es freekiosk_api_key … --ei
    // freekiosk_port …` (SPEC §13.9). Dart reads it with getFreeKiosk.
    private fun takeKioskKey(intent: Intent) {
        val key = intent.getStringExtra(FREEKIOSK_KEY) ?: return
        kioskPrefs().edit()
            .putString(FREEKIOSK_KEY, key)
            .putInt(FREEKIOSK_PORT, intent.getIntExtra(FREEKIOSK_PORT, 8080))
            .apply()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Updater.register(this, flutterEngine)
        // The ambient light sensor, in lux, while Dart listens (SPEC FR-DSP-02).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "app.dearth/light").setStreamHandler(object : EventChannel.StreamHandler {
            private var listener: SensorEventListener? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val sensors = getSystemService(SENSOR_SERVICE) as SensorManager
                val light = sensors.getDefaultSensor(Sensor.TYPE_LIGHT) ?: return events.endOfStream()
                listener = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) = events.success(event.values[0].toDouble())
                    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
                }.also { sensors.registerListener(it, light, SensorManager.SENSOR_DELAY_NORMAL) }
            }

            override fun onCancel(arguments: Any?) {
                listener?.let { (getSystemService(SENSOR_SERVICE) as SensorManager).unregisterListener(it) }
                listener = null
            }
        })
        tool = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.dearth/tool").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // The pending command and enrollment, cleared as Dart takes them.
                    "takeTool" -> {
                        val p = toolPrefs()
                        val taken = mapOf("command" to p.getString(TOOL_COMMAND, null), "hub" to p.getString(TOOL_HUB, null), "code" to p.getString(TOOL_ENROLL, null))
                        p.edit().clear().apply()
                        result.success(taken)
                    }
                    "report" -> {
                        Log.i("DearthTool", call.arguments as? String ?: "")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.dearth/display").setMethodCallHandler { call, result ->
            when (call.method) {
                "setOrientation" -> {
                    val mode = call.arguments as? String
                    prefs().edit().putString(ORIENTATION, mode).apply()
                    applyOrientation(mode)
                    result.success(null)
                }
                // The media volume Dearth plays at (chimes, timers, the
                // Toybox): a wall frame's own buttons are out of reach.
                "getVolume" -> {
                    val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                    result.success(listOf(audio.getStreamVolume(AudioManager.STREAM_MUSIC), audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)))
                }
                // Total RAM (MB) and the low-RAM flag: the perf tier (SPEC
                // §6.2) that decides frame budgets and animation caps.
                "getMemory" -> {
                    val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                    val info = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(info)
                    result.success(listOf((info.totalMem / (1024 * 1024)).toInt(), if (am.isLowRamDevice) 1 else 0))
                }
                "setVolume" -> {
                    val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    try {
                        audio.setStreamVolume(AudioManager.STREAM_MUSIC, ((call.arguments as? Int) ?: 0).coerceIn(0, max), 0)
                        result.success(null)
                    } catch (e: SecurityException) {
                        // Do Not Disturb can refuse a change.
                        result.error("volume", e.message, null)
                    }
                }
                "hasLightSensor" -> result.success((getSystemService(SENSOR_SERVICE) as SensorManager).getDefaultSensor(Sensor.TYPE_LIGHT) != null)
                // This window's brightness, 0…1, or null to follow the
                // system's (FR-DSP-02). It holds while Dearth is in front.
                "setBrightness" -> {
                    val level = (call.arguments as? Number)?.toFloat()
                    window.attributes = window.attributes.apply {
                        screenBrightness = level?.coerceIn(0f, 1f) ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    }
                    result.success(null)
                }
                // Turns a sleeping screen back on (the morning after "screen
                // off at night", a timer ringing in the dark). FreeKiosk's
                // screen/on does it too; this works without the bridge. The
                // window's keep-screen-on flag holds it on afterwards.
                "wakeScreen" -> {
                    val power = getSystemService(POWER_SERVICE) as PowerManager
                    @Suppress("DEPRECATION")
                    power.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "dearth:wake").acquire(5000)
                    result.success(power.isInteractive)
                }
                "isScreenOn" -> result.success((getSystemService(POWER_SERVICE) as PowerManager).isInteractive)
                "getFreeKiosk" -> {
                    val key = kioskPrefs().getString(FREEKIOSK_KEY, null)
                    result.success(if (key == null) null else mapOf("key" to key, "port" to kioskPrefs().getInt(FREEKIOSK_PORT, 8080)))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun prefs() = getSharedPreferences("dearth_display", MODE_PRIVATE)

    private fun kioskPrefs() = getSharedPreferences("dearth_kiosk", MODE_PRIVATE)

    private fun toolPrefs() = getSharedPreferences("dearth_tool", MODE_PRIVATE)

    private var tool: MethodChannel? = null

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

    companion object {
        /** Whether Dearth is the activity in front (KioskWatch checks it after a boot). */
        @Volatile
        var inFront = false

        private const val ORIENTATION = "orientation"
        private const val FREEKIOSK_KEY = "freekiosk_api_key"
        private const val FREEKIOSK_PORT = "freekiosk_port"
        private const val TOOL_COMMAND = "dearth_tool"
        private const val TOOL_HUB = "dearth_hub"
        private const val TOOL_ENROLL = "dearth_enroll"
    }
}
