import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'inspection.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// ผู้ใช้ที่เรียก API — ส่งไปกับการขอ OTP เพื่อบอกว่าเป็นลูกค้าหรือช่าง
enum ApiRole { customer, provider }

String _roleToJson(ApiRole role) =>
    role == ApiRole.customer ? 'CUSTOMER' : 'PROVIDER';

class FixGoApiClient {
  FixGoApiClient({required this.baseUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  String? accessToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl/api$path').replace(queryParameters: query);
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode >= 400) {
      String message = 'เกิดข้อผิดพลาด (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['message'] != null) {
          final raw = decoded['message'];
          message = raw is List ? raw.join('\n') : raw.toString();
        }
      } on FormatException {
        // ไม่ใช่ JSON ใช้ข้อความ default
      }
      throw ApiException(response.statusCode, message);
    }

    if (response.body.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  // ---------- Auth ----------

  Future<String?> requestOtp(String phone, ApiRole role) async {
    final result = await _send('POST', '/auth/otp/request', body: {
      'phone': phone,
      'role': _roleToJson(role),
    }) as Map<String, dynamic>;
    // devCode มีเฉพาะตอน backend รันโหมด development
    return result['devCode'] as String?;
  }

  /// ลบบัญชีของผู้ที่ล็อกอินอยู่ (ลูกค้าหรือช่าง) กู้คืนไม่ได้
  Future<void> deleteAccount() async {
    await _send('DELETE', '/account');
  }

  /// หน้าเว็บนโยบาย/ข้อตกลง/การลบบัญชี/ติดต่อ ที่ backend ให้บริการแบบสาธารณะ
  Uri legalPageUrl(String page) => Uri.parse('$baseUrl/api/legal/$page');

  Future<({String accessToken, bool hasProfile})> verifyOtp(
    String phone,
    ApiRole role,
    String code,
  ) async {
    final result = await _send('POST', '/auth/otp/verify', body: {
      'phone': phone,
      'role': _roleToJson(role),
      'code': code,
    }) as Map<String, dynamic>;

    final token = result['accessToken'] as String;
    accessToken = token;
    return (
      accessToken: token,
      hasProfile: result['hasProfile'] as bool,
    );
  }

  // ---------- Catalog ----------

  Future<List<ServiceCategory>> listCategories() async {
    final result = await _send('GET', '/catalog/categories') as List<dynamic>;
    return result
        .cast<Map<String, dynamic>>()
        .map(ServiceCategory.fromJson)
        .toList();
  }

  Future<List<SubService>> listSubServices(String categoryId) async {
    final result = await _send(
      'GET',
      '/catalog/categories/$categoryId/sub-services',
    ) as List<dynamic>;
    return result
        .cast<Map<String, dynamic>>()
        .map(SubService.fromJson)
        .toList();
  }

  Future<List<VehicleType>> listVehicleTypes() async {
    final result =
        await _send('GET', '/catalog/vehicle-types') as List<dynamic>;
    return result
        .cast<Map<String, dynamic>>()
        .map(VehicleType.fromJson)
        .toList();
  }

  Future<int> quote(String subServiceId, String vehicleTypeId) async {
    final result = await _send('GET', '/catalog/quote', query: {
      'subServiceId': subServiceId,
      'vehicleTypeId': vehicleTypeId,
    }) as Map<String, dynamic>;
    return result['price'] as int;
  }

  // ---------- Orders (ลูกค้า) ----------

  Future<Order> createOrder({
    required String categoryId,
    required String subServiceId,
    required String vehicleTypeId,
    required double pickupLat,
    required double pickupLng,
    String? pickupAddress,
    String? note,
    List<String>? photoUrls,
    InspectionBooking? inspection,
  }) async {
    final result = await _send('POST', '/orders', body: {
      'categoryId': categoryId,
      'subServiceId': subServiceId,
      'vehicleTypeId': vehicleTypeId,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      if (pickupAddress != null) 'pickupAddress': pickupAddress,
      if (note != null) 'note': note,
      if (photoUrls != null && photoUrls.isNotEmpty) 'photoUrls': photoUrls,
      if (inspection != null) 'inspection': inspection.toJson(),
    }) as Map<String, dynamic>;
    return Order.fromJson(result);
  }

  // ---------- ตรวจรถมือสอง ----------

  Future<InspectionChecklist> getInspectionChecklist() async {
    final result =
        await _send('GET', '/inspections/checklist') as Map<String, dynamic>;
    return InspectionChecklist.fromJson(result);
  }

  Future<InspectionReport> getInspection(String orderId) async {
    final result = await _send('GET', '/orders/$orderId/inspection')
        as Map<String, dynamic>;
    return InspectionReport.fromJson(result);
  }

  /// บันทึกข้อมูลรถและ/หรือผลตรวจบางข้อ (ส่งเฉพาะที่เปลี่ยน)
  Future<InspectionReport> updateInspection(
    String orderId, {
    Map<String, dynamic> vehicle = const {},
    List<InspectionItemResult> items = const [],
    Map<String, List<InspectionPhoto>> photoSlots = const {},
  }) async {
    final result = await _send('PATCH', '/orders/$orderId/inspection', body: {
      ...vehicle,
      if (items.isNotEmpty)
        'items': items.map((item) => item.toJson()).toList(),
      // ส่งรูปทั้งช่องแทนของเดิม (ลบรูป = ส่งรายการที่เหลือ)
      if (photoSlots.isNotEmpty)
        'photoSlots': [
          for (final entry in photoSlots.entries)
            {
              'slotCode': entry.key,
              'photos': entry.value.map((photo) => photo.toJson()).toList(),
            },
        ],
    }) as Map<String, dynamic>;
    return InspectionReport.fromJson(result);
  }

  Future<InspectionReport> submitInspection(String orderId) async {
    final result = await _send('POST', '/orders/$orderId/inspection/submit')
        as Map<String, dynamic>;
    return InspectionReport.fromJson(result);
  }

  Future<Order> getOrder(String orderId) async {
    final result =
        await _send('GET', '/orders/$orderId') as Map<String, dynamic>;
    return Order.fromJson(result);
  }

  Future<List<Order>> listMyOrders() async {
    final result = await _send('GET', '/orders/mine') as List<dynamic>;
    return result.cast<Map<String, dynamic>>().map(Order.fromJson).toList();
  }

  Future<void> cancelOrder(String orderId) async {
    await _send('POST', '/orders/$orderId/cancel');
  }

  Future<void> rateOrder(String orderId, int score, {String? comment}) async {
    await _send('POST', '/orders/$orderId/rate', body: {
      'score': score,
      if (comment != null) 'comment': comment,
    });
  }

  // ---------- Provider ----------

  Future<({String accessToken, bool hasProfile})> registerProvider(
    Map<String, dynamic> form,
  ) async {
    final result = await _send(
      'POST',
      '/providers/register',
      body: form,
    ) as Map<String, dynamic>;
    final token = result['accessToken'] as String;
    accessToken = token;
    return (
      accessToken: token,
      hasProfile: result['hasProfile'] as bool,
    );
  }

  Future<Map<String, dynamic>> getProviderProfile() async {
    return await _send('GET', '/providers/me') as Map<String, dynamic>;
  }

  Future<void> setOnline(bool isOnline) async {
    await _send('PATCH', '/providers/me/online', body: {'isOnline': isOnline});
  }

  Future<void> updateProviderLocation(double lat, double lng) async {
    await _send('PATCH', '/providers/me/location', body: {
      'lat': lat,
      'lng': lng,
    });
  }

  Future<void> sendProviderHeartbeat() async {
    await _send('POST', '/providers/me/heartbeat');
  }

  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String scope,
  }) async {
    final result = await _send('POST', '/uploads/presign', body: {
      'fileName': fileName,
      'contentType': contentType,
      'byteLength': bytes.length,
      'scope': scope,
    }) as Map<String, dynamic>;

    final uploadUrl = result['uploadUrl'] as String;
    final publicUrl = result['publicUrl'] as String;
    final uploadHeaders =
        (result['headers'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(key, value.toString()));
    final response = await _http.put(
      Uri.parse(uploadUrl),
      headers: uploadHeaders,
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่',
      );
    }
    return publicUrl;
  }

  Future<void> updatePayoutInfo({
    String? bankName,
    String? bankAccountName,
    String? bankAccountNumber,
    String? promptPayId,
  }) async {
    await _send('PATCH', '/providers/me/payout-info', body: {
      if (bankName != null) 'bankName': bankName,
      if (bankAccountName != null) 'bankAccountName': bankAccountName,
      if (bankAccountNumber != null) 'bankAccountNumber': bankAccountNumber,
      if (promptPayId != null) 'promptPayId': promptPayId,
    });
  }

  // ---------- Dispatch (ช่าง) ----------

  Future<List<JobOffer>> listOffers() async {
    final result = await _send('GET', '/dispatch/offers') as List<dynamic>;
    return result.cast<Map<String, dynamic>>().map(JobOffer.fromJson).toList();
  }

  Future<void> acceptOffer(String orderId) async {
    await _send('POST', '/dispatch/offers/$orderId/accept');
  }

  Future<void> rejectOffer(String orderId) async {
    await _send('POST', '/dispatch/offers/$orderId/reject');
  }

  Future<List<Order>> listAssignedOrders() async {
    final result = await _send('GET', '/orders/assigned') as List<dynamic>;
    return result.cast<Map<String, dynamic>>().map(Order.fromJson).toList();
  }

  Future<void> markEnRoute(String orderId) async {
    await _send('PATCH', '/orders/$orderId/en-route');
  }

  Future<void> startJob(String orderId) async {
    await _send('PATCH', '/orders/$orderId/start');
  }

  Future<void> proposeQuote(
    String orderId,
    int priceProposed, {
    String? note,
  }) async {
    await _send('POST', '/orders/$orderId/quote', body: {
      'priceProposed': priceProposed,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<void> approveQuote(String orderId) async {
    await _send('POST', '/orders/$orderId/quote/approve');
  }

  Future<void> rejectQuote(String orderId) async {
    await _send('POST', '/orders/$orderId/quote/reject');
  }

  Future<void> completeJob(String orderId) async {
    await _send('POST', '/orders/$orderId/complete');
  }

  // ---------- Wallet (ช่าง) ----------

  Future<int> getWalletBalance() async {
    final result =
        await _send('GET', '/wallet/balance') as Map<String, dynamic>;
    return result['balance'] as int;
  }

  Future<List<WalletEntry>> listWalletEntries() async {
    final result = await _send('GET', '/wallet/entries') as List<dynamic>;
    return result
        .cast<Map<String, dynamic>>()
        .map(WalletEntry.fromJson)
        .toList();
  }

  Future<void> requestWithdrawal(int amount) async {
    await _send('POST', '/wallet/withdrawals', body: {'amount': amount});
  }

  // ---------- Payments (ลูกค้า) ----------

  /// ขอ QR พร้อมเพย์ การได้ QR ไม่ใช่การชำระสำเร็จ ต้องรอ backend ยืนยันจาก gateway
  Future<({String chargeId, String qrPayload, int amount, DateTime? expiresAt})>
      createPromptPayCharge(String orderId) async {
    final result = await _send(
      'POST',
      '/payments/orders/$orderId/promptpay',
    ) as Map<String, dynamic>;
    final expires = result['expiresAt'] as String?;
    return (
      chargeId: result['chargeId'] as String,
      qrPayload: result['qrPayload'] as String,
      amount: result['amount'] as int,
      expiresAt: expires == null ? null : DateTime.parse(expires).toLocal(),
    );
  }

  Future<void> confirmCashPayment(String orderId) async {
    await _send('POST', '/payments/orders/$orderId/cash/confirm');
  }

  void dispose() => _http.close();
}
