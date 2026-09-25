// โมเดลข้อมูลที่ตรงกับ response ของ backend

import 'inspection.dart';

class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.slug,
    required this.name,
    required this.iconKey,
  });

  final String id;
  final String slug;
  final String name;
  final String iconKey;

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      iconKey: json['iconKey'] as String,
    );
  }
}

enum PriceType { callOutFee, fullService }

PriceType _priceTypeFromJson(String value) =>
    value == 'CALL_OUT_FEE' ? PriceType.callOutFee : PriceType.fullService;

class SubService {
  const SubService({
    required this.id,
    required this.name,
    required this.basePrice,
    required this.priceType,
    this.description,
    this.infoNote,
  });

  final String id;
  final String name;

  /// หน่วยสตางค์
  final int basePrice;
  final PriceType priceType;
  final String? description;
  final String? infoNote;

  factory SubService.fromJson(Map<String, dynamic> json) {
    return SubService(
      id: json['id'] as String,
      name: json['name'] as String,
      basePrice: json['basePrice'] as int,
      priceType: _priceTypeFromJson(json['priceType'] as String),
      description: json['description'] as String?,
      infoNote: json['infoNote'] as String?,
    );
  }
}

class VehicleType {
  const VehicleType({
    required this.id,
    required this.slug,
    required this.name,
    required this.multiplier,
  });

  final String id;
  final String slug;
  final String name;
  final double multiplier;

  factory VehicleType.fromJson(Map<String, dynamic> json) {
    return VehicleType(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      multiplier: (json['multiplier'] as num).toDouble(),
    );
  }
}

enum OrderStatus {
  created,
  searching,
  matched,
  enRoute,
  inProgress,
  completed,
  cancelled,
  noMatch,
}

enum QuoteStatus { notRequested, pending, approved, rejected }

QuoteStatus quoteStatusFromJson(String? value) {
  switch (value) {
    case 'PENDING':
      return QuoteStatus.pending;
    case 'APPROVED':
      return QuoteStatus.approved;
    case 'REJECTED':
      return QuoteStatus.rejected;
    case 'NOT_REQUESTED':
    case null:
      return QuoteStatus.notRequested;
    default:
      throw ArgumentError('สถานะใบเสนอราคาไม่รู้จัก: $value');
  }
}

OrderStatus orderStatusFromJson(String value) {
  switch (value) {
    case 'CREATED':
      return OrderStatus.created;
    case 'SEARCHING':
      return OrderStatus.searching;
    case 'MATCHED':
      return OrderStatus.matched;
    case 'EN_ROUTE':
      return OrderStatus.enRoute;
    case 'IN_PROGRESS':
      return OrderStatus.inProgress;
    case 'COMPLETED':
      return OrderStatus.completed;
    case 'CANCELLED':
      return OrderStatus.cancelled;
    case 'NO_MATCH':
      return OrderStatus.noMatch;
    default:
      throw ArgumentError('สถานะออเดอร์ไม่รู้จัก: $value');
  }
}

String orderStatusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.created:
    case OrderStatus.searching:
      return 'กำลังหาช่าง';
    case OrderStatus.matched:
      return 'ช่างรับงานแล้ว';
    case OrderStatus.enRoute:
      return 'ช่างกำลังเดินทาง';
    case OrderStatus.inProgress:
      return 'กำลังดำเนินการ';
    case OrderStatus.completed:
      return 'เสร็จสิ้น';
    case OrderStatus.cancelled:
      return 'ยกเลิกแล้ว';
    case OrderStatus.noMatch:
      return 'ยังไม่มีช่างรับ';
  }
}

/// ป้ายสถานะชำระเงินที่ใช้ร่วมกันทั้งแอปลูกค้าและแอปช่าง ให้เห็นตรงกันเสมอ
/// "ชำระแล้ว" มาจาก backend (PAID) เท่านั้น การแสดง QR/กดปุ่มไม่เปลี่ยนสถานะนี้
String paymentStatusLabel(String? status) {
  switch (status) {
    case 'PAID':
      return 'ชำระแล้ว';
    case 'FAILED':
      return 'ชำระไม่สำเร็จ';
    case 'REFUNDED':
      return 'คืนเงินแล้ว';
    default:
      return 'รอยืนยันยอดเงิน';
  }
}

class ProviderSummary {
  const ProviderSummary({
    required this.id,
    required this.realName,
    required this.nickname,
    required this.phone,
    required this.ratingAvg,
    this.currentLat,
    this.currentLng,
  });

  final String id;
  final String realName;
  final String nickname;
  final String phone;
  final double ratingAvg;
  final double? currentLat;
  final double? currentLng;

  factory ProviderSummary.fromJson(Map<String, dynamic> json) {
    return ProviderSummary(
      id: json['id'] as String,
      realName: json['realName'] as String,
      nickname: json['nickname'] as String,
      phone: json['phone'] as String,
      ratingAvg: (json['ratingAvg'] as num).toDouble(),
      currentLat: (json['currentLat'] as num?)?.toDouble(),
      currentLng: (json['currentLng'] as num?)?.toDouble(),
    );
  }
}

class Order {
  const Order({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.priceEstimated,
    required this.pickupLat,
    required this.pickupLng,
    this.priceFinal,
    this.priceProposed,
    this.quoteStatus = QuoteStatus.notRequested,
    this.quoteNote,
    this.pickupAddress,
    this.note,
    this.categoryName,
    this.subServiceName,
    this.provider,
    this.photoUrls = const [],
    this.paymentStatus,
    this.paymentMethod,
    this.categorySlug,
    this.categoryIconKey,
    this.inspection,
    this.ratingScore,
    this.ratingComment,
    this.completedAt,
    this.cancelReason,
  });

