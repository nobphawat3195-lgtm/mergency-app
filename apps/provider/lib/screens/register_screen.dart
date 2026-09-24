import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';

/// แบบฟอร์มลงทะเบียนช่าง — ฟิลด์ตรงกับฟอร์มคัดกรองช่างที่ใช้งานจริง
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _realNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _experienceController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _facebookController = TextEditingController();

  TimeOfDay _openTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 20, minute: 0);

  // null จนกว่าช่างจะกดปักหมุดจริง — ห้าม default เป็นพิกัดปลอม เพราะระบบ
  // dispatch ใช้พิกัดนี้คำนวณระยะทางส่งงาน ถ้าช่างลืมปักหมุดแล้วระบบส่งพิกัดผิด
  // ไปเงียบๆ งานจะถูกส่งไปหาช่างคนนี้ทั้งที่อยู่ไกลจริง
  double? _baseLat;
  double? _baseLng;
  bool _locatingPin = false;
  String? _pinError;

  final Set<String> _categoryIds = {};
  final Set<String> _vehicleTypeIds = {};
  final List<String> _toolPhotoUrls = [];
  bool _uploadingToolPhotos = false;

  Future<List<ServiceCategory>>? _categoriesFuture;
  Future<List<VehicleType>>? _vehicleTypesFuture;

  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ProviderAppScope.of(context).api;
    _categoriesFuture ??= api.listCategories();
    _vehicleTypesFuture ??= api.listVehicleTypes();
  }

  @override
  void dispose() {
    _realNameController.dispose();
    _nicknameController.dispose();
    _experienceController.dispose();
    _shopNameController.dispose();
    _facebookController.dispose();
    super.dispose();
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _contentTypeFor(XFile file) {
    final mimeType = file.mimeType;
    if (mimeType == 'image/png' ||
        mimeType == 'image/webp' ||
        mimeType == 'image/jpeg') {
      return mimeType!;
    }
    return file.name.toLowerCase().endsWith('.png')
        ? 'image/png'
        : file.name.toLowerCase().endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
  }

  Future<void> _pickToolPhotos() async {
    final remaining = 6 - _toolPhotoUrls.length;
    if (remaining <= 0) return;
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 82,
      maxWidth: 1920,
    );
    if (picked.isEmpty || !mounted) return;

    setState(() => _uploadingToolPhotos = true);
    try {
      final api = ProviderAppScope.of(context).api;
      for (final file in picked.take(remaining)) {
        final bytes = await file.readAsBytes();
        final url = await api.uploadImage(
          bytes: bytes,
          fileName: file.name,
          contentType: _contentTypeFor(file),
          scope: 'PROVIDER_TOOL',
        );
        if (!mounted) return;
        setState(() => _toolPhotoUrls.add(url));
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'อ่านหรืออัปโหลดรูปไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _uploadingToolPhotos = false);
    }
  }

  Future<void> _pinCurrentLocation() async {
    setState(() {
      _locatingPin = true;
      _pinError = null;
    });
    try {
      final result = await LocationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _baseLat = result.latitude;
        _baseLng = result.longitude;
      });
    } on LocationException catch (error) {
      if (!mounted) return;
      setState(() => _pinError = error.message);
    } finally {
      if (mounted) setState(() => _locatingPin = false);
    }
  }

  Future<void> _pickTime({required bool isOpen}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpen ? _openTime : _closeTime,
    );
    if (picked == null) return;
    setState(() {
      if (isOpen) {
        _openTime = picked;
      } else {
        _closeTime = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_categoryIds.isEmpty) {
      setState(() => _error = 'กรุณาเลือกงานบริการที่รับทำอย่างน้อย 1 รายการ');
      return;
    }
    if (_vehicleTypeIds.isEmpty) {
      setState(() => _error = 'กรุณาเลือกประเภทรถที่รับอย่างน้อย 1 รายการ');
      return;
    }
    if (_toolPhotoUrls.isEmpty) {
      setState(() => _error = 'กรุณาแนบรูปเครื่องมือช่างเพื่อยืนยันตัวตน');
      return;
    }
    final baseLat = _baseLat;
    final baseLng = _baseLng;
    if (baseLat == null || baseLng == null) {
      setState(() => _error = 'กรุณากดปักหมุดตำแหน่งร้าน/พื้นที่รับงานก่อน');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final appState = ProviderAppScope.of(context);
      final session = await appState.api.registerProvider({
        'realName': _realNameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'experienceYears': int.parse(_experienceController.text.trim()),
        if (_shopNameController.text.trim().isNotEmpty)
          'shopName': _shopNameController.text.trim(),
        if (_facebookController.text.trim().isNotEmpty)
          'facebookPage': _facebookController.text.trim(),
        'baseLat': baseLat,
        'baseLng': baseLng,
        'openMinute': _toMinutes(_openTime),
        'closeMinute': _toMinutes(_closeTime),
        'categoryIds': _categoryIds.toList(),
        'vehicleTypeIds': _vehicleTypeIds.toList(),
        'toolPhotoUrls': _toolPhotoUrls,
      });
      appState.signIn(
        session.accessToken,
        hasProfile: session.hasProfile,
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลงทะเบียนเป็นช่าง')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(FixGoSpacing.md),
          children: [
            Text(
              'กรอกข้อมูลเพื่อให้ทีมงานส่งงานได้ตรงตามประเภทของช่าง',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FixGoSpacing.lg),
            TextFormField(
              controller: _realNameController,
              decoration: const InputDecoration(labelText: 'ชื่อจริง-นามสกุล'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'กรุณากรอกชื่อจริง' : null,
            ),
            const SizedBox(height: FixGoSpacing.md),
            TextFormField(
              controller: _nicknameController,
              decoration: const InputDecoration(labelText: 'ชื่อเล่น'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'กรุณากรอกชื่อเล่น' : null,
            ),
            const SizedBox(height: FixGoSpacing.md),
            TextFormField(
              controller: _experienceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ประสบการณ์ด้านรถยนต์ (ปี)',
              ),
              validator: (value) {
                final years = int.tryParse((value ?? '').trim());
                if (years == null || years < 0 || years > 60) {
                  return 'กรุณากรอกจำนวนปี 0-60';
                }
                return null;
              },
            ),
            const SizedBox(height: FixGoSpacing.md),
            TextFormField(
              controller: _shopNameController,
              decoration: const InputDecoration(
                labelText: 'ชื่อร้าน / อู่ (ถ้ามี)',
              ),
            ),
            const SizedBox(height: FixGoSpacing.md),
            TextFormField(
              controller: _facebookController,
              decoration: const InputDecoration(
                labelText: 'ชื่อเพจ / เฟซบุ๊ก',
              ),
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('ตำแหน่งร้าน / พื้นที่รับงาน'),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.location_on_outlined,
                  color: _pinError != null ? FixGoColors.error : null,
                ),
                title: Text(
                  _baseLat != null && _baseLng != null
                      ? '${_baseLat!.toStringAsFixed(4)}, ${_baseLng!.toStringAsFixed(4)}'
                      : (_pinError ?? 'ยังไม่ได้ปักหมุด'),
                ),
                subtitle: const Text('ใช้คำนวณว่างานอยู่ใกล้คุณแค่ไหน'),
                trailing: TextButton(
                  onPressed: _locatingPin ? null : _pinCurrentLocation,
                  child: _locatingPin
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ปักหมุด'),
                ),
              ),
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('วันและเวลาเปิด-ปิด'),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'เปิด',
                    time: _openTime,
                    onTap: () => _pickTime(isOpen: true),
                  ),
                ),
                const SizedBox(width: FixGoSpacing.sm),
                Expanded(
                  child: _TimeField(
                    label: 'ปิด',
                    time: _closeTime,
                    onTap: () => _pickTime(isOpen: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('งานบริการที่รับทำ'),
            FutureBuilder<List<ServiceCategory>>(
              future: _categoriesFuture,
              builder: (context, snapshot) {
                final categories = snapshot.data ?? const <ServiceCategory>[];
                if (categories.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(FixGoSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Wrap(
                  spacing: FixGoSpacing.sm,
                  runSpacing: FixGoSpacing.sm,
                  children: [
                    for (final category in categories)
                      FilterChip(
                        label: Text(category.name),
                        selected: _categoryIds.contains(category.id),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _categoryIds.add(category.id);
                          } else {
                            _categoryIds.remove(category.id);
                          }
                        }),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('ประเภทรถที่รับ'),
            FutureBuilder<List<VehicleType>>(
              future: _vehicleTypesFuture,
              builder: (context, snapshot) {
                final vehicleTypes = snapshot.data ?? const <VehicleType>[];
                if (vehicleTypes.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(FixGoSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Wrap(
                  spacing: FixGoSpacing.sm,
                  runSpacing: FixGoSpacing.sm,
                  children: [
                    for (final vehicleType in vehicleTypes)
                      FilterChip(
                        label: Text(vehicleType.name),
                        selected: _vehicleTypeIds.contains(vehicleType.id),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _vehicleTypeIds.add(vehicleType.id);
                          } else {
                            _vehicleTypeIds.remove(vehicleType.id);
                          }
                        }),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('รูปเครื่องมือช่าง'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(FixGoSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.photo_camera_outlined),
                        const SizedBox(width: FixGoSpacing.sm),
                        Expanded(
                          child: Text(
                            _toolPhotoUrls.isEmpty
                                ? 'ยังไม่ได้แนบรูป'
                                : 'แนบแล้ว ${_toolPhotoUrls.length} รูป',
                          ),
                        ),
                        TextButton(
                          onPressed: _uploadingToolPhotos ||
                                  _toolPhotoUrls.length >= 6
                              ? null
                              : _pickToolPhotos,
                          child: Text(
                            _uploadingToolPhotos ? 'กำลังอัปโหลด' : 'เพิ่มรูป',
                          ),
                        ),
                      ],
                    ),
                    const Text('ใช้ยืนยันว่าเป็นช่างจริงและมีอุปกรณ์พร้อม'),
                    if (_toolPhotoUrls.isNotEmpty) ...[
                      const SizedBox(height: FixGoSpacing.sm),
                      Wrap(
                        spacing: FixGoSpacing.sm,
                        runSpacing: FixGoSpacing.sm,
                        children: [
                          for (final url in _toolPhotoUrls)
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    url,
                                    width: 82,
                                    height: 82,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: -7,
                                  top: -7,
                                  child: InkWell(
                                    onTap: () => setState(
                                      () => _toolPhotoUrls.remove(url),
                                    ),
                                    child: const CircleAvatar(
                                      radius: 11,
                                      backgroundColor: FixGoColors.error,
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: FixGoSpacing.md),
              Text(_error!, style: const TextStyle(color: FixGoColors.error)),
            ],
            const SizedBox(height: FixGoSpacing.lg),
            FixGoButton(
              label: 'ส่งใบสมัคร',
              loading: _submitting,
              onPressed: _submit,
            ),
            const SizedBox(height: FixGoSpacing.sm),
            Text(
              'ทีมงานจะตรวจสอบและอนุมัติภายใน 1-2 วันทำการ',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FixGoSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FixGoSpacing.sm),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
