import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../location_service.dart';
import '../theme.dart';

/// กลางกรุงเทพฯ ใช้เมื่อยังไม่มีพิกัดเริ่มต้นเลย ผู้ใช้ต้องเลื่อนหมุดเองก่อนยืนยัน
const _fallbackCenter = LatLng(13.7563, 100.5018);

/// เปิดหน้าปักหมุดเต็มจอ คืนตำแหน่งที่เลือก หรือ null ถ้ากดย้อนกลับ
Future<LocationResult?> pickLocationOnMap(
  BuildContext context, {
  LocationResult? initial,
  String title = 'ปักหมุดตำแหน่ง',
  String userAgentPackageName = 'com.fixgo.app',
}) {
  return Navigator.of(context).push<LocationResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MapPinPicker(
        initial: initial,
        title: title,
        userAgentPackageName: userAgentPackageName,
      ),
    ),
  );
}

/// หน้าปักหมุดบนแผนที่ OpenStreetMap: หมุดอยู่กลางจอ ผู้ใช้เลื่อนแผนที่ให้ตรงจุด
/// ค้นหาที่อยู่ในประเทศไทยได้ (Nominatim) แล้วกด "ใช้ตำแหน่งนี้"
///
/// ใช้แทน GPS เมื่อขอสิทธิ์ไม่ได้ หาตำแหน่งไม่ทัน หรือเรียกช่าง/นัดตรวจรถให้จุดอื่น
class MapPinPicker extends StatefulWidget {
  const MapPinPicker({
    super.key,
    this.initial,
    this.title = 'ปักหมุดตำแหน่ง',
    this.userAgentPackageName = 'com.fixgo.app',
  });

  final LocationResult? initial;
  final String title;

  /// OpenStreetMap ขอให้ระบุแอปที่เรียก tile
  final String userAgentPackageName;

  @override
  State<MapPinPicker> createState() => _MapPinPickerState();
}

class _MapPinPickerState extends State<MapPinPicker> {
  final _map = MapController();
  final _search = TextEditingController();
  late LatLng _center = widget.initial == null
      ? _fallbackCenter
      : LatLng(widget.initial!.latitude, widget.initial!.longitude);
  String? _address;
  bool _resolving = false;
  bool _searching = false;
  bool _locating = false;
  List<LocationResult> _results = const [];
  Timer? _geocodeDebounce;
  int _geocodeRequest = 0;

  @override
  void initState() {
    super.initState();
    _address = widget.initial?.address;
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  /// หยุดเลื่อนแผนที่ 1 วินาทีแล้วค่อยแปลงเป็นที่อยู่ (Nominatim จำกัด 1 ครั้ง/วินาที)
  void _onMoved(LatLng center) {
    _center = center;
    _geocodeDebounce?.cancel();
    setState(() {
      _address = null;
      _resolving = true;
    });
    _geocodeDebounce = Timer(const Duration(seconds: 1), () async {
      final request = ++_geocodeRequest;
      final address = await LocationService.reverseGeocode(
          center.latitude, center.longitude);
      if (!mounted || request != _geocodeRequest) return;
      setState(() {
        _address = address;
        _resolving = false;
      });
    });
  }

  void _moveTo(LocationResult location) {
    final point = LatLng(location.latitude, location.longitude);
    _map.move(point, 17);
    _geocodeDebounce?.cancel();
    _geocodeRequest++;
    setState(() {
      _center = point;
      _address = location.address;
      _resolving = false;
      _results = const [];
    });
  }

  Future<void> _runSearch() async {
    FocusScope.of(context).unfocus();
    final query = _search.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    final results = await LocationService.searchAddress(query);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results;
    });
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('ไม่พบที่อยู่นี้ ลองพิมพ์ชื่อสถานที่หรือถนน')),
      );
    }
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    try {
      final location = await LocationService.getCurrentLocation();
      if (mounted) _moveTo(location);
    } on LocationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    Navigator.of(context).pop(
      LocationResult(
        latitude: _center.latitude,
        longitude: _center.longitude,
        address: _address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FixGoSpacing.md,
              FixGoSpacing.sm,
              FixGoSpacing.md,
              FixGoSpacing.sm,
            ),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                hintText: 'ค้นหาที่อยู่ ถนน หรือชื่อสถานที่',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'ค้นหา',
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _runSearch,
                      ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: widget.initial == null ? 11 : 17,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture) _onMoved(camera.center);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: widget.userAgentPackageName,
                    ),
                    const SimpleAttributionWidget(
                      source: Text('OpenStreetMap contributors'),
                    ),
                  ],
                ),
                // หมุดอยู่กลางจอเสมอ ปลายหมุดชี้ตรงจุดกึ่งกลางแผนที่
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(
                        Icons.location_on,
                        size: 48,
                        color: FixGoColors.error,
                        semanticLabel: 'หมุดตำแหน่งที่เลือก',
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: FixGoSpacing.md,
                  bottom: FixGoSpacing.lg,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'ตำแหน่งปัจจุบัน',
                    backgroundColor: Colors.white,
                    foregroundColor: FixGoColors.accent,
                    onPressed: _locating ? null : _useGps,
                    child: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                  ),
                ),
                if (_results.isNotEmpty)
                  Positioned(
                    left: FixGoSpacing.md,
                    right: FixGoSpacing.md,
                    top: 0,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(FixGoRadius.md),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final result = _results[index];
                            return ListTile(
                              leading: const Icon(Icons.place_outlined),
                              title: Text(
                                result.address ??
                                    '${result.latitude.toStringAsFixed(5)}, '
                                        '${result.longitude.toStringAsFixed(5)}',
                              ),
                              onTap: () => _moveTo(result),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(FixGoSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _resolving
                        ? 'กำลังหาที่อยู่...'
                        : _address ??
                            '${_center.latitude.toStringAsFixed(5)}, '
                                '${_center.longitude.toStringAsFixed(5)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: FixGoSpacing.sm),
                  FilledButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.check),
                    label: const Text('ใช้ตำแหน่งนี้'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
