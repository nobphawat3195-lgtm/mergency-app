import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../order_tracking_screen.dart';

/// Booking wizard 4 ขั้นตอน: บริการ -> บริการย่อย -> ประเภทรถ -> ยืนยัน
class BookingFlow extends StatefulWidget {
  const BookingFlow({super.key, this.initialCategory, this.pickupLocation});

  final ServiceCategory? initialCategory;

  /// ตำแหน่งที่ดึงมาจากหน้า Home แล้ว — ถ้า null (เช่น ผู้ใช้ปฏิเสธสิทธิ์ตอนนั้น)
  /// จะลองขอใหม่อีกครั้งตอนยืนยันออเดอร์
  final LocationResult? pickupLocation;

  @override
  State<BookingFlow> createState() => _BookingFlowState();
}

class _BookingFlowState extends State<BookingFlow> {
  static const _stepLabels = ['บริการ', 'บริการย่อย', 'ประเภทรถ', 'ยืนยัน'];

  int _step = 0;
  ServiceCategory? _category;
  SubService? _subService;
  VehicleType? _vehicleType;
  bool _submitting = false;
  LocationResult? _pickupLocation;

  @override
  void initState() {
    super.initState();
    _pickupLocation = widget.pickupLocation;
    if (widget.initialCategory != null) {
      _category = widget.initialCategory;
      _step = 1;
    }
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step -= 1);
  }

  Future<void> _submit() async {
    final category = _category;
    final subService = _subService;
    final vehicleType = _vehicleType;
    if (category == null || subService == null || vehicleType == null) return;

    setState(() => _submitting = true);
    try {
      // ยังไม่มีตำแหน่ง (เช่น หน้า Home ขอสิทธิ์ไม่สำเร็จตอนนั้น) ลองขอใหม่อีกครั้ง
      // ก่อนสร้างออเดอร์จริง — ห้ามส่งพิกัดปลอม/ค่าเริ่มต้นไปเด็ดขาด เพราะระบบ dispatch
      // ใช้พิกัดนี้คำนวณระยะทางหาช่างใกล้สุด ถ้าใช้ค่าปลอมช่างจะถูกส่งไปผิดที่จริง
      _pickupLocation ??= await LocationService.getCurrentLocation();
      if (!mounted) return;

      final location = _pickupLocation!;
      final api = AppStateScope.of(context).api;
      final order = await api.createOrder(
        categoryId: category.id,
        subServiceId: subService.id,
        vehicleTypeId: vehicleType.id,
        pickupLat: location.latitude,
        pickupLng: location.longitude,
        pickupAddress: location.address,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderTrackingScreen(orderId: order.id),
        ),
      );
    } on LocationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.background,
      appBar: AppBar(
        title: const Text('เลือกบริการ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
      ),
      body: Column(
        children: [
          StepProgress(labels: _stepLabels, currentIndex: _step),
          const Divider(height: 1),
          Expanded(child: _buildStep()),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _CategoryStep(
          onSelected: (category) => setState(() {
            _category = category;
            _step = 1;
          }),
        );
      case 1:
        return _SubServiceStep(
          category: _category!,
          onSelected: (subService) => setState(() {
            _subService = subService;
            _step = 2;
          }),
        );
      case 2:
        return _VehicleTypeStep(
          onSelected: (vehicleType) => setState(() {
            _vehicleType = vehicleType;
            _step = 3;
          }),
        );
      default:
        return _ConfirmStep(
          category: _category!,
          subService: _subService!,
          vehicleType: _vehicleType!,
          submitting: _submitting,
          onConfirm: _submit,
          pickupLocation: _pickupLocation,
        );
    }
  }
}

class _CategoryStep extends StatefulWidget {
  const _CategoryStep({required this.onSelected});

  final ValueChanged<ServiceCategory> onSelected;

  @override
  State<_CategoryStep> createState() => _CategoryStepState();
}

class _CategoryStepState extends State<_CategoryStep> {
  Future<List<ServiceCategory>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppStateScope.of(context).api.listCategories();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ServiceCategory>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _ErrorView(message: 'โหลดหมวดบริการไม่สำเร็จ');
        }
        final categories = snapshot.data ?? const [];
        return ListView.separated(
          padding: const EdgeInsets.all(FixGoSpacing.md),
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(height: FixGoSpacing.sm),
          itemBuilder: (context, index) {
            final category = categories[index];
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: FixGoSpacing.md,
                  vertical: FixGoSpacing.sm,
                ),
                leading: Image.asset(
                  categoryIconAsset(category.iconKey),
                  height: 40,
                  width: 40,
                ),
                title: Text(
                  category.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onSelected(category),
              ),
            );
          },
        );
      },
    );
  }
}

class _SubServiceStep extends StatefulWidget {
  const _SubServiceStep({required this.category, required this.onSelected});

  final ServiceCategory category;
  final ValueChanged<SubService> onSelected;

  @override
  State<_SubServiceStep> createState() => _SubServiceStepState();
}

