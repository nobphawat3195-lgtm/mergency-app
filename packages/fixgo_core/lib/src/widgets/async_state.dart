import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';

final _thai = RegExp(r'[฀-๿]');

/// ข้อความ error ที่ให้ผู้ใช้เห็นได้: ภาษาไทยเท่านั้น ไม่มีข้อความอังกฤษหรือ stack
///
/// - ข้อความจาก backend ที่เป็นภาษาไทย (เช่น "ราคาเปลี่ยนแล้ว") แสดงตามเดิม เพราะบอกเหตุผลได้ตรงกว่า
/// - error 5xx หรือข้อความที่ไม่ใช่ภาษาไทย (เช่น "Internal server error") ใช้ข้อความกลาง
/// - error อื่น ๆ (แปลงข้อมูลไม่ได้ ฯลฯ) ใช้ [fallback]
String userMessageFor(
  Object? error, {
  String fallback = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
}) {
  if (error is ApiException) {
    if (_thai.hasMatch(error.message)) return error.message;
    if (error.statusCode >= 500) {
      return 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง';
    }
    return fallback;
  }
  if (error is TimeoutException) {
    return 'การเชื่อมต่อใช้เวลานาน กรุณาลองใหม่อีกครั้ง';
  }
  return fallback;
}

/// แสดงผลของปุ่มที่ส่งข้อมูลเป็นแถบข้อความด้านล่าง (ภาษาไทยเสมอ)
void showResultSnackBar(
  BuildContext context, {
  String? success,
  Object? error,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final failed = error != null;
  if (!failed && success == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: failed ? FixGoColors.error : null,
        content: Text(failed ? userMessageFor(error) : success!),
      ),
    );
}

/// กำลังโหลด: spinner กลางจอ ขนาดคงที่ ไม่ทำให้ layout กระตุกตอนข้อมูลมา
class LoadingStateView extends StatelessWidget {
  const LoadingStateView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            if (message != null) ...[
              const SizedBox(height: FixGoSpacing.md),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// กำลังโหลดรายการ: กล่องสีเทาเท่ารายการจริง (ไม่มีแอนิเมชัน ไม่กระพริบ)
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.itemHeight = 84});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'กำลังโหลด',
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(FixGoSpacing.md),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: FixGoSpacing.sm),
        itemBuilder: (_, __) => Container(
          height: itemHeight,
          decoration: BoxDecoration(
            color: FixGoColors.hairline.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(FixGoRadius.md),
          ),
        ),
      ),
    );
  }
}

/// ไม่มีข้อมูล: บอกว่าว่างเพราะอะไร และทำอะไรต่อได้
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: FixGoColors.textSecondary),
            const SizedBox(height: FixGoSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: FixGoSpacing.xs),
              Text(message!,
                  textAlign: TextAlign.center, style: text.bodySmall),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: FixGoSpacing.md),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// โหลดไม่สำเร็จ/เน็ตหลุด: ข้อความไทย + ปุ่ม "ลองใหม่" (ไม่โชว์ error ดิบ)
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    this.error,
    required this.onRetry,
    this.title = 'โหลดไม่สำเร็จ',
    this.compact = false,
  });

  final Object? error;
  final VoidCallback onRetry;
  final String title;

  /// ใช้ในการ์ดหรือส่วนย่อยของหน้า (ไม่จัดกลางจอ)
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final body = Container(
      padding: const EdgeInsets.all(FixGoSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FixGoRadius.md),
        border: Border.all(color: FixGoColors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 36, color: FixGoColors.textSecondary),
          const SizedBox(height: FixGoSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: FixGoSpacing.xs),
          Text(
            userMessageFor(
              error,
              fallback: 'ตรวจอินเทอร์เน็ตแล้วกดลองใหม่อีกครั้ง',
            ),
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: FixGoSpacing.md),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
    if (compact) return body;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: body,
        ),
      ),
    );
  }
}

/// โหลดข้อมูลจาก [future] แล้วแสดงครบ 3 สถานะ: กำลังโหลด / ว่าง / ผิดพลาด
///
/// - กำลังโหลดใหม่ (ดึงลงเพื่อรีเฟรช) ขณะมีข้อมูลเดิม: แสดงข้อมูลเดิมต่อ ไม่กระพริบเป็น spinner
/// - [scrollable] ห่อสถานะว่าง/ผิดพลาดด้วย ListView ให้ RefreshIndicator ดึงลงได้
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.future,
    required this.builder,
    required this.onRetry,
    this.isEmpty,
    this.empty,
    this.loading,
    this.scrollable = false,
    this.errorTitle = 'โหลดไม่สำเร็จ',
  });

  final Future<T>? future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? loading;
  final bool scrollable;
  final String errorTitle;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        final waiting = snapshot.connectionState != ConnectionState.done;
        if (snapshot.hasData) {
          final data = snapshot.data as T;
          if (isEmpty != null && isEmpty!(data) && empty != null) {
            return _wrap(empty!);
          }
          return builder(context, data);
        }
        if (snapshot.hasError && !waiting) {
          return _wrap(
            ErrorStateView(
              error: snapshot.error,
              onRetry: onRetry,
              title: errorTitle,
            ),
          );
        }
        if (!waiting && null is T) {
          // future คืน null ได้ (เช่น ยังไม่มีข้อมูล) ถือว่าว่าง
          return builder(context, snapshot.data as T);
        }
        return loading ?? const LoadingStateView();
      },
    );
  }

  Widget _wrap(Widget child) {
    if (!scrollable) return child;
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}

/// ปุ่มส่งข้อมูลที่กันกดซ้ำ: ระหว่างรอแสดง spinner และกดไม่ได้
/// [onPressed] คืน Future: ปุ่มกลับมากดได้เมื่อจบ (สำเร็จหรือล้มเหลว)
class BusyButton extends StatefulWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.expand = false,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool outlined;
  final bool expand;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed == null || _busy ? null : _run;
    final icon = _busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : widget.icon == null
            ? null
            : Icon(widget.icon);
    final label = Text(widget.label);
    final Widget button = widget.outlined
        ? (icon == null
            ? OutlinedButton(onPressed: onPressed, child: label)
            : OutlinedButton.icon(
                onPressed: onPressed, icon: icon, label: label))
        : (icon == null
            ? FilledButton(onPressed: onPressed, child: label)
            : FilledButton.icon(
                onPressed: onPressed, icon: icon, label: label));
    return widget.expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}
