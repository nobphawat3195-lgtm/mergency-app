/// โมเดลของโหมดตรวจรถมือสองนอกสถานที่
///
/// แบบฟอร์มตรวจ (checklist) มาจาก backend (`GET /inspections/checklist`) เสมอ
/// แอปไม่ hardcode รายการตรวจ เพื่อให้เพิ่ม/แก้ข้อได้โดยไม่ต้องออกเวอร์ชันแอปใหม่
library;

enum InspectionItemStatus { pass, attention, fail, notApplicable }

InspectionItemStatus? inspectionItemStatusFromJson(String? value) {
  switch (value) {
    case 'PASS':
      return InspectionItemStatus.pass;
    case 'ATTENTION':
      return InspectionItemStatus.attention;
    case 'FAIL':
      return InspectionItemStatus.fail;
    case 'NOT_APPLICABLE':
      return InspectionItemStatus.notApplicable;
    default:
      return null;
  }
}

String inspectionItemStatusToJson(InspectionItemStatus status) {
  switch (status) {
    case InspectionItemStatus.pass:
      return 'PASS';
    case InspectionItemStatus.attention:
      return 'ATTENTION';
    case InspectionItemStatus.fail:
      return 'FAIL';
    case InspectionItemStatus.notApplicable:
      return 'NOT_APPLICABLE';
  }
}

String inspectionItemStatusLabel(InspectionItemStatus status) {
  switch (status) {
    case InspectionItemStatus.pass:
      return 'ผ่าน';
    case InspectionItemStatus.attention:
      return 'ควรระวัง';
    case InspectionItemStatus.fail:
      return 'ไม่ผ่าน';
    case InspectionItemStatus.notApplicable:
      return 'ไม่มี/ไม่เกี่ยว';
  }
}

enum InspectionVerdict { recommended, caution, notRecommended }

InspectionVerdict? inspectionVerdictFromJson(String? value) {
  switch (value) {
    case 'RECOMMENDED':
      return InspectionVerdict.recommended;
    case 'CAUTION':
      return InspectionVerdict.caution;
    case 'NOT_RECOMMENDED':
      return InspectionVerdict.notRecommended;
    default:
      return null;
  }
}

String inspectionVerdictLabel(InspectionVerdict verdict) {
  switch (verdict) {
    case InspectionVerdict.recommended:
      return 'แนะนำให้ซื้อ';
    case InspectionVerdict.caution:
      return 'ซื้อได้ แต่ควรต่อรอง/ซ่อมบางจุด';
    case InspectionVerdict.notRecommended:
      return 'ไม่แนะนำให้ซื้อ';
  }
}

class MeasurementRule {
  const MeasurementRule({
    required this.unit,
    this.passMin,
    this.attentionMin,
    this.passMax,
    this.attentionMax,
  });

  final String unit;
  final double? passMin;
  final double? attentionMin;
  final double? passMax;
  final double? attentionMax;

  factory MeasurementRule.fromJson(Map<String, dynamic> json) {
    double? read(String key) => (json[key] as num?)?.toDouble();
    return MeasurementRule(
      unit: json['unit'] as String,
      passMin: read('passMin'),
      attentionMin: read('attentionMin'),
      passMax: read('passMax'),
      attentionMax: read('attentionMax'),
    );
  }

  /// เกณฑ์เดียวกับ backend (src/inspections/grading.ts) ใช้แสดงผลทันทีตอนช่างพิมพ์ค่า
  InspectionItemStatus statusFor(double value) {
    if (passMax != null) {
      if (value <= passMax!) return InspectionItemStatus.pass;
      if (attentionMax != null && value <= attentionMax!) {
        return InspectionItemStatus.attention;
      }
      return InspectionItemStatus.fail;
    }
    if (passMin != null) {
      if (value >= passMin!) return InspectionItemStatus.pass;
      if (attentionMin != null && value >= attentionMin!) {
        return InspectionItemStatus.attention;
      }
      return InspectionItemStatus.fail;
    }
    return InspectionItemStatus.pass;
  }
}

