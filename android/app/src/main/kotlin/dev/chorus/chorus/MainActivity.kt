package dev.chorus.chorus

import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel

/// 无障碍服务：只订阅锁屏状态和前台窗口切换，不读取屏幕内容。
class ChorusAccessibilityService : android.accessibilityservice.AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val kind = when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> "app"
            else -> return
        }
        val name = event.packageName?.toString() ?: return
        if (name == this.packageName) return
        sink?.success(mapOf("kind" to kind, "name" to name))
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
        EventChannel(flutterEngine?.dartExecutor?.binaryMessenger, "dev.chorus.chorus/access")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ChorusAccessibilityService.sink = events
                }

                override fun onCancel(arguments: Any?) {
                    ChorusAccessibilityService.sink = null
                }
            })
    }
}
