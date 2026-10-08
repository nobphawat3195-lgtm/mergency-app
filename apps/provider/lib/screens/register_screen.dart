import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../working_hours.dart';

/// แบบฟอร์มลงทะเบียนช่าง — ฟิลด์ตรงกับฟอร์มคัดกรองช่างที่ใช้งานจริง
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.resubmit = false});

  /// ส่งใบสมัครใหม่หลังถูกปฏิเสธ: เปิดเป็นหน้าซ้อน ส่งเสร็จแล้วปิดกลับหน้าหลัก
  final bool resubmit;

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
  final _plateController = TextEditingController();
  final _vehicleDescController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _photoUrl;
  bool _uploadingPhoto = false;
  // กดส่งโดยยังไม่มีรูปหน้าตรง: ไฮไลต์วงกลมรูปโปรไฟล์และเลื่อนขึ้นไปให้เห็น
  bool _photoMissing = false;
  final _photoPickerKey = GlobalKey();

  // ค่าเริ่มต้นรับงานตลอดเวลา (งานฉุกเฉิน) ปรับทีหลังได้ทุกเมื่อจากหน้าหลัก
  int _openMinute = allDayOpenMinute;
  int _closeMinute = allDayCloseMinute;
  bool _customHours = false;

  // null จนกว่าช่างจะกดปักหมุดจริง — ห้าม default เป็นพิกัดปลอม เพราะระบบ
  // dispatch ใช้พิกัดนี้คำนวณระยะทางส่งงาน ถ้าช่างลืมปักหมุดแล้วระบบส่งพิกัดผิด
  // ไปเงียบๆ งานจะถูกส่งไปหาช่างคนนี้ทั้งที่อยู่ไกลจริง
  double? _baseLat;
  double? _baseLng;
  String? _pinAddress;
  double? _pinAccuracy;
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
    _plateController.dispose();
    _vehicleDescController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

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

  Future<void> _pickProfilePhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
    );
    if (file == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await ProviderAppScope.of(context).api.uploadImage(
            bytes: await file.readAsBytes(),
            fileName: file.name,
            contentType: _contentTypeFor(file),
            scope: 'PROVIDER_TOOL',
          );
      if (mounted) {
        setState(() {
          _photoUrl = url;
          _photoMissing = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } catch (_) {
      if (mounted) setState(() => _error = 'อ่านหรืออัปโหลดรูปไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
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
      setState(() => _error = userMessageFor(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'อ่านหรืออัปโหลดรูปไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _uploadingToolPhotos = false);
    }
  }

  Future<void> _pinOnMap() async {
    final current = _baseLat == null || _baseLng == null
        ? null
        : LocationResult(
            latitude: _baseLat!,
            longitude: _baseLng!,
            address: _pinAddress,
          );
    final picked = await pickLocationOnMap(
      context,
      initial: current,
      title: 'ปักหมุดร้าน / จุดรับงาน',
      userAgentPackageName: 'com.fixgo.fixgo_provider',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _baseLat = picked.latitude;
      _baseLng = picked.longitude;
      _pinAddress = picked.address;
      // ปักเองบนแผนที่ไม่มีค่าความคลาดเคลื่อนของ GPS
      _pinAccuracy = null;
      _pinError = null;
    });
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
        _pinAddress = result.address;
        _pinAccuracy = result.accuracyMeters;
      });
    } on LocationException catch (error) {
      if (!mounted) return;
      setState(() => _pinError = error.message);
    } finally {
      if (mounted) setState(() => _locatingPin = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_photoUrl == null) {
      setState(() {
        _photoMissing = true;
        _error =
            'กรุณาใส่รูปหน้าตรงที่วงกลมด้านบนสุด (รูปเครื่องมือใช้แทนไม่ได้)';
      });
      final pickerContext = _photoPickerKey.currentContext;
      if (pickerContext != null) {
        Scrollable.ensureVisible(
          pickerContext,
          duration: const Duration(milliseconds: 300),
        );
      }
      return;
    }
    if (_categoryIds.isEmpty) {
      setState(() => _error = 'กรุณาเลือกงานบริการที่รับทำอย่างน้อย 1 รายการ');
      return;
    }
    if (_vehicleTypeIds.isEmpty) {
      setState(() => _error = 'กรุณาเลือกประเภทรถที่รับอย่างน้อย 1 รายการ');
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
        'openMinute': _openMinute,
        'closeMinute': _closeMinute,
        'categoryIds': _categoryIds.toList(),
        'vehicleTypeIds': _vehicleTypeIds.toList(),
        'toolPhotoUrls': _toolPhotoUrls,
        'photoUrl': _photoUrl,
        'vehiclePlate': _plateController.text.trim(),
        if (_vehicleDescController.text.trim().isNotEmpty)
          'vehicleDesc': _vehicleDescController.text.trim(),
        if (appState.needsContactPhone) 'phone': _phoneController.text.trim(),
      });
      appState.signIn(
        session.accessToken,
        hasProfile: session.hasProfile,
      );
      if (widget.resubmit && mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (error.statusCode == 409 && !widget.resubmit && mounted) {
        await _handleAlreadyRegistered(error.message);
        return;
      }
      setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// บัญชี LINE นี้สมัครไว้แล้วจากเบราว์เซอร์อื่น: เข้าบัญชีนั้นเลยถ้าได้ ไม่งั้นพาไปล็อกอินใหม่
  Future<void> _handleAlreadyRegistered(String message) async {
    final appState = ProviderAppScope.of(context);
    if (await appState.refreshPendingLineSession()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('บัญชีนี้สมัครไว้แล้ว เข้าสู่บัญชีเดิมให้แล้ว')),
      );
      return;
    }
    appState.loginNotice = message;
    appState.signOut();
  }

  Future<void> _switchAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ออกจากระบบ?'),
        content: const Text(
          'ข้อมูลที่กรอกไว้ในหน้านี้จะหายไป ถ้าเคยสมัครด้วยบัญชีอื่นแล้วให้เข้าสู่ระบบด้วยบัญชีนั้น',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) ProviderAppScope.of(context).signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.resubmit ? 'ส่งใบสมัครใหม่' : 'ลงทะเบียนเป็นช่าง'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(FixGoSpacing.md),
          children: [
            // เคยสมัครด้วยบัญชีอื่น หรือเบราว์เซอร์นี้จำบัญชีเก่าไว้ ให้ออกไปเข้าใหม่ได้
            if (!widget.resubmit)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _submitting ? null : _switchAccount,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('ออกจากระบบ / ใช้บัญชีอื่น'),
                ),
              ),
            Text(
              'กรอกข้อมูลเพื่อให้ทีมงานส่งงานได้ตรงตามประเภทของช่าง',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FixGoSpacing.lg),
            _ProfilePhotoPicker(
              key: _photoPickerKey,
              photoUrl: _photoUrl,
              uploading: _uploadingPhoto,
              missing: _photoMissing,
              onPick: _pickProfilePhoto,
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
            // สมัครผ่าน LINE ยังไม่มีเบอร์ ลูกค้าต้องโทรหาช่างได้ ทีมงานจะโทรยืนยันเบอร์นี้ก่อนอนุมัติ
            if (ProviderAppScope.of(context).needsContactPhone) ...[
              const SizedBox(height: FixGoSpacing.md),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'เบอร์โทรที่ลูกค้าติดต่อได้',
                  helperText: 'ทีมงานจะโทรยืนยันเบอร์นี้ก่อนอนุมัติ',
                ),
                validator: (value) =>
                    RegExp(r'^0[0-9]{8,9}$').hasMatch((value ?? '').trim())
                        ? null
                        : 'กรุณากรอกเบอร์โทร 9-10 หลัก ขึ้นต้นด้วย 0',
              ),
            ],
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
            const _SectionTitle('รถที่ใช้ไปหน้างาน'),
            TextFormField(
              controller: _plateController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: 'ทะเบียนรถ',
                hintText: 'เช่น 1กข 1234 กรุงเทพมหานคร',
              ),
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'กรุณากรอกทะเบียนรถ ลูกค้าใช้ยืนยันตัวช่าง'
                  : null,
            ),
            TextFormField(
              controller: _vehicleDescController,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'ยี่ห้อ / สีรถ (ไม่บังคับ)',
                hintText: 'เช่น กระบะ Isuzu สีขาว',
              ),
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('ตำแหน่งร้าน / พื้นที่รับงาน'),
            _PinCard(
              lat: _baseLat,
              lng: _baseLng,
              address: _pinAddress,
              accuracyMeters: _pinAccuracy,
              error: _pinError,
              locating: _locatingPin,
              onPin: _pinCurrentLocation,
              onPinOnMap: _pinOnMap,
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('เวลารับงาน'),
            Text(
              'ระบบส่งงานให้เฉพาะในช่วงนี้ แก้ได้ทุกเมื่อจากหน้าหลักของแอป',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FixGoSpacing.sm),
            WorkingHoursFields(
              open: _openMinute,
              close: _closeMinute,
              custom: _customHours,
              onChanged: (open, close, {required custom}) => setState(() {
                _openMinute = open;
                _closeMinute = close;
                _customHours = custom;
              }),
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('งานบริการที่รับทำ (เลือกได้หลายข้อ)'),
            FutureBuilder<List<ServiceCategory>>(
              future: _categoriesFuture,
              builder: (context, snapshot) {
                final categories = snapshot.data;
                if (categories == null && snapshot.hasError) {
                  return ErrorStateView(
                    compact: true,
                    error: snapshot.error,
                    title: 'โหลดงานบริการไม่สำเร็จ',
                    onRetry: () => setState(
                      () => _categoriesFuture =
                          ProviderAppScope.of(context).api.listCategories(),
                    ),
                  );
                }
                if (categories == null) {
                  return const Padding(
                    padding: EdgeInsets.all(FixGoSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (categories.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(FixGoSpacing.md),
                    child: Text(
                        'ตอนนี้ยังไม่มีงานบริการที่เปิดรับช่าง กลับมาสมัครอีกครั้งภายหลัง'),
                  );
                }
                return _ChoiceGrid(
                  items: [
                    for (final category in categories)
                      (
                        id: category.id,
                        label: category.name,
                        asset: categoryIconAsset(category.iconKey),
                      ),
                  ],
                  selected: _categoryIds,
                  onChanged: () => setState(() {}),
                );
              },
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('ประเภทรถที่รับ (เลือกได้หลายข้อ)'),
            FutureBuilder<List<VehicleType>>(
              future: _vehicleTypesFuture,
              builder: (context, snapshot) {
                final vehicleTypes = snapshot.data;
                if (vehicleTypes == null && snapshot.hasError) {
                  return ErrorStateView(
                    compact: true,
                    error: snapshot.error,
                    title: 'โหลดประเภทรถไม่สำเร็จ',
                    onRetry: () => setState(
                      () => _vehicleTypesFuture =
                          ProviderAppScope.of(context).api.listVehicleTypes(),
                    ),
                  );
                }
                if (vehicleTypes == null) {
                  return const Padding(
                    padding: EdgeInsets.all(FixGoSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (vehicleTypes.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(FixGoSpacing.md),
                    child: Text(
                        'ยังไม่มีประเภทรถให้เลือก กลับมาลองอีกครั้งภายหลัง'),
                  );
                }
                return _ChoiceGrid(
                  items: [
                    for (final vehicleType in vehicleTypes)
                      (
                        id: vehicleType.id,
                        label: vehicleType.name,
                        asset: vehicleIconAsset(vehicleType.slug),
                      ),
                  ],
                  selected: _vehicleTypeIds,
                  onChanged: () => setState(() {}),
                );
              },
            ),
            const SizedBox(height: FixGoSpacing.lg),
            const _SectionTitle('รูปเครื่องมือช่าง (ไม่บังคับ)'),
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
                          onPressed:
                              _uploadingToolPhotos || _toolPhotoUrls.length >= 6
                                  ? null
                                  : _pickToolPhotos,
                          child: Text(
                            _uploadingToolPhotos ? 'กำลังอัปโหลด' : 'เพิ่มรูป',
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'ถ่ายเฉพาะเครื่องมือหรือรถที่ใช้ออกงาน เช่น แม่แรง '
                      'สายพ่วงแบต ชุดประแจ ช่วยให้ทีมงานอนุมัติได้เร็วขึ้น',
                    ),
                    const SizedBox(height: FixGoSpacing.xs),
                    Text(
                      'รูปหน้าของคุณให้ใส่ที่วงกลมด้านบนสุด',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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

/// รูปโปรไฟล์หน้าตรง: ทีมงานใช้ตรวจตัวตน และลูกค้าเห็นในการ์ดช่างตอนช่างรับงาน
class _ProfilePhotoPicker extends StatelessWidget {
  const _ProfilePhotoPicker({
    super.key,
    required this.photoUrl,
    required this.uploading,
    required this.missing,
    required this.onPick,
  });

  final String? photoUrl;
  final bool uploading;
  final bool missing;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: uploading ? null : onPick,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: missing ? FixGoColors.error : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: FixGoColors.accentSoft,
                  backgroundImage:
                      photoUrl == null ? null : NetworkImage(photoUrl!),
                  child: photoUrl == null
                      ? Image.asset(technicianIconAsset, height: 64)
                      : null,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: FixGoColors.accent,
                  child: uploading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.photo_camera,
                          size: 18,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FixGoSpacing.sm),
        Text(
          photoUrl == null ? 'แตะเพื่อใส่รูปหน้าตรง (บังคับ)' : 'เปลี่ยนรูป',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: missing ? FixGoColors.error : null,
          ),
        ),
        Text(
          'เห็นหน้าชัด ไม่ใส่แว่นดำ ลูกค้าจะเห็นรูปนี้ตอนคุณรับงาน',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// ตัวเลือกแบบการ์ดพร้อมไอคอน 3D กดเพื่อเลือก/ยกเลิก เลือกได้หลายข้อ
class _ChoiceGrid extends StatelessWidget {
  const _ChoiceGrid({
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<({String id, String label, String asset})> items;
  final Set<String> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = FixGoSpacing.sm;
        final width = (constraints.maxWidth - spacing * 2) / 3;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _ChoiceTile(
                  label: item.label,
                  asset: item.asset,
                  selected: selected.contains(item.id),
                  onTap: () {
                    if (!selected.remove(item.id)) selected.add(item.id);
                    onChanged();
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? FixGoColors.accentSoft : FixGoColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FixGoRadius.md),
          side: BorderSide(
            color: selected ? FixGoColors.accent : FixGoColors.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                child: Column(
                  children: [
                    Image.asset(asset, height: 44, width: 44),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: Center(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.check_circle,
                    size: 20,
                    color: FixGoColors.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ปักหมุดจาก GPS แล้วแสดงที่อยู่ ความแม่นยำ และลิงก์เปิดแผนที่ ให้ช่างเช็กเองได้ว่าตรงไหม
class _PinCard extends StatelessWidget {
  const _PinCard({
    required this.lat,
    required this.lng,
    required this.address,
    required this.accuracyMeters,
    required this.error,
    required this.locating,
    required this.onPin,
    required this.onPinOnMap,
  });

  final double? lat;
  final double? lng;
  final String? address;
  final double? accuracyMeters;
  final String? error;
  final bool locating;
  final VoidCallback onPin;

  /// GPS ใช้ไม่ได้หรือไม่ได้ยืนอยู่ที่ร้าน: เลื่อนแผนที่ปักหมุดเอง
  final VoidCallback onPinOnMap;

  // เกินรัศมีนี้ GPS ยังไม่นิ่ง (มักเป็นตำแหน่งจากเสาสัญญาณ/Wi-Fi) ควรกดใหม่
  static const _roughAccuracyMeters = 200.0;

  @override
  Widget build(BuildContext context) {
    final pinned = lat != null && lng != null;
    final accuracy = accuracyMeters;
    final rough = accuracy != null && accuracy > _roughAccuracyMeters;
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  pinned ? Icons.location_on : Icons.location_off_outlined,
                  color: error != null
                      ? FixGoColors.error
                      : pinned
                          ? FixGoColors.accent
                          : null,
                ),
                const SizedBox(width: FixGoSpacing.sm),
                Expanded(
                  child: Text(
                    pinned
                        ? (address ?? 'ปักหมุดแล้ว')
                        : (error ?? 'ยังไม่ได้ปักหมุด'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FixGoSpacing.xs),
            if (pinned && accuracy != null)
              Text(
                rough
                    ? 'คลาดเคลื่อนได้ประมาณ ${accuracy.round()} เมตร ออกไปที่โล่งแล้วกดปักใหม่จะแม่นขึ้น'
                    : 'แม่นยำประมาณ ${accuracy.round()} เมตร',
                style: small?.copyWith(
                  color: rough ? FixGoColors.error : null,
                ),
              )
            else
              Text(
                'ยืนอยู่ที่ร้านหรือจุดที่ออกรับงานบ่อย แล้วกดปุ่มด้านล่าง ใช้คำนวณว่างานอยู่ใกล้คุณแค่ไหน',
                style: small,
              ),
            const SizedBox(height: FixGoSpacing.sm),
            // ธีมกำหนดความกว้างขั้นต่ำเป็น infinity ปุ่มในแถวต้องอยู่ใน Expanded ทุกปุ่ม
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: locating ? null : onPin,
                    icon: locating
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(pinned ? 'ปักใหม่' : 'ใช้ตำแหน่งปัจจุบัน'),
                  ),
                ),
                const SizedBox(width: FixGoSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: locating ? null : onPinOnMap,
                    icon: const Icon(Icons.push_pin_outlined),
                    label: const Text('ปักหมุดบนแผนที่'),
                  ),
                ),
              ],
            ),
            if (pinned)
              TextButton.icon(
                onPressed: () => LocationService.openInMaps(lat!, lng!),
                icon: const Icon(Icons.map_outlined),
                label: const Text('ดูบนแผนที่'),
              ),
          ],
        ),
      ),
    );
  }
}
