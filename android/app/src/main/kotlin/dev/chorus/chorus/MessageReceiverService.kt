package dev.chorus.chorus

import android.app.*
import android.content.*
import android.os.*
import android.hardware.*
import org.json.JSONArray
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.TimeZone
import java.security.MessageDigest
import java.security.cert.X509Certificate
import javax.net.ssl.*

/** Native worker: survives Flutter UI suspension. User-visible foreground notification. */
class MessageReceiverService : Service(), SensorEventListener {
    private lateinit var worker: HandlerThread
    private lateinit var handler: Handler
    private var stopping = false
    private val settings by lazy { getSharedPreferences("message_receiver", MODE_PRIVATE) }
    private val sensors by lazy { getSystemService(SENSOR_SERVICE) as SensorManager }
    private var latestMotion: FloatArray? = null
    private var latestMotionAt = 0L
    private val notices by lazy { getSystemService(NOTIFICATION_SERVICE) as NotificationManager }
    private val poll = object : Runnable {
        override fun run() {
            if (stopping) return
            try { receiveMessages() } catch (_: Exception) { }
            sampleMotion()
            if (!stopping) handler.postDelayed(this, 300_000L)
        }
    }
    private val screen = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            handler.removeCallbacks(poll)
            handler.post(poll)
        }
    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 26) {
            notices.createNotificationChannel(NotificationChannel("chorus_messages", "Chorus messages", NotificationManager.IMPORTANCE_HIGH))
            notices.createNotificationChannel(NotificationChannel("chorus_receiver", "Chorus message receiver", NotificationManager.IMPORTANCE_LOW))
        }
        startForeground(7390, notificationBuilder("chorus_receiver")
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle("Chorus")
            .setContentText("Receiving assistant messages").setContentIntent(openChat(7390))
            .setOngoing(true).build())
        worker = HandlerThread("chorus-message-poll")
        worker.start(); handler = Handler(worker.looper)
        val filter = IntentFilter().apply { addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_USER_PRESENT) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(screen, filter, RECEIVER_NOT_EXPORTED) else registerReceiver(screen, filter)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handler.removeCallbacks(poll); handler.post(poll)
        return START_STICKY
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        stopping = true; unregisterReceiver(screen)
        sensors.unregisterListener(this)
        handler.removeCallbacksAndMessages(null); worker.quitSafely()
        super.onDestroy()
    }
    private fun notificationBuilder(channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)

    private fun openChat(id: Int): PendingIntent = PendingIntent.getActivity(this, id,
        Intent(this, MainActivity::class.java).putExtra("chorus_message", true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun sampleMotion() {
        val sensor = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        latestMotion = null
        sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL, handler)
        handler.postDelayed({ sensors.unregisterListener(this) }, 2_000L)
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER && event.values.size >= 3) {
            latestMotion = floatArrayOf(event.values[0], event.values[1], event.values[2])
            latestMotionAt = System.currentTimeMillis()
            sensors.unregisterListener(this)
            try { sendMotion() } catch (_: Exception) { }
        }
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun configureTls(connection: java.net.HttpURLConnection) {
        // The configured server uses a self-signed leaf. Trust only this SSH-verified pin.
        // Other servers keep normal platform TLS validation.
        if (connection is HttpsURLConnection && connection.url.host == "47.109.58.185") {
            val trust = object : X509TrustManager {
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
                override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) { throw java.security.cert.CertificateException("client trust unsupported") }
                override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                    if (chain.isEmpty() || digest(chain[0].encoded) != SERVER_PIN) throw java.security.cert.CertificateException("server pin mismatch")
                    chain[0].checkValidity()
                }
            }
            val ssl = SSLContext.getInstance("TLS"); ssl.init(null, arrayOf(trust), null)
            connection.sslSocketFactory = ssl.socketFactory
            connection.hostnameVerifier = HostnameVerifier { hostName, session ->
                hostName == "47.109.58.185" && digest(session.peerCertificates[0].encoded) == SERVER_PIN
            }
        }
    }

    private fun sendMotion() {
        val values = latestMotion ?: return
        val at = latestMotionAt
        if (at <= 0L) return
        val host = settings.getString("host", "") ?: ""
        val token = settings.getString("token", "") ?: ""
        if (host.isBlank() || token.isBlank()) return
        val connection = URL(host.trimEnd('/') + "/api/signal").openConnection() as java.net.HttpURLConnection
        connection.connectTimeout = 15_000; connection.readTimeout = 15_000; connection.requestMethod = "POST"
        configureTls(connection)
        connection.doOutput = true; connection.setRequestProperty("Authorization", "Bearer $token"); connection.setRequestProperty("Content-Type", "application/json")
        val id = "motion-native:$at"
        val body = "{\"observed_at\":\"${SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(at))}\",\"kind\":\"motion\",\"source\":\"phone_native\",\"event_id\":\"$id\",\"data\":{\"x\":${values[0]},\"y\":${values[1]},\"z\":${values[2]},\"magnitude\":${Math.sqrt((values[0]*values[0]+values[1]*values[1]+values[2]*values[2]).toDouble())},\"sampling_period_sec\":300}}"
        connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
        connection.inputStream.close(); connection.disconnect()
    }

    private fun receiveMessages() {
        val host = settings.getString("host", "") ?: ""
        val token = settings.getString("token", "") ?: ""
        if (host.isBlank() || token.isBlank()) return
        val account = digest((host + "\n" + token).toByteArray())
        val cursorKey = "cursor:$account"
        val connection = URL(host.trimEnd('/') + "/api/messages?limit=80").openConnection() as java.net.HttpURLConnection
        connection.connectTimeout = 15_000; connection.readTimeout = 15_000
        connection.setRequestProperty("Authorization", "Bearer $token")
        configureTls(connection)
        try {
            if (connection.responseCode != 200) return
            val rows = JSONArray(connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() })
            val ordered = (0 until rows.length()).map { rows.getJSONObject(it) }.sortedBy { it.getLong("id") }
            val latest = ordered.lastOrNull()?.getLong("id") ?: return
            if (!settings.contains(cursorKey)) {
                // Baseline first connection without notifying historical messages.
                settings.edit().putLong(cursorKey, latest).commit(); return
            }
            var cursor = settings.getLong(cursorKey, 0)
            for (message in ordered) {
                val id = message.getLong("id")
                if (id <= cursor) continue
                if (message.optString("origin") == "task" && message.optString("kind", "chat") == "chat") {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) return
                    if (!notices.areNotificationsEnabled()) return
                    if (Build.VERSION.SDK_INT >= 26 && notices.getNotificationChannel("chorus_messages")?.importance == NotificationManager.IMPORTANCE_NONE) return
                    val content = message.optString("content")
                    val notificationId = (id % 2_000_000_000L).toInt() + 10_000
                    notices.notify(notificationId, notificationBuilder("chorus_messages")
                        .setSmallIcon(R.mipmap.ic_launcher).setContentTitle(message.optString("speaker", "Chorus"))
                        .setContentText(content).setStyle(Notification.BigTextStyle().bigText(content))
                        .setContentIntent(openChat(notificationId)).setAutoCancel(true).build())
                }
                if (!settings.edit().putLong(cursorKey, id).commit()) return
                cursor = id
            }
        } finally { connection.disconnect() }
    }
    companion object {
        private const val SERVER_PIN = "d29f5d39228657f8fa9984d017471cc4675e2ae857492a4fe9c676858ec01250"
        private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        fun configure(context: Context, host: String, token: String) {
            context.getSharedPreferences("message_receiver", MODE_PRIVATE).edit().putString("host", host).putString("token", token).commit()
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(Intent(context, MessageReceiverService::class.java))
            else context.startService(Intent(context, MessageReceiverService::class.java))
        }
    }
}
