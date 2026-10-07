import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

/// ตัวเลือกด่วน (รหัสตรงกับ SUGGESTION_CHOICES ของ backend)
const suggestionChoiceLabels = <String, String>{
  'TOW_TRUCK': 'เพิ่มบริการรถยก',
  'FASTER_ARRIVAL': 'ช่างมาเร็วขึ้น',
  'LOWER_PRICE': 'ราคาถูกลง',
  'MORE_AREAS': 'เพิ่มพื้นที่ให้บริการ',
  'OTHER': 'อื่นๆ',
};

/// คำถามเสริมหลังให้ดาว: อยากให้ FixGo เพิ่มบริการหรือปรับอะไร (ไม่บังคับ กดข้ามได้)
/// คำตอบส่งถึงทีม FixGo ไม่ใช่ช่าง
class SuggestionCard extends StatefulWidget {
  const SuggestionCard({
    super.key,
    required this.api,
    required this.orderId,
    required this.onDone,
  });

  final FixGoApiClient api;
  final String orderId;

  /// ส่งสำเร็จ (true) หรือกดข้าม (false)
  final ValueChanged<bool> onDone;

  @override
  State<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<SuggestionCard> {
  final _selected = <String>{};
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canSend => _selected.isNotEmpty || _text.text.trim().isNotEmpty;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.api.sendServiceSuggestion(
        widget.orderId,
        choices: [
          for (final code in suggestionChoiceLabels.keys)
            if (_selected.contains(code)) code,
        ],
        otherText: _text.text,
      );
      if (mounted) widget.onDone(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = userMessageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'อยากให้ FixGo เพิ่มบริการหรือปรับอะไร',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'ไม่บังคับ เลือกได้หลายข้อ ทีมงานอ่านทุกคำตอบ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FixGoSpacing.sm),
            Wrap(
              spacing: FixGoSpacing.xs,
              runSpacing: FixGoSpacing.xs,
              children: [
                for (final entry in suggestionChoiceLabels.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: _selected.contains(entry.key),
                    onSelected: _sending
                        ? null
                        : (on) => setState(() {
                              if (on) {
                                _selected.add(entry.key);
                              } else {
                                _selected.remove(entry.key);
                              }
                            }),
                  ),
              ],
            ),
            const SizedBox(height: FixGoSpacing.sm),
            TextField(
              controller: _text,
              enabled: !_sending,
              maxLines: 2,
              maxLength: 300,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'พิมพ์เพิ่มเติม เช่น บริการที่อยากให้มี',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: FixGoSpacing.xs),
                child: Text(
                  _error!,
                  style: const TextStyle(color: FixGoColors.error),
                ),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: _sending ? null : () => widget.onDone(false),
                  child: const Text('ข้าม'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _sending || !_canSend ? null : _send,
                  child: Text(_sending ? 'กำลังส่ง...' : 'ส่งความเห็น'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
