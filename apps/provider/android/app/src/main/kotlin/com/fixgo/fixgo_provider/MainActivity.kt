package com.fixgo.fixgo_provider

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        showOverLockScreenFor(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        showOverLockScreenFor(intent)
    }

    /** ออกจากหน้าแอปแล้ว: กลับไปต้องปลดล็อกเครื่องตามปกติ */
    override fun onStop() {
        super.onStop()
        setOverLockScreen(false)
    }

    /**
     * แสดงทับจอล็อกและเปิดจอ เฉพาะตอนระบบเปิดแอปจากแจ้งเตือนงานใหม่แบบเต็มจอ
     * (ไม่ตั้งใน manifest: ไม่อย่างนั้นใครก็ใช้แอปบนเครื่องที่ล็อกอยู่ได้)
     */
    private fun showOverLockScreenFor(intent: Intent?) {
        setOverLockScreen(intent?.action == NOTIFICATION_LAUNCH_ACTION)
    }

    private fun setOverLockScreen(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(enabled)
        }
    }

    companion object {
        /** action ที่ flutter_local_notifications ใส่ให้ intent เมื่อเปิดแอปจากแจ้งเตือน */
        private const val NOTIFICATION_LAUNCH_ACTION = "SELECT_NOTIFICATION"
    }

    /**
     * ช่องแจ้งเตือนความสำคัญสูง (เด้งบนจอพร้อมเสียง) ชื่อต้องตรงกับ
     * default_notification_channel_id ใน AndroidManifest ที่ FCM ใช้
     * (ช่อง fixgo_offer_alarm ของงานใหม่สร้างจากฝั่ง Dart พร้อมเสียงปลุก)
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "fixgo_updates",
            "งานใหม่และสถานะงาน",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "แจ้งงานใหม่ใกล้คุณ การยืนยันราคา และการชำระเงิน"
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    /** หน้า "ตั้งค่าเสียงเตือนงาน": ตรวจสิทธิ์เต็มจอ/แบตเตอรี่ และเปิดหน้าตั้งค่าของระบบ */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fixgo/alarm_settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "isIgnoringBatteryOptimizations" -> result.success(
                        getSystemService(PowerManager::class.java)
                            .isIgnoringBatteryOptimizations(packageName),
                    )
                    "openFullScreenIntentSettings" -> result.success(
                        if (Build.VERSION.SDK_INT >= 34) {
                            open(
                                Intent(
                                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                        } else {
                            openNotificationSettings()
                        },
                    )
                    "openBatteryOptimizationSettings" -> result.success(
                        open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)),
                    )
                    "openNotificationSettings" -> result.success(openNotificationSettings())
                    "openAppSettings" -> result.success(openAppDetails())
                    else -> result.notImplemented()
                }
            }
    }

    /** Android 14+: ระบบอาจปิดสิทธิ์เต็มจอ ต้องให้ช่างเปิดเอง ต่ำกว่านั้นได้อัตโนมัติ */
    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        return getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
    }

    private fun openNotificationSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return openAppDetails()
        return open(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
        )
    }

    private fun openAppDetails(): Boolean = open(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
    )

    /** บางยี่ห้อไม่มีหน้านั้น: ตกไปที่หน้าข้อมูลแอปแทน */
    private fun open(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (error: Exception) {
        if (intent.action == Settings.ACTION_APPLICATION_DETAILS_SETTINGS) {
            false
        } else {
            openAppDetails()
        }
    }
}
