// Service worker ของเว็บแอปช่าง (FixGo Fixer)
//
// รับ Web Push: เด้งเตือนงานใหม่แม้ปิดหน้าเว็บ/ล็อกจอ (แอปที่ติดตั้งลงหน้าจอหลัก)
// ใช้แทน flutter_service_worker.js เดิม และไม่ cache ไฟล์เลย ช่างจึงได้เวอร์ชันล่าสุดทุกครั้งที่เปิด
'use strict';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // ล้าง cache ที่ service worker เดิมของ Flutter เก็บไว้
    for (const key of await caches.keys()) {
      if (key.startsWith('flutter-')) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  const offer = data.type === 'OFFER';
  event.waitUntil(self.registration.showNotification(data.title || 'FixGo Fixer', {
    body: data.body || '',
    // งานเดียวกันแทนที่ข้อความเดิม แต่ยังสั่น/ดังอีกครั้ง (renotify)
    tag: data.orderId || data.type || 'fixgo',
    renotify: true,
    // งานใหม่ค้างบนจอจนกว่าช่างจะแตะ ไม่หายเองหลังไม่กี่วินาที
    requireInteraction: offer,
    vibrate: offer ? [800, 300, 800, 300, 800, 300, 800, 300, 800] : [200, 100, 200],
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    data: { url: '/', type: data.type || '', orderId: data.orderId || '' },
  }));
});

// แตะแจ้งเตือน: กลับไปหน้าที่เปิดอยู่ หรือเปิดหน้าหลัก (รายการงานใหม่)
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if ('focus' in client) return client.focus();
    }
    return self.clients.openWindow(url);
  })());
});
