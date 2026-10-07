import 'dart:async';
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
  FixGoApiClient({
    required this.baseUrl,
    this.requestTimeout = const Duration(seconds: 25),
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  })  : _http = httpClient ?? http.Client(),
        _streamClientFactory = streamClientFactory ?? http.Client.new;

  final String baseUrl;
  final Duration requestTimeout;
  final http.Client _http;

  /// event stream ใช้ client แยกต่อ stream เพื่อปิด connection ได้ทันทีเมื่อเลิกฟัง
  final http.Client Function() _streamClientFactory;

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
    try {
      return await _sendOnce(method, path, body: body, query: query)
          .timeout(requestTimeout);
    } on TimeoutException {
      throw ApiException(408,
          'การเชื่อมต่อใช้เวลานาน กรุณาตรวจสถานะล่าสุดก่อนลองทำรายการใหม่');
    } on http.ClientException {
      throw ApiException(
          503, 'เชื่อมต่อไม่ได้ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่');
    }
  }

  Future<dynamic> _sendOnce(
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

  /// ฟังการเปลี่ยนแปลงของงานแบบ real-time (Server-Sent Events)
  ///
  /// ปล่อยค่าเป็นประเภทเหตุการณ์ เช่น MATCHED, EN_ROUTE, LOCATION ให้ผู้ฟังไปเรียก [getOrder] ใหม่
  /// stream จบหรือ error เมื่อการเชื่อมต่อหลุด ผู้ฟังต้องต่อใหม่เอง
  /// ใช้บนเว็บไม่ได้ (browser client ไม่ส่งข้อมูลทีละส่วน) ให้ดึงข้อมูลเป็นรอบแทน
  Stream<String> orderEvents(String orderId) {
    final client = _streamClientFactory();
    late final StreamController<String> controller;
    StreamSubscription<String>? lines;
    controller = StreamController<String>(
      onListen: () async {
        try {
          final request = http.Request(
            'GET',
            Uri.parse('$baseUrl/api/orders/$orderId/events'),
          )..headers.addAll({
              ..._headers,
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
            });
          final response = await client.send(request);
          if (response.statusCode != 200) {
            throw ApiException(
              response.statusCode,
              'เชื่อมต่อการติดตามงานไม่สำเร็จ (${response.statusCode})',
            );
          }
          var event = 'message';
          var data = StringBuffer();
          lines = response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
            (line) {
              if (line.isEmpty) {
                if (event == 'order' && data.isNotEmpty) {
                  final decoded = jsonDecode(data.toString());
                  final type = decoded is Map ? decoded['type'] : null;
                  if (type is String) controller.add(type);
                } else if (event == 'ping') {
                  controller.add('PING');
                }
                event = 'message';
                data = StringBuffer();
              } else if (line.startsWith('event:')) {
                event = line.substring(6).trim();
              } else if (line.startsWith('data:')) {
                data.write(line.substring(5).trim());
              }
            },
            onError: controller.addError,
            onDone: controller.close,
            cancelOnError: true,
          );
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      },
      onCancel: () async {
        await lines?.cancel();
        client.close();
      },
    );
    return controller.stream;
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

  /// เซิร์ฟเวอร์เปิดให้เข้าสู่ระบบด้วย LINE หรือยัง (ต้องตั้ง Channel ID/secret และที่อยู่เว็บของแอปนั้น)
  Future<bool> isLineLoginEnabled({ApiRole role = ApiRole.customer}) async {
    final result = await _send(
      'GET',
      '/auth/line/config${_lineAppQuery(role)}',
    ) as Map<String, dynamic>;
    return result['enabled'] as bool? ?? false;
  }

  /// หน้าเริ่มล็อกอิน LINE: เปิดในแท็บเดิม LINE จะพากลับมาที่เว็บพร้อม ?line_ticket=
  Uri get lineLoginStartUri => lineLoginStartUriFor(ApiRole.customer);

  Uri lineLoginStartUriFor(ApiRole role) =>
      Uri.parse('$baseUrl/api/auth/line/start${_lineAppQuery(role)}');

  /// แอปมือถือ: เปิดใน ASWebAuthenticationSession / Custom Tabs แล้ว backend พากลับ
  /// fixgo://auth/line หรือ fixgofixer://auth/line พร้อม ?line_ticket=
  Uri nativeLineLoginStartUriFor(ApiRole role) => Uri.parse(
        '$baseUrl/api/auth/line/start'
        '?app=${role == ApiRole.provider ? 'provider' : 'customer'}&client=native',
      );

  String _lineAppQuery(ApiRole role) =>
      role == ApiRole.provider ? '?app=provider' : '';

  /// แลกตั๋วจาก LINE (ใช้ได้ครั้งเดียว ภายใน 60 วินาที) เป็น accessToken
  Future<String> exchangeLineTicket(String ticket) async =>
      (await exchangeLineTicketSession(ticket)).accessToken;

  /// เหมือน [exchangeLineTicket] แต่บอกด้วยว่าเคยสมัครแล้วหรือยัง (ช่างใหม่ต้องส่งใบสมัครก่อน)
  Future<({String accessToken, bool hasProfile})> exchangeLineTicketSession(
    String ticket,
  ) async {
    final result = await _send('POST', '/auth/line/exchange', body: {
      'ticket': ticket,
    }) as Map<String, dynamic>;
    final token = result['accessToken'] as String;
    accessToken = token;
    return (
      accessToken: token,
      hasProfile: result['hasProfile'] as bool? ?? true,
    );
  }

  /// ช่างที่ถือ pending token ของ LINE (ยังไม่สมัครตอนล็อกอิน) แต่ส่งใบสมัครไปแล้วจากเบราว์เซอร์อื่น:
  /// ขอโทเคนของบัญชีช่างตัวจริง ยังไม่สมัครได้ [ApiException] 404 ใช้ไม่ได้กับโทเคนนี้ได้ 403
  Future<({String accessToken, bool hasProfile})>
      refreshPendingLineSession() async {
    final result =
        await _send('POST', '/auth/line/refresh') as Map<String, dynamic>;
    final token = result['accessToken'] as String;
    accessToken = token;
    return (
      accessToken: token,
      hasProfile: result['hasProfile'] as bool? ?? true,
    );
  }

  /// ชื่อและเบอร์ของลูกค้าที่ล็อกอินอยู่ และเข้าด้วย LINE หรือไม่
  Future<({String? name, String? phone, bool viaLine})> getMyAccount() async {
    final result = await _send('GET', '/account') as Map<String, dynamic>;
    return (
      name: result['name'] as String?,
      phone: result['phone'] as String?,
      viaLine: result['viaLine'] as bool? ?? false,
    );
  }

  /// ลบบัญชีของผู้ที่ล็อกอินอยู่ (ลูกค้าหรือช่าง) กู้คืนไม่ได้
  Future<void> deleteAccount() async {
    await _send('DELETE', '/account');
  }

  /// ลงทะเบียนโทเคน push ของเครื่องนี้ให้ผู้ที่ล็อกอินอยู่ (platform: IOS / ANDROID)
  Future<void> registerDevice(String token, String platform) async {
    await _send('POST', '/devices', body: {
      'token': token,
      'platform': platform,
    });
  }

  /// ถอนโทเคน push ตอนล็อกเอาต์ ต้องเรียกก่อนล้าง accessToken
  Future<void> unregisterDevice(String token) async {
    await _send('DELETE', '/devices', body: {'token': token});
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

  /// ลิงก์ติดตามงานสำหรับครอบครัว (เปิดได้โดยไม่ต้องล็อกอิน) เรียกซ้ำได้ ได้ลิงก์เดิม
  /// [url] เป็น null เมื่อเซิร์ฟเวอร์ไม่ได้ตั้ง PUBLIC_WEB_URL ให้ต่อ [path] กับโดเมนเว็บเอง
  Future<({String path, String? url})> shareOrder(String orderId) async {
    final result =
        await _send('POST', '/orders/$orderId/share') as Map<String, dynamic>;
    return (path: result['path'] as String, url: result['url'] as String?);
  }

  Future<void> revokeOrderShare(String orderId) async {
    await _send('DELETE', '/orders/$orderId/share');
  }

  Future<void> rateOrder(String orderId, int score, {String? comment}) async {
    await _send('POST', '/orders/$orderId/rate', body: {
      'score': score,
      if (comment != null) 'comment': comment,
    });
  }

  // ---------- Chat ----------

  /// เปิดแชทของงาน: ข้อความทั้งหมด และส่งต่อได้ไหม (เรียกแล้วนับว่าอ่านแล้ว)
  Future<({bool canSend, List<ChatMessage> messages})> getOrderChat(
    String orderId,
  ) async {
    final result =
        await _send('GET', '/orders/$orderId/messages') as Map<String, dynamic>;
    return (
      canSend: result['canSend'] as bool? ?? false,
      messages: (result['messages'] as List<dynamic>? ?? const [])
          .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<ChatMessage> sendOrderMessage(
    String orderId, {
    String? text,
    String? imageUrl,
  }) async {
    final result = await _send('POST', '/orders/$orderId/messages', body: {
      if (text != null) 'text': text,
      if (imageUrl != null) 'imageUrl': imageUrl,
    }) as Map<String, dynamic>;
    return ChatMessage.fromJson(result);
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

  /// เวลารับงานของช่าง (นาทีนับจากเที่ยงคืน 0-1439) ระบบส่งงานให้เฉพาะในช่วงนี้
  Future<({int openMinute, int closeMinute})> updateProviderHours({
    required int openMinute,
    required int closeMinute,
  }) async {
    final result = await _send('PATCH', '/providers/me/hours', body: {
      'openMinute': openMinute,
      'closeMinute': closeMinute,
    }) as Map<String, dynamic>;
    return (
      openMinute: result['openMinute'] as int,
      closeMinute: result['closeMinute'] as int,
    );
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
    final http.Response response;
    try {
      response = await _http
          .put(
            Uri.parse(uploadUrl),
            headers: uploadHeaders,
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw ApiException(408, 'อัปโหลดใช้เวลานาน กรุณาลองแนบรูปใหม่');
    } on http.ClientException {
      throw ApiException(503, 'อัปโหลดไม่ได้ กรุณาตรวจอินเทอร์เน็ต');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่',
      );
    }
    return publicUrl;
  }

  /// การ์ดช่างที่ลูกค้าเห็น ค่า "" = ลบ, null = ไม่เปลี่ยน
  Future<void> updatePublicProfile({
    String? photoUrl,
    String? vehicleDesc,
    String? vehiclePlate,
  }) async {
    await _send('PATCH', '/providers/me/public-profile', body: {
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (vehicleDesc != null) 'vehicleDesc': vehicleDesc,
      if (vehiclePlate != null) 'vehiclePlate': vehiclePlate,
    });
  }

  /// บันทึกข้อมูลรับเงินทั้งชุด ช่องที่ว่างส่งเป็น null (ลบค่าเดิม) ไม่ส่งสตริงว่าง
  Future<void> updatePayoutInfo({
    String? bankName,
    String? bankAccountName,
    String? bankAccountNumber,
    String? promptPayId,
  }) async {
    String? orNull(String? value) {
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    await _send('PATCH', '/providers/me/payout-info', body: {
      'bankName': orNull(bankName),
      'bankAccountName': orNull(bankAccountName),
      'bankAccountNumber': orNull(bankAccountNumber),
      'promptPayId': orNull(promptPayId),
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

  Future<void> approveQuote(String orderId,
      {required int quoteVersion, required int priceProposed}) async {
    await _send('POST', '/orders/$orderId/quote/approve',
        body: {'quoteVersion': quoteVersion, 'priceProposed': priceProposed});
  }

  Future<void> rejectQuote(String orderId,
      {required int quoteVersion, required int priceProposed}) async {
    await _send('POST', '/orders/$orderId/quote/reject',
        body: {'quoteVersion': quoteVersion, 'priceProposed': priceProposed});
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

  /// ค่าบริการแพลตฟอร์มที่ช่างค้างจากงานเงินสด (สตางค์) และสถานะสลิปโอนคืน
  Future<WalletDebt> getWalletDebt() async {
    final result = await _send('GET', '/wallet/debt') as Map<String, dynamic>;
    return WalletDebt.fromJson(result);
  }

  /// QR พร้อมเพย์ของบริษัท ล็อกยอดเท่ากับค่าบริการที่ค้างทั้งหมด
  Future<
      ({
        int amount,
        String qrPayload,
        String? payeeName,
        String? promptPayId,
      })> getSettlementQr() async {
    final result =
        await _send('GET', '/wallet/settlement-qr') as Map<String, dynamic>;
    return (
      amount: result['amount'] as int,
      qrPayload: result['qrPayload'] as String,
      payeeName: result['payeeName'] as String?,
      promptPayId: result['promptPayId'] as String?,
    );
  }

  /// ส่งสลิปโอนค่าบริการค้าง (อัปโหลดรูปด้วย [uploadImage] scope PAYMENT_SLIP ก่อน)
  Future<void> submitSettlementSlip(String slipUrl) async {
    await _send('POST', '/wallet/settlements', body: {'slipUrl': slipUrl});
  }

  // ---------- Payments (ลูกค้า) ----------

  /// ขอ QR พร้อมเพย์ การได้ QR ไม่ใช่การชำระสำเร็จ ต้องรอ backend ยืนยันจาก gateway
  Future<
      ({
        String chargeId,
        String qrPayload,
        int amount,
        DateTime? expiresAt,
        bool requiresSlip,
        String? payeeName,
        String? promptPayId,
      })> createPromptPayCharge(String orderId) async {
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
      requiresSlip: result['requiresSlip'] as bool? ?? false,
      payeeName: result['payeeName'] as String?,
      promptPayId: result['promptPayId'] as String?,
    );
  }

  /// ส่งสลิปโอนพร้อมเพย์ (อัปโหลดรูปด้วย [uploadImage] scope PAYMENT_SLIP ก่อน)
  /// งานยังไม่เป็น "ชำระแล้ว" จนกว่าทีมงานตรวจยอดเข้าบัญชีจริง
  Future<void> submitPaymentSlip(String orderId, String slipUrl) async {
    await _send('POST', '/payments/orders/$orderId/slip', body: {
      'slipUrl': slipUrl,
    });
  }

  Future<void> confirmCashPayment(String orderId) async {
    await _send('POST', '/payments/orders/$orderId/cash/confirm');
  }

  void dispose() => _http.close();
}