class ChecklistItem {
  const ChecklistItem({
    required this.code,
    required this.label,
    this.hint,
    this.critical = false,
    this.flags = const [],
    this.appliesTo = 'all',
    this.measurement,
    this.photoOnIssue = false,
  });

  final String code;
  final String label;
  final String? hint;
  final bool critical;
  final List<String> flags;
  final String appliesTo;
  final MeasurementRule? measurement;
  final bool photoOnIssue;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    final measurement = json['measurement'] as Map<String, dynamic>?;
    return ChecklistItem(
      code: json['code'] as String,
      label: json['label'] as String,
      hint: json['hint'] as String?,
      critical: json['critical'] as bool? ?? false,
      flags: (json['flags'] as List<dynamic>? ?? const []).cast<String>(),
      appliesTo: json['appliesTo'] as String? ?? 'all',
      measurement:
          measurement == null ? null : MeasurementRule.fromJson(measurement),
      photoOnIssue: json['photoOnIssue'] as bool? ?? false,
    );
  }

  /// ข้อนี้ต้องตรวจกับรถคันนี้หรือไม่ (ตรงกับ isApplicable ใน backend)
  bool appliesToVehicle({String? powertrain, String? transmission}) {
    switch (appliesTo) {
      case 'combustion':
        return powertrain != 'electrified';
      case 'electrified':
        return powertrain == 'electrified' || powertrain == 'hybrid';
      case 'manual':
        return transmission == 'manual';
      case 'automatic':
        return transmission != 'manual';
      default:
        return true;
    }
  }
}

class ChecklistSection {
  const ChecklistSection({
    required this.code,
    required this.title,
    required this.description,
    required this.items,
  });

  final String code;
  final String title;
  final String description;
  final List<ChecklistItem> items;

