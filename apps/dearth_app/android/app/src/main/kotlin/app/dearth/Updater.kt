package app.dearth

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * App updates with Android's installer (SPEC §15.3), for devices that can't
 * install silently through their own ADB (Dart's LocalAdb): Android shows
 * its "install this update?" screen and the person confirms.
 *
 * `app.dearth/update`: `info` → {abi} (the ABI of the installed APK, which
 * picks the release asset); `install(path)` → "started", or "permission"
 * when Android first needs "install unknown apps" allowed for Dearth (its
 * settings screen opens).
 */
object Updater {
    fun register(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.dearth/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(mapOf("abi" to installedAbi(activity)))
                "install" -> {
                    val path = call.arguments as? String ?: return@setMethodCallHandler result.error("install", "no APK", null)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                        return@setMethodCallHandler result.success("permission")
                    }
                    // Writing ~50 MB into the session takes a moment: off the UI thread.
                    Thread {
                        try {
                            install(activity, File(path))
                            activity.runOnUiThread { result.success("started") }
                        } catch (e: Exception) {
                            Log.w(TAG, "install failed", e)
                            activity.runOnUiThread { result.error("install", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    /** The ABI this APK was built for, from where Android put its native libraries. */
    private fun installedAbi(context: Context): String? = when (File(context.applicationInfo.nativeLibraryDir).name) {
        "arm" -> "armeabi-v7a"
        "arm64" -> "arm64-v8a"
        "x86_64" -> "x86_64"
        else -> Build.SUPPORTED_ABIS.firstOrNull { it in setOf("armeabi-v7a", "arm64-v8a", "x86_64") }
    }

    private fun install(context: Context, apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("dearth.apk", 0, apk.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val status = PendingIntent.getBroadcast(context, id, Intent(context, UpdateStatus::class.java), flags)
            session.commit(status.intentSender)
        }
    }

    const val TAG = "DearthUpdate"
}

/** The installer's answers: its confirm screen to show, or how it ended. */
class UpdateStatus : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            PackageInstaller.STATUS_SUCCESS -> Log.i(Updater.TAG, "installed")
            else -> Log.w(Updater.TAG, "install ended ($status): ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)}")
        }
    }
}
