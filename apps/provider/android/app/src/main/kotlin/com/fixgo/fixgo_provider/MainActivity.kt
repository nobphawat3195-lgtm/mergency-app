package com.fixgo.fixgo_provider

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /**
     * ช่องแจ้งเตือนความสำคัญสูง (เด้งบนจอพร้อมเสียง) ชื่อต้องตรงกับ
     * default_notification_channel_id ใน AndroidManifest ที่ FCM ใช้
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
}
