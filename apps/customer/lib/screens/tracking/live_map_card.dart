import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// แผนที่สดตอนช่างกำลังมา: หมุดจุดนัดของลูกค้า + หมุดช่าง + เวลาถึงโดยประมาณ
/// ใช้แผนที่ OpenStreetMap (ฟรี ไม่ต้องมี API key) ตำแหน่งช่างและ ETA มาจาก backend
class LiveMapCard extends StatelessWidget {
  const LiveMapCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final provider = order.provider;
    final pickup = LatLng(order.pickupLat, order.pickupLng);
    final mechanic = provider != null && provider.hasLivePosition
        ? LatLng(provider.currentLat!, provider.currentLng!)
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EtaHeader(provider: provider),
          SizedBox(
            height: 220,
            child: FlutterMap(
              // เปลี่ยน key เมื่อช่างขยับ ให้กล้องจัดกรอบใหม่ครอบทั้งสองหมุด
              key: ValueKey('${mechanic?.latitude},${mechanic?.longitude}'),
              options: MapOptions(
                initialCameraFit: mechanic == null
                    ? null
                    : CameraFit.coordinates(
                        coordinates: [pickup, mechanic],
                        padding: const EdgeInsets.all(48),
                        maxZoom: 16,
                      ),
                initialCenter: pickup,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fixgo.fixgo_customer',
                ),
                if (mechanic != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [mechanic, pickup],
                        strokeWidth: 3,
                        color: FixGoColors.accent.withValues(alpha: 0.55),
                        pattern: StrokePattern.dashed(segments: const [8, 6]),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pickup,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on,
                        size: 44,
                        color: FixGoColors.error,
                        semanticLabel: 'จุดนัดของคุณ',
                      ),
                    ),
                    if (mechanic != null)
                      Marker(
                        point: mechanic,
                        width: 46,
                        height: 46,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: FixGoColors.accent,
                              width: 2.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            technicianIconAsset,
                            semanticLabel: 'ตำแหน่งช่าง',
                          ),
                        ),
                      ),
                  ],
                ),
                // OpenStreetMap กำหนดให้แสดงเครดิตบนแผนที่เสมอ
                const Align(
                  alignment: Alignment.bottomRight,
                  child: ColoredBox(
                    color: Color(0xCCFFFFFF),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 10.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EtaHeader extends StatelessWidget {
  const _EtaHeader({required this.provider});

  final ProviderSummary? provider;

  @override
  Widget build(BuildContext context) {
    final eta = provider?.etaMinutes;
    final distance = provider?.distanceKm;
    final updatedAt = provider?.locationUpdatedAt;
    return Container(
      color: FixGoColors.accentSoft,
      padding: const EdgeInsets.symmetric(
        horizontal: FixGoSpacing.md,
        vertical: FixGoSpacing.sm + 2,
      ),
      child: Row(
        children: [
          const Icon(Icons.near_me_rounded, color: FixGoColors.accent),
          const SizedBox(width: FixGoSpacing.sm),
          Expanded(
            child: eta == null
                ? const Text(
                    'รอรับตำแหน่งช่าง แผนที่จะแสดงเมื่อช่างออกเดินทาง',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ช่างจะถึงในอีกราว $eta นาที',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: FixGoColors.navy,
                        ),
                      ),
                      Text(
                        [
                          if (distance != null)
                            'ห่าง ${distance.toStringAsFixed(1)} กม.',
                          if (updatedAt != null)
                            'อัปเดต ${formatRelativeMinutes(updatedAt)}',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
