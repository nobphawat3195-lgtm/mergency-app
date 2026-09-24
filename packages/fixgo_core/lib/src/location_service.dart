import 'dart:ui' show Locale;

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocationResult {
  const LocationResult({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final double latitude;
  final double longitude;

  /// ที่อยู่แบบอ่านง่าย ได้จาก reverse geocoding — เป็น null ได้ถ้าแปลงไม่สำเร็จ
  /// (เช่น ไม่มีเน็ต) ไม่ควรทำให้ทั้ง flow ล้มเหลวเพราะจุดนี้อย่างเดียว
  final String? address;
}

/// ขอตำแหน่ง GPS ปัจจุบันของเครื่อง ใช้ร่วมกันทั้งแอปลูกค้าและแอปช่าง
class LocationService {
  /// ขอสิทธิ์ + อ่านพิกัดปัจจุบัน แล้วพยายามแปลงเป็นที่อยู่ (ไม่บังคับสำเร็จ)
  ///
  /// โยน [LocationException] ที่มีข้อความภาษาไทยพร้อมอธิบายให้ผู้ใช้เห็นตรงๆ
  /// ถ้า service ปิดอยู่หรือผู้ใช้ปฏิเสธสิทธิ์
  static Future<LocationResult> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        'กรุณาเปิดบริการตำแหน่ง (Location Services) ในเครื่องก่อนใช้งาน',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException('คุณไม่ได้อนุญาตให้เข้าถึงตำแหน่ง');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'สิทธิ์เข้าถึงตำแหน่งถูกปฏิเสธถาวร กรุณาเปิดในตั้งค่าเครื่อง',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    String? address;
    try {
      // สร้างในนี้: แพลตฟอร์มที่ไม่มี geocoder (เช่น เว็บ) จะ throw ตั้งแต่ตอนสร้าง
      final placemarks = await Geocoding(locale: const Locale('th', 'TH'))
          .placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        address = _formatPlacemark(placemarks.first);
      }
    } catch (_) {
      // reverse geocoding ล้มเหลวได้ (เช่น ไม่มีเน็ต) ไม่ต้องทำให้ทั้งฟังก์ชันพัง
      // แค่ไม่มีชื่อที่อยู่ให้แสดง ยังใช้พิกัดได้ปกติ
    }

    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
    );
  }

  static String _formatPlacemark(Placemark placemark) {
    final parts = [
      placemark.street,
      placemark.subLocality,
      placemark.locality,
    ].where((part) => part != null && part.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'ตำแหน่งปัจจุบัน' : parts.join(' ');
  }

  /// สตรีมพิกัดต่อเนื่อง ใช้ตอนช่างออนไลน์เพื่ออัปเดตตำแหน่งเป็นระยะ
  static Stream<Position> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // อัปเดตเมื่อขยับเกิน 50 เมตร กันยิง API ถี่เกินไป
      ),
    );
  }
}
