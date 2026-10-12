# Proactive message delivery (v0.3.13)

After opening the configured Android app, a native foreground service polls /api/messages every 30 seconds. It is independent of Flutter UI timers and location permission. Screen-on/unlock triggers an immediate poll. First successful connection sets a baseline, without alerting historical messages. Subsequent task-origin chat messages produce Android notifications; each processed message ID is persisted per server/account. Disconnects and denied notifications leave pending messages for later retry. Notification ID reuse prevents duplicate entries if cursor saving fails. Tap opens the chat. Chat refreshes every 10 seconds while visible and when returning to foreground, without sending a human message.

Enable notification permission and allow background operation in phone system settings. Android force-stop, battery restrictions and Doze may suspend or delay polling. This is native polling, not FCM; a 30-second interval is a target while scheduled, not a delivery SLA. No boot autostart is installed. Open the app once after upgrading.

The deployed self-signed server certificate is pinned to its SSH-verified SHA256; certificate renewal requires updating the pin. Other servers retain default platform TLS validation. Credentials remain app-private and are never logged.

Verified: Flutter analysis, widget tests for silent refresh/offline recovery, release compilation. No Android device is attached; notification display, lockscreen timing, tapping and restart behavior still require device verification. Existing server wake/task creation and Xiaomi preflight were verified separately; no user message is fabricated for a test.
