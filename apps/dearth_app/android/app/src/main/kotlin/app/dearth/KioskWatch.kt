package app.dearth

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log

/**
 * Brings a frame's kiosk back if it sticks at boot.
 *
 * Frames have no clock battery: they boot at 1970 and the network sets the
 * clock a little later. FreeKiosk (v2.0.0-beta.4 and .5) times its boot
 * screen with the wall clock, so when that jump lands while the screen is up
 * its safety timeout fires at once and, inside lock task, loops on
 * "Starting kiosk…" for good, skipping the check that would hand over to
 * its main screen. Bringing FreeKiosk's main screen forward ends it (it
 * relaunches Dearth).
 *
 * After every boot, on frames set up with FreeKiosk (deploy_frame.sh handed
 * over its key), an alarm on the uptime clock (which never jumps) checks
 * whether Dearth made it to the front, and if not asks for FreeKiosk's main
 * screen, a few times. Starting an activity from the background needs
 * "display over other apps", which deploy_frame.sh grants.
 */
class KioskWatch : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val attempt = intent.getIntExtra(ATTEMPT, 0)
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> if (isKioskFrame(context)) schedule(context, 1)
            CHECK -> {
                if (MainActivity.inFront) return
                Log.w(TAG, "Dearth isn't in front ${attempt * DELAY_MS / 1000} s after boot: asking FreeKiosk for its main screen")
                try {
                    context.startActivity(Intent().setClassName(FREEKIOSK, "$FREEKIOSK.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (e: ActivityNotFoundException) {
                    return
                } catch (e: SecurityException) {
                    Log.w(TAG, "Not allowed to start FreeKiosk from the background: ${e.message}")
                }
                if (attempt < ATTEMPTS) schedule(context, attempt + 1)
            }
        }
    }

    private fun isKioskFrame(context: Context) =
        context.getSharedPreferences("dearth_kiosk", Context.MODE_PRIVATE).getString("freekiosk_api_key", null) != null

    private fun schedule(context: Context, attempt: Int) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val check = Intent(context, KioskWatch::class.java).setAction(CHECK).putExtra(ATTEMPT, attempt)
        val pending = PendingIntent.getBroadcast(context, attempt, check, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarms.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + DELAY_MS, pending)
    }

    private companion object {
        const val TAG = "DearthKioskWatch"
        const val CHECK = "app.dearth.KIOSK_CHECK"
        const val ATTEMPT = "attempt"
        const val FREEKIOSK = "com.freekiosk"

        // FreeKiosk hands over well inside its own two-minute limit on a
        // good boot.
        const val DELAY_MS = 120_000L
        const val ATTEMPTS = 3
    }
}