class _SubServiceStepState extends State<_SubServiceStep> {
  Future<List<SubService>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??=
        AppStateScope.of(context).api.listSubServices(widget.category.id);
  }

  void _showInfo(SubService subService) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(FixGoSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subService.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: FixGoSpacing.sm),
            Text(
              subService.infoNote ??
                  subService.description ??
                  'ราคานี้เป็นราคาเริ่มต้น ไม่รวมค่าอะไหล่ ช่างจะประเมินราคาจริงหน้างานก่อนดำเนินการ',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: FixGoSpacing.lg),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SubService>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _ErrorView(message: 'โหลดบริการย่อยไม่สำเร็จ');
        }
        final subServices = snapshot.data ?? const [];
        return ListView.separated(
          padding: const EdgeInsets.all(FixGoSpacing.md),
          itemCount: subServices.length,
          separatorBuilder: (_, __) => const SizedBox(height: FixGoSpacing.sm),
          itemBuilder: (context, index) {
            final subService = subServices[index];
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => widget.onSelected(subService),
                child: Padding(
                  padding: const EdgeInsets.all(FixGoSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subService.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (subService.description != null) ...[
                              const SizedBox(height: FixGoSpacing.xs),
                              Text(
                                subService.description!,
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: FixGoSpacing.sm),
                      Text(
                        formatSatang(subService.basePrice),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: FixGoColors.navy,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline),
                        color: FixGoColors.textSecondary,
                        onPressed: () => _showInfo(subService),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _VehicleTypeStep extends StatefulWidget {
  const _VehicleTypeStep({required this.onSelected});

  final ValueChanged<VehicleType> onSelected;

  @override
  State<_VehicleTypeStep> createState() => _VehicleTypeStepState();
}

class _VehicleTypeStepState extends State<_VehicleTypeStep> {
  Future<List<VehicleType>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppStateScope.of(context).api.listVehicleTypes();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VehicleType>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _ErrorView(message: 'โหลดประเภทรถไม่สำเร็จ');
        }
        final vehicleTypes = snapshot.data ?? const [];
        return GridView.builder(
          padding: const EdgeInsets.all(FixGoSpacing.md),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: FixGoSpacing.sm,
            crossAxisSpacing: FixGoSpacing.sm,
            childAspectRatio: 1.6,
          ),
          itemCount: vehicleTypes.length,
          itemBuilder: (context, index) {
            final vehicleType = vehicleTypes[index];
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => widget.onSelected(vehicleType),
                child: Center(
                  child: Text(
                    vehicleType.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ConfirmStep extends StatefulWidget {
  const _ConfirmStep({
    required this.category,
    required this.subService,
    required this.vehicleType,
    required this.submitting,
    required this.onConfirm,
    required this.pickupLocation,
  });

  final ServiceCategory category;
  final SubService subService;
  final VehicleType vehicleType;
  final bool submitting;
  final VoidCallback onConfirm;
  final LocationResult? pickupLocation;

  @override
  State<_ConfirmStep> createState() => _ConfirmStepState();
}

class _ConfirmStepState extends State<_ConfirmStep> {
  Future<int>? _quoteFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _quoteFuture ??= AppStateScope.of(context).api.quote(
          widget.subService.id,
          widget.vehicleType.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(FixGoSpacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(FixGoSpacing.md),
                  child: Column(
                    children: [
                      _SummaryRow(
                        label: 'หมวดบริการ',
                        value: widget.category.name,
                      ),
                      const Divider(),
                      _SummaryRow(
                        label: 'บริการ',
                        value: widget.subService.name,
                      ),
                      const Divider(),
                      _SummaryRow(
                        label: 'ประเภทรถ',
                        value: widget.vehicleType.name,
                      ),
                      const Divider(),
                      _SummaryRow(
                        label: 'จุดนัดหมาย',
                        value: widget.pickupLocation?.address ??
                            (widget.pickupLocation != null
                                ? '${widget.pickupLocation!.latitude.toStringAsFixed(5)}, ${widget.pickupLocation!.longitude.toStringAsFixed(5)}'
                                : 'จะขอตำแหน่งอีกครั้งตอนยืนยัน'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: FixGoSpacing.md),
              // TODO: เพิ่มปุ่มแนบรูปปัญหารถ และช่องกรอกหมายเหตุ
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(FixGoSpacing.md),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'ราคาประเมิน',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FutureBuilder<int>(
                        future: _quoteFuture,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            );
                          }
                          return Text(
                            formatSatang(snapshot.data!),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: FixGoColors.navy,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: FixGoSpacing.sm),
              Text(
                'ราคานี้เป็นราคาเริ่มต้น ไม่รวมค่าอะไหล่ '
                'ช่างจะแจ้งราคาจริงให้ยืนยันก่อนดำเนินการเสมอ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(FixGoSpacing.md),
            child: FixGoButton(
              label: 'ยืนยันเรียกช่าง',
              icon: Icons.car_repair,
              loading: widget.submitting,
              onPressed: widget.onConfirm,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FixGoSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.lg),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: FixGoColors.error),
        ),
      ),
    );
  }
}