  factory ChecklistSection.fromJson(Map<String, dynamic> json) {
    return ChecklistSection(
      code: json['code'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      items: (json['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(ChecklistItem.fromJson)
          .toList(),
    );
  }
}

/// ช่องภาพหลักฐานตามหัวข้อ เช่น "ประตูหน้าซ้าย" (ต้นทาง backend/src/inspections/photo-slots.ts)
class PhotoSlot {
  const PhotoSlot({
    required this.code,
    required this.group,
    required this.label,
    required this.required,
    required this.maxPhotos,
    this.hint,
    this.captionRequired = false,
  });

  final String code;
  final String group;
  final String label;
  final String? hint;
  final bool required;
  final int maxPhotos;

  /// ทุกรูปต้องมีคำอธิบาย (ใช้กับช่องรูปตำหนิ)
  final bool captionRequired;

  factory PhotoSlot.fromJson(Map<String, dynamic> json) {
    return PhotoSlot(
      code: json['code'] as String,
      group: json['group'] as String,
      label: json['label'] as String,
      hint: json['hint'] as String?,
      required: json['required'] as bool? ?? false,
      maxPhotos: json['maxPhotos'] as int? ?? 3,
      captionRequired: json['captionRequired'] as bool? ?? false,
    );
  }
}

class InspectionPhoto {
  const InspectionPhoto({
    required this.slotCode,
    required this.url,
    this.caption,
  });

  final String slotCode;
  final String url;
  final String? caption;

  InspectionPhoto copyWith({String? caption}) =>
      InspectionPhoto(slotCode: slotCode, url: url, caption: caption);

  factory InspectionPhoto.fromJson(Map<String, dynamic> json) {
    return InspectionPhoto(
      slotCode: json['slotCode'] as String,
      url: json['url'] as String,
      caption: json['caption'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        if (caption != null && caption!.trim().isNotEmpty)
          'caption': caption!.trim(),
      };
}

class InspectionChecklist {
  const InspectionChecklist({
    required this.version,
    required this.sections,
    this.photoSlots = const [],
  });

  final int version;
  final List<ChecklistSection> sections;
  final List<PhotoSlot> photoSlots;

  factory InspectionChecklist.fromJson(Map<String, dynamic> json) {
    return InspectionChecklist(
      version: json['version'] as int,
      sections: (json['sections'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(ChecklistSection.fromJson)
          .toList(),
      photoSlots: (json['photoSlots'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(PhotoSlot.fromJson)
          .toList(),
    );
  }

  PhotoSlot? photoSlot(String code) {
    for (final slot in photoSlots) {
      if (slot.code == code) return slot;
    }
    return null;
  }

  /// หัวข้อกลุ่มรูปตามลำดับที่ backend กำหนด
  List<String> get photoGroups {
    final groups = <String>[];
    for (final slot in photoSlots) {
      if (!groups.contains(slot.group)) groups.add(slot.group);
    }
    return groups;
  }

  ChecklistItem? item(String code) {
    for (final section in sections) {
      for (final item in section.items) {
        if (item.code == code) return item;
      }
    }
    return null;
  }

  int get totalItems =>
      sections.fold(0, (sum, section) => sum + section.items.length);
}

class InspectionItemResult {
  const InspectionItemResult({
    required this.itemCode,
    this.status,
    this.measurement,
    this.note,
    this.photoUrls = const [],
  });

  final String itemCode;
  final InspectionItemStatus? status;
  final double? measurement;
  final String? note;
  final List<String> photoUrls;

  factory InspectionItemResult.fromJson(Map<String, dynamic> json) {
    return InspectionItemResult(
      itemCode: json['itemCode'] as String,
      status: inspectionItemStatusFromJson(json['status'] as String?),
      measurement: (json['measurement'] as num?)?.toDouble(),
      note: json['note'] as String?,
      photoUrls:
          (json['photoUrls'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'itemCode': itemCode,
        'status': status == null ? null : inspectionItemStatusToJson(status!),
        'measurement': measurement,
        'note': note,
        'photoUrls': photoUrls,
      };

  /// ผลที่ใช้แสดง: ถ้าไม่ได้เลือกผลแต่มีค่าวัด ให้คำนวณจากเกณฑ์
  InspectionItemStatus? effectiveStatus(ChecklistItem? definition) {
    if (status != null) return status;
    final rule = definition?.measurement;
    if (rule != null && measurement != null) {
      return rule.statusFor(measurement!);
    }
    return null;
  }

  InspectionItemResult copyWith({
    InspectionItemStatus? status,
    bool clearStatus = false,
    double? measurement,
    bool clearMeasurement = false,
    String? note,
    List<String>? photoUrls,
  }) {
    return InspectionItemResult(
      itemCode: itemCode,
      status: clearStatus ? null : (status ?? this.status),
      measurement: clearMeasurement ? null : (measurement ?? this.measurement),
      note: note ?? this.note,
      photoUrls: photoUrls ?? this.photoUrls,
    );
  }
}

class InspectionReport {
  const InspectionReport({
    required this.orderId,
    required this.checklistVersion,
    this.listingUrl,
    this.sellerName,
    this.sellerPhone,
    this.appointmentAt,
    this.brand,
    this.model,
    this.year,
    this.color,
    this.plateNo,
    this.plateProvince,
    this.vin,
    this.engineNo,
    this.mileageKm,
    this.powertrain,
    this.transmission,
    this.score,
    this.grade,
    this.verdict,
    this.floodSuspected = false,
    this.accidentSuspected = false,
    this.odometerSuspected = false,
    this.legalIssue = false,
    this.summary,
    this.submittedAt,
    this.items = const [],
    this.photos = const [],
  });

  final String orderId;
  final int checklistVersion;
  final String? listingUrl;
  final String? sellerName;
  final String? sellerPhone;
  final DateTime? appointmentAt;
  final String? brand;
  final String? model;
  final int? year;
  final String? color;
  final String? plateNo;
  final String? plateProvince;
  final String? vin;
  final String? engineNo;
  final int? mileageKm;
  final String? powertrain;
  final String? transmission;
  final int? score;
  final String? grade;
  final InspectionVerdict? verdict;
  final bool floodSuspected;
  final bool accidentSuspected;
  final bool odometerSuspected;
  final bool legalIssue;
  final String? summary;
  final DateTime? submittedAt;
  final List<InspectionItemResult> items;

  /// ภาพหลักฐานแยกช่อง ลูกค้าเห็นหลังช่างส่งรายงานแล้วเท่านั้น
  final List<InspectionPhoto> photos;

  List<InspectionPhoto> photosFor(String slotCode) =>
      photos.where((photo) => photo.slotCode == slotCode).toList();

  bool get isSubmitted => submittedAt != null;

  String get vehicleTitle {
    final parts = [brand, model, year?.toString()]
        .whereType<String>()
        .where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'รถที่นัดตรวจ' : parts.join(' ');
  }

  factory InspectionReport.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value).toLocal();
    }

    return InspectionReport(
      orderId: json['orderId'] as String,
      checklistVersion: json['checklistVersion'] as int,
      listingUrl: json['listingUrl'] as String?,
      sellerName: json['sellerName'] as String?,
      sellerPhone: json['sellerPhone'] as String?,
      appointmentAt: date('appointmentAt'),
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      year: json['year'] as int?,
      color: json['color'] as String?,
      plateNo: json['plateNo'] as String?,
      plateProvince: json['plateProvince'] as String?,
      vin: json['vin'] as String?,
      engineNo: json['engineNo'] as String?,
      mileageKm: json['mileageKm'] as int?,
      powertrain: json['powertrain'] as String?,
      transmission: json['transmission'] as String?,
      score: json['score'] as int?,
      grade: json['grade'] as String?,
      verdict: inspectionVerdictFromJson(json['verdict'] as String?),
      floodSuspected: json['floodSuspected'] as bool? ?? false,
      accidentSuspected: json['accidentSuspected'] as bool? ?? false,
      odometerSuspected: json['odometerSuspected'] as bool? ?? false,
      legalIssue: json['legalIssue'] as bool? ?? false,
      summary: json['summary'] as String?,
      submittedAt: date('submittedAt'),
      items: (json['items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(InspectionItemResult.fromJson)
          .toList(),
      photos: (json['photos'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(InspectionPhoto.fromJson)
          .toList(),
    );
  }
}

/// ข้อมูลนัดตรวจที่ลูกค้ากรอกตอนจอง
class InspectionBooking {
  const InspectionBooking({
    this.brand,
    this.model,
    this.year,
    this.listingUrl,
    this.sellerName,
    this.sellerPhone,
    this.appointmentAt,
  });

  final String? brand;
  final String? model;
  final int? year;
  final String? listingUrl;
  final String? sellerName;
  final String? sellerPhone;
  final DateTime? appointmentAt;

  Map<String, dynamic> toJson() {
    String? clean(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    return {
      if (clean(brand) != null) 'brand': clean(brand),
      if (clean(model) != null) 'model': clean(model),
      if (year != null) 'year': year,
      if (clean(listingUrl) != null) 'listingUrl': clean(listingUrl),
      if (clean(sellerName) != null) 'sellerName': clean(sellerName),
      if (clean(sellerPhone) != null) 'sellerPhone': clean(sellerPhone),
      if (appointmentAt != null)
        'appointmentAt': appointmentAt!.toUtc().toIso8601String(),
    };
  }
}

/// กลุ่มสำหรับอธิบายบริการตรวจรถให้ลูกค้าอ่านง่าย (หน้า "รายละเอียดบริการตรวจรถ")
///
/// รายการข้อตรวจมาจาก checklist ของ backend เสมอ ที่นี่แค่จัดกลุ่มใหม่เพื่อการแสดงผล
/// แต่ละข้ออยู่ได้กลุ่มเดียว จำนวนข้อที่แสดงจึงรวมกันได้เท่ากับ checklist จริง
class InspectionDisplayGroup {
  const InspectionDisplayGroup({
    required this.key,
    required this.title,
    required this.description,
    required this.items,
  });

  final String key;
  final String title;
  final String description;
  final List<ChecklistItem> items;

  int get criticalCount => items.where((item) => item.critical).length;
}

/// ข้อที่เกี่ยวกับความปลอดภัยโดยตรง ดึงออกจากหมวดเดิมมารวมไว้กลุ่มเดียว
const _safetyItemCodes = {
  'SUS07',
  'SUS08',
  'SUS09',
  'SUS10',
  'FRM12',
  'OBD04',
  'OBD05',
  'INT13',
};

const _displayGroupDefs = [
  (
    key: 'documents',
    title: 'เอกสารและเลขตัวรถ',
    description: 'เทียบเล่มทะเบียนกับเลขตัวถัง เลขเครื่อง ภาษี และภาระไฟแนนซ์',
  ),
  (
    key: 'body',
    title: 'ตัวถังและสี',
    description: 'วัดความหนาสีทีละชิ้น หาร่องรอยทำสี โป๊ว หรือเปลี่ยนชิ้นส่วน',
  ),
  (
    key: 'structure',
    title: 'เสา A/B/C และโครงสร้าง',
    description: 'ตรวจเสา คานหน้า-หลัง ซุ้มล้อ พื้นรถ และร่องรอยน้ำท่วม',
  ),
  (
    key: 'engine',
    title: 'เครื่องยนต์และเกียร์',
    description: 'ห้องเครื่อง ของเหลว การรั่วซึม เกียร์ และระบบไฮบริด/EV ถ้ามี',
  ),
  (
    key: 'obd',
    title: 'OBD สแกนคอมพิวเตอร์',
    description: 'อ่านโค้ดปัญหาในกล่อง ECU และเทียบเลขไมล์ในระบบ',
  ),
  (
    key: 'safety',
    title: 'ระบบความปลอดภัยและเบรก',
    description: 'ผ้าเบรก จานเบรก เบรกมือ ถุงลมนิรภัย ABS/ESP และเข็มขัดนิรภัย',
  ),
  (
    key: 'suspension',
    title: 'ช่วงล่างและยาง',
    description: 'โช้คอัพ ลูกหมาก บูช พวงมาลัย ดอกยาง ปีผลิตยาง และล้อ',
  ),
  (
    key: 'electrical',
    title: 'ระบบไฟและแอร์',
    description:
        'ความเย็นแอร์ ไฟทุกดวง กระจก ล็อก เครื่องเสียง และอุปกรณ์ในห้องโดยสาร',
  ),
  (
    key: 'drive',
    title: 'ทดลองขับ',
    description: 'ออกตัว เปลี่ยนเกียร์ เบรก พวงมาลัย และเสียงผิดปกติขณะขับจริง',
  ),
];

String _displayGroupKey(String itemCode) {
  if (_safetyItemCodes.contains(itemCode)) return 'safety';
  final prefix = itemCode.replaceAll(RegExp(r'\d+$'), '');
  switch (prefix) {
    case 'DOC':
      return 'documents';
    case 'PNT':
      return 'body';
    case 'FRM':
    case 'FLD':
      return 'structure';
    case 'ENG':
    case 'EV':
      return 'engine';
    case 'OBD':
      return 'obd';
    case 'SUS':
    case 'TIR':
      return 'suspension';
    case 'DRV':
      return 'drive';
    default:
      return 'electrical';
  }
}

extension InspectionChecklistDisplay on InspectionChecklist {
  /// จัดกลุ่มตามหัวข้อที่ลูกค้าเข้าใจง่าย ตัดกลุ่มว่างออก
  List<InspectionDisplayGroup> get displayGroups {
    final buckets = <String, List<ChecklistItem>>{};
    for (final section in sections) {
      for (final item in section.items) {
        buckets.putIfAbsent(_displayGroupKey(item.code), () => []).add(item);
      }
    }
    return [
      for (final def in _displayGroupDefs)
        if (buckets[def.key]?.isNotEmpty ?? false)
          InspectionDisplayGroup(
            key: def.key,
            title: def.title,
            description: def.description,
            items: buckets[def.key]!,
          ),
    ];
  }

  int get photoRequiredItems => sections.fold(
        0,
        (sum, section) =>
            sum + section.items.where((item) => item.photoOnIssue).length,
      );
}
