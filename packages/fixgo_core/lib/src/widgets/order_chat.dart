import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';

/// รูปที่แอปเลือกมาให้แนบในแชท (แต่ละแอปใช้ image_picker ของตัวเอง)
typedef ChatImage = ({Uint8List bytes, String fileName, String contentType});

/// เสียงสั้นๆ ตอนมีข้อความใหม่ เล่นไม่ได้ (เบราว์เซอร์บล็อก/ไม่มีลำโพง) ก็ไม่เป็นไร
abstract final class ChatChime {
  static AudioPlayer? _player;

  /// ปิดในเทสต์ที่ไม่มี plugin เสียง
  static bool enabled = true;

  static Future<void> play() async {
    if (!enabled) return;
    unawaited(HapticFeedback.lightImpact().catchError((_) {}));
    try {
      final player =
          _player ??= AudioPlayer()..audioCache = AudioCache(prefix: '');
      await player.play(
        AssetSource('packages/fixgo_core/assets/sounds/chat.wav'),
      );
    } catch (_) {}
  }
}

/// ปุ่มเปิดแชทพร้อมตัวเลขข้อความที่ยังไม่อ่าน
class ChatBadgeButton extends StatelessWidget {
  const ChatBadgeButton({
    super.key,
    required this.label,
    required this.unread,
    required this.onPressed,
  });

  final String label;
  final int unread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.chat_bubble_outline),
      ),
      label: Text(unread > 0 ? '$label ($unread ใหม่)' : label),
    );
  }
}

/// หน้าแชทของงาน ใช้ทั้งแอปลูกค้าและแอปช่าง
///
/// ดึงข้อความใหม่ทุก 4 วินาทีระหว่างเปิดหน้า (ไม่ต้องรอ Firebase) ส่งข้อความหรือรูปได้
/// ตั้งแต่ช่างรับงานจนงานจบ หลังจากนั้นอ่านย้อนหลังได้อย่างเดียว
class OrderChatScreen extends StatefulWidget {
  const OrderChatScreen({
    super.key,
    required this.api,
    required this.orderId,
    required this.me,
    required this.title,
    this.pickImage,
    this.pollInterval = const Duration(seconds: 4),
  });

  final FixGoApiClient api;
  final String orderId;
  final ChatSender me;

  /// เช่น "แชทกับช่างสมชาย" หรือ "แชทกับลูกค้า"
  final String title;
  final Future<ChatImage?> Function(BuildContext context)? pickImage;
  final Duration pollInterval;

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = const [];
  bool _canSend = false;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(widget.pollInterval, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final chat = await widget.api.getOrderChat(widget.orderId);
      if (!mounted) return;
      final before = _messages.length;
      final incoming = chat.messages.length > before &&
          !_loading &&
          chat.messages.skip(before).any((m) => m.sender != widget.me);
      setState(() {
        _messages = chat.messages;
        _canSend = chat.canSend;
        _loading = false;
        _error = null;
      });
      if (chat.messages.length != before) _scrollToEnd();
      if (incoming) unawaited(ChatChime.play());
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send({String? imageUrl}) async {
    final text = _input.text.trim();
    if (text.isEmpty && imageUrl == null) return;
    setState(() => _sending = true);
    try {
      final message = await widget.api.sendOrderMessage(
        widget.orderId,
        text: imageUrl == null ? text : null,
        imageUrl: imageUrl,
      );
      if (!mounted) return;
      if (imageUrl == null) _input.clear();
      setState(() => _messages = [..._messages, message]);
      _scrollToEnd();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      unawaited(_load());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final pick = widget.pickImage;
    if (pick == null) return;
    final image = await pick(context);
    if (image == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final url = await widget.api.uploadImage(
        bytes: image.bytes,
        fileName: image.fileName,
        contentType: image.contentType,
        scope: 'ORDER',
      );
      await _send(imageUrl: url);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.surface,
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(FixGoSpacing.lg),
                          child: Text(
                            _error ??
                                (_canSend
                                    ? 'ยังไม่มีข้อความ ทักทายหรือแจ้งรายละเอียดเพิ่มเติมได้เลย'
                                    : 'ไม่มีข้อความในงานนี้'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(FixGoSpacing.md),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return _Bubble(
                            message: message,
                            mine: message.sender == widget.me,
                          );
                        },
                      ),
          ),
          if (!_loading && !_canSend)
            Container(
              width: double.infinity,
              color: FixGoColors.disabledBackground,
              padding: const EdgeInsets.all(FixGoSpacing.sm),
              child: const SafeArea(
                top: false,
                child: Text(
                  'งานนี้จบแล้วหรือยังไม่มีช่างรับ แชทอ่านได้อย่างเดียว',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: FixGoColors.disabledForeground),
                ),
              ),
            )
          else if (!_loading)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FixGoSpacing.sm,
                  FixGoSpacing.xs,
                  FixGoSpacing.sm,
                  FixGoSpacing.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.pickImage != null)
                      IconButton(
                        tooltip: 'แนบรูป',
                        onPressed: _sending ? null : _attach,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: !_sending,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'พิมพ์ข้อความ',
                          counterText: '',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: FixGoSpacing.xs),
                    IconButton.filled(
                      tooltip: 'ส่ง',
                      onPressed: _sending ? null : () => _send(),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final time = '${message.createdAt.hour.toString().padLeft(2, '0')}:'
        '${message.createdAt.minute.toString().padLeft(2, '0')}';
    final image = message.imageUrl;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: FixGoSpacing.sm),
          padding: const EdgeInsets.all(FixGoSpacing.sm),
          decoration: BoxDecoration(
            color: mine ? FixGoColors.accent : Colors.white,
            borderRadius: BorderRadius.circular(FixGoRadius.md),
            border: mine ? null : Border.all(color: FixGoColors.hairline),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (image != null)
                GestureDetector(
                  onTap: () => _showImage(context, image),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(FixGoRadius.sm),
                    child: Image.network(
                      image,
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      semanticLabel: 'รูปในแชท แตะเพื่อดูเต็มจอ',
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 200,
                        height: 80,
                        child: Center(child: Text('โหลดรูปไม่ได้')),
                      ),
                    ),
                  ),
                ),
              if (message.text != null)
                Text(
                  message.text!,
                  style: TextStyle(
                    color: mine ? Colors.white : FixGoColors.textPrimary,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                time,
                style: TextStyle(
                  fontSize: 11,
                  color:
                      mine ? FixGoColors.accentSoft : FixGoColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Center(child: Image.network(url)),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  tooltip: 'ปิด',
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
