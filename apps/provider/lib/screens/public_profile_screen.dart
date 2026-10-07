import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';

/// ข้อมูลที่ลูกค้าเห็นในการ์ดช่างหลังรับงาน: รูปหน้าตรง รถที่ขับไป และทะเบียน
/// ช่วยให้ลูกค้ามั่นใจว่าคนที่มาคือช่างที่ระบบส่งมาจริง
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late final _vehicleController = TextEditingController(
    text: widget.profile['vehicleDesc'] as String? ?? '',
  );
  late final _plateController = TextEditingController(
    text: widget.profile['vehiclePlate'] as String? ?? '',
  );
  late String? _photoUrl = widget.profile['photoUrl'] as String?;
  bool _uploading = false;
  bool _saving = false;

  @override
  void dispose() {
    _vehicleController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
    );
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final name = file.name.toLowerCase();
      final url = await ProviderAppScope.of(context).api.uploadImage(
            bytes: await file.readAsBytes(),
            fileName: file.name,
            contentType: name.endsWith('.png')
                ? 'image/png'
                : name.endsWith('.webp')
                    ? 'image/webp'
                    : 'image/jpeg',
            scope: 'PROVIDER_TOOL',
          );
      if (mounted) setState(() => _photoUrl = url);
    } on ApiException catch (error) {
      _toast(userMessageFor(error));
    } catch (_) {
      _toast('อ่านหรืออัปโหลดรูปไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ProviderAppScope.of(context).api.updatePublicProfile(
            photoUrl: _photoUrl ?? '',
            vehicleDesc: _vehicleController.text.trim(),
            vehiclePlate: _plateController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      _toast(userMessageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ข้อมูลที่ลูกค้าเห็น')),
      body: ListView(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        children: [
          Text(
            'ลูกค้าจะเห็นข้อมูลนี้หลังคุณรับงาน ใส่ให้ครบแล้วลูกค้ามั่นใจ '
            'เปิดประตูรับช่างเร็วขึ้น โดยเฉพาะงานกลางคืน',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: FixGoSpacing.lg),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: FixGoColors.accentSoft,
                  backgroundImage:
                      _photoUrl == null ? null : NetworkImage(_photoUrl!),
                  child: _photoUrl == null
                      ? const Icon(
                          Icons.person,
                          size: 56,
                          color: FixGoColors.accent,
                        )
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filled(
                    tooltip: 'เลือกรูป',
                    onPressed: _uploading ? null : _pickPhoto,
                    icon: _uploading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FixGoSpacing.sm),
          Text(
            'รูปหน้าตรง เห็นหน้าชัด ไม่ใส่แว่นดำ',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_photoUrl != null)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _photoUrl = null),
                child: const Text('ลบรูป'),
              ),
            ),
          const SizedBox(height: FixGoSpacing.lg),
          TextField(
            controller: _vehicleController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'รถที่ใช้ไปหน้างาน',
              hintText: 'เช่น กระบะ Isuzu สีขาว',
            ),
          ),
          const SizedBox(height: FixGoSpacing.sm),
          TextField(
            controller: _plateController,
            maxLength: 20,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'ทะเบียนรถ',
              hintText: 'เช่น 1กข 1234 กรุงเทพมหานคร',
            ),
          ),
          const SizedBox(height: FixGoSpacing.lg),
          FixGoButton(
            label: 'บันทึก',
            loading: _saving,
            onPressed: _uploading ? null : _save,
          ),
        ],
      ),
    );
  }
}
