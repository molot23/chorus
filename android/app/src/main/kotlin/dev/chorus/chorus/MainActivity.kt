package dev.chorus.chorus

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
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
        sink?.success(mapOf("kind" to "app", "name" to name))
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
                else -> result.notImplemented()
            }
        }
    }

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
