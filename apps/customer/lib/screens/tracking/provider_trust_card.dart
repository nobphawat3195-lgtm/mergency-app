import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// การ์ดช่าง: ข้อมูลที่ทำให้ลูกค้ามั่นใจว่าคนที่มาคือช่างตัวจริงที่ระบบส่งมา
/// รูป ชื่อ ป้ายยืนยันตัวตน คะแนน จำนวนงาน และทะเบียนรถที่ช่างขับมา
class ProviderTrustCard extends StatelessWidget {
  const ProviderTrustCard({super.key, required this.provider});

  final ProviderSummary provider;

  Future<void> _call(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: provider.phone);
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดแอปโทรศัพท์ได้')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = provider.vehicleDesc ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Avatar(photoUrl: provider.photoUrl),
                const SizedBox(width: FixGoSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        provider.realName,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (provider.verified) ...[
                        const SizedBox(height: 4),
                        const _VerifiedBadge(),
                      ],
                    ],
                  ),
                ),
                IconButton.filled(
                  tooltip: 'โทรหาช่าง',
                  onPressed: () => _call(context),
                  icon: const Icon(Icons.phone),
                  style: IconButton.styleFrom(
                    backgroundColor: FixGoColors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FixGoSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: Icons.star_rounded,
                    iconColor: const Color(0xFFF5A524),
                    value: provider.ratingCount > 0
                        ? provider.ratingAvg.toStringAsFixed(1)
                        : 'ใหม่',
                    label: provider.ratingCount > 0
                        ? '${provider.ratingCount} รีวิว'
                        : 'ยังไม่มีรีวิว',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    icon: Icons.task_alt_rounded,
                    iconColor: FixGoColors.jade,
                    value: '${provider.completedJobs}',
                    label: 'งานสำเร็จ',
                  ),
                ),
                if (provider.experienceYears != null)
                  Expanded(
                    child: _Stat(
                      icon: Icons.workspace_premium_rounded,
                      iconColor: FixGoColors.accent,
                      value: '${provider.experienceYears} ปี',
                      label: 'ประสบการณ์',
                    ),
                  ),
              ],
            ),
            if (provider.vehiclePlate != null || vehicle.isNotEmpty) ...[
              const SizedBox(height: FixGoSpacing.md),
              Container(
                padding: const EdgeInsets.all(FixGoSpacing.sm + 2),
                decoration: BoxDecoration(
                  color: FixGoColors.surface,
                  borderRadius: BorderRadius.circular(FixGoRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_shipping_outlined,
                      color: FixGoColors.accent,
                    ),
                    const SizedBox(width: FixGoSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'รถของช่าง',
                            style: TextStyle(
                              fontSize: 12,
                              color: FixGoColors.textSecondary,
                            ),
                          ),
                          if (vehicle.isNotEmpty)
                            Text(
                              vehicle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (provider.vehiclePlate != null)
                      _PlateChip(plate: provider.vehiclePlate!),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ตรวจทะเบียนรถให้ตรงก่อนให้ช่างเริ่มงาน',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    final fallback = Container(
      height: size,
      width: size,
      padding: const EdgeInsets.all(8),
      color: FixGoColors.accentSoft,
      child: Image.asset(technicianIconAsset),
    );
    return ClipOval(
      child: photoUrl == null
          ? fallback
          : Image.network(
              photoUrl!,
              height: size,
              width: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: FixGoColors.accentSoft,
        borderRadius: BorderRadius.circular(FixGoRadius.pill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 15, color: FixGoColors.success),
          SizedBox(width: 4),
          Text(
            'FixGo ตรวจสอบตัวตนแล้ว',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: FixGoColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 3),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: FixGoColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// ป้ายทะเบียนแบบไทย พื้นขาวขอบดำ ให้ลูกค้าจับคู่กับรถจริงได้เร็ว
class _PlateChip extends StatelessWidget {
  const _PlateChip({required this.plate});

  final String plate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FixGoColors.navy, width: 1.5),
      ),
      child: Text(
        plate,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: FixGoColors.navy,
        ),
      ),
    );
  }
}