  final String id;
  final String orderNo;
  final OrderStatus status;
  final int priceEstimated;
  final int? priceFinal;
  final int? priceProposed;
  final QuoteStatus quoteStatus;
  final String? quoteNote;
  final double pickupLat;
  final double pickupLng;
  final String? pickupAddress;
  final String? note;
  final String? categoryName;
  final String? subServiceName;
  final ProviderSummary? provider;
  final List<String> photoUrls;
  final String? paymentStatus;
  final String? paymentMethod;
  final String? categorySlug;
  final String? categoryIconKey;

  /// สรุปรายงานตรวจรถ (มีเฉพาะงานตรวจรถมือสอง)
  final InspectionReport? inspection;

  /// คะแนนที่ลูกค้าให้ไว้แล้ว (null = ยังไม่ให้คะแนน)
  final int? ratingScore;
  final String? ratingComment;

  /// เวลาปิดงานจาก backend ใช้สรุปงานเสร็จวันนี้ในแอปช่าง
  final DateTime? completedAt;

  /// เหตุผลเมื่อทีมงานเป็นผู้ยกเลิกงาน (ลูกค้ายกเลิกเองจะเป็น null)
  final String? cancelReason;

  bool get isInspection => categorySlug == 'used-car-inspection';

  /// ชำระสำเร็จเมื่อ backend ยืนยันแล้วเท่านั้น (webhook ผู้ให้บริการรับชำระ หรือช่างยืนยันรับเงินสด)
  bool get isPaid => paymentStatus == 'PAID';

  factory Order.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    final subService = json['subService'] as Map<String, dynamic>?;
    final provider = json['provider'] as Map<String, dynamic>?;
    final payment = json['payment'] as Map<String, dynamic>?;
    final rating = json['rating'] as Map<String, dynamic>?;
    final photos = (json['photos'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((photo) => photo['url'] as String)
        .toList();

    return Order(
      id: json['id'] as String,
      orderNo: json['orderNo'] as String,
      status: orderStatusFromJson(json['status'] as String),
      priceEstimated: json['priceEstimated'] as int,
      priceFinal: json['priceFinal'] as int?,
      priceProposed: json['priceProposed'] as int?,
      quoteStatus: quoteStatusFromJson(json['quoteStatus'] as String?),
      quoteNote: json['quoteNote'] as String?,
      pickupLat: (json['pickupLat'] as num).toDouble(),
      pickupLng: (json['pickupLng'] as num).toDouble(),
      pickupAddress: json['pickupAddress'] as String?,
      note: json['note'] as String?,
      categoryName: category?['name'] as String?,
      subServiceName: subService?['name'] as String?,
      provider: provider == null ? null : ProviderSummary.fromJson(provider),
      photoUrls: photos,
      paymentStatus: payment?['status'] as String?,
      paymentMethod: payment?['method'] as String?,
      categorySlug: category?['slug'] as String?,
      categoryIconKey: category?['iconKey'] as String?,
      inspection: json['inspection'] is Map<String, dynamic>
          ? InspectionReport.fromJson({
              'orderId': json['id'],
              'checklistVersion': 0,
              ...json['inspection'] as Map<String, dynamic>,
            })
          : null,
      ratingScore: rating?['score'] as int?,
      ratingComment: rating?['comment'] as String?,
      completedAt: json['completedAt'] is String
          ? DateTime.parse(json['completedAt'] as String).toLocal()
          : null,
      cancelReason: json['cancelReason'] as String?,
    );
  }
}

/// งานที่ถูกเสนอให้ช่าง พร้อมเวลานับถอยหลัง
class JobOffer {
  const JobOffer({
    required this.orderId,
    required this.orderNo,
    required this.distanceKm,
    required this.expiresAt,
    required this.priceEstimated,
    this.categoryName,
    this.subServiceName,
    this.pickupAddress,
    this.photoUrls = const [],
  });

  final String orderId;
  final String orderNo;
  final double distanceKm;
  final DateTime expiresAt;
  final int priceEstimated;
  final String? categoryName;
  final String? subServiceName;
  final String? pickupAddress;
  final List<String> photoUrls;

  factory JobOffer.fromJson(Map<String, dynamic> json) {
    final order = json['order'] as Map<String, dynamic>;
    final category = order['category'] as Map<String, dynamic>?;
    final subService = order['subService'] as Map<String, dynamic>?;
    final photos = (order['photos'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((photo) => photo['url'] as String)
        .toList();

    return JobOffer(
      orderId: order['id'] as String,
      orderNo: order['orderNo'] as String,
      distanceKm: (json['distanceKm'] as num).toDouble(),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      priceEstimated: order['priceEstimated'] as int,
      categoryName: category?['name'] as String?,
      subServiceName: subService?['name'] as String?,
      pickupAddress: order['pickupAddress'] as String?,
      photoUrls: photos,
    );
  }
}

class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.createdAt,
    this.memo,
  });

  final String id;
  final String type;

  /// หน่วยสตางค์ บวก = เงินเข้า ลบ = เงินออก
  final int amount;
  final DateTime createdAt;
  final String? memo;

  factory WalletEntry.fromJson(Map<String, dynamic> json) {
    return WalletEntry(
      id: json['id'] as String,
      type: json['type'] as String,
      amount: json['amount'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      memo: json['memo'] as String?,
    );
  }
}
