package dev.chorus.chorus

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.os.PowerManager
import android.app.KeyguardManager
import java.security.MessageDigest
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// 无障碍服务：只订阅前台窗口切换，不读取屏幕内容。
/// 锁屏和解锁在这里动态注册广播接收器：服务在后台常驻，
/// 比 Activity 更能在锁屏时收到广播。
class ChorusAccessibilityService : android.accessibilityservice.AccessibilityService() {
    private var screenReceiver: BroadcastReceiver? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action ?: return
                val event = when (action) {
                    Intent.ACTION_USER_PRESENT -> mapOf("kind" to "unlock")
                    Intent.ACTION_SCREEN_ON -> mapOf("kind" to "screen", "state" to "on")
                    Intent.ACTION_SCREEN_OFF -> mapOf("kind" to "screen", "state" to "off")
                    else -> return
                }
                sink?.success(event)
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        screenReceiver = receiver
    }

    override fun onDestroy() {
        screenReceiver?.let { unregisterReceiver(it) }
        screenReceiver = null
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val name = event.packageName?.toString() ?: return
        if (name == this.packageName) return
        val label = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(name, 0)).toString()
        } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
            name
        }
        sink?.success(mapOf("kind" to "app", "name" to name, "label" to label))
    }

    override fun onInterrupt() {}

    companion object {
        var instance: ChorusAccessibilityService? = null
        var sink: EventChannel.EventSink? = null
    }
}

class MainActivity : FlutterActivity() {
    override fun onStart() {
        super.onStart()
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return
        EventChannel(messenger, "dev.chorus.chorus/access")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ChorusAccessibilityService.sink = events
                }

                override fun onCancel(arguments: Any?) {
                    ChorusAccessibilityService.sink = null
                }
            })
        MethodChannel(messenger, "dev.chorus.chorus/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "accessibilityEnabled" -> result.success(accessibilityEnabled())
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "openAppSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.fromParts("package", packageName, null)
                    })
                    result.success(null)
                }
                "locationGranted" -> result.success(
                    checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) ==
                        android.content.pm.PackageManager.PERMISSION_GRANTED
                )
                "notificationGranted" -> result.success(
                    if (Build.VERSION.SDK_INT >= 33)
                        checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                    else true
                )
                "usageGranted" -> result.success(usageGranted())
                "foregroundEvents" -> result.success(foregroundEvents(call.argument<Long>("sinceMs") ?: (System.currentTimeMillis() - 30_000L)))
                "openUsageSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// 使用情况访问权限，用来读应用使用时长。
    private fun usageGranted(): Boolean {
        val appOps = getSystemService(APP_OPS_SERVICE) as android.app.AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            appOps.unsafeCheckOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName
            )
        }
        return mode == android.app.AppOpsManager.MODE_ALLOWED
    }

    /** Reads a small overlapping window. UsageStats is the primary source; no screen content is read. */
    private fun foregroundEvents(sinceMs: Long): List<Map<String, Any>> {
        if (!usageGranted()) return emptyList()
        val power = getSystemService(POWER_SERVICE) as PowerManager
        val keyguard = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        if (!power.isInteractive || keyguard.isKeyguardLocked) return emptyList()
        val now = System.currentTimeMillis()
        val begin = (sinceMs - 5_000L).coerceAtLeast(now - 15 * 60_000L)
        val manager = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(begin, now)
        val event = UsageEvents.Event()
        val result = mutableListOf<Map<String, Any>>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val resumed = if (Build.VERSION.SDK_INT >= 29) {
                event.eventType == UsageEvents.Event.ACTIVITY_RESUMED
            } else {
                @Suppress("DEPRECATION")
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            }
            if (!resumed || event.packageName.isNullOrBlank() || event.packageName == packageName) continue
            val packageName = event.packageName
            val label = try {
                getPackageManager().getApplicationLabel(
                    getPackageManager().getApplicationInfo(packageName, 0)
                ).toString()
            } catch (_: Exception) { packageName }
            val observed = event.timeStamp
            val eventId = sha256("usage:$packageName:${event.className ?: ""}:$observed")
            result.add(mapOf(
                "kind" to "app", "name" to packageName, "label" to label,
                "observedAtMs" to observed, "eventId" to eventId, "source" to "usage_stats"
            ))
        }
        return result.sortedBy { (it["observedAtMs"] as Long) }
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray()).joinToString("") { "%02x".format(it) }

    /// 无障碍权限只能由用户在系统设置里手动开，这里只判断开没开。
    private fun accessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(":").any {
            it.equals("$packageName/.ChorusAccessibilityService", ignoreCase = true) ||
                it.equals("$packageName/$packageName.ChorusAccessibilityService", ignoreCase = true)
        }
    }
}
