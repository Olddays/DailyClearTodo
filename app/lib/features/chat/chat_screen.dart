import 'package:flutter/material.dart';
import 'package:flutter_gen_ai_chat_ui/flutter_gen_ai_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/chat_message.dart' as domain;
import '../../services/voice_input_service.dart';
import 'chat_controller.dart';

const _aiUser = ChatUser(id: 'assistant', name: '日清');

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messagesController = ChatMessagesController();
  final _inputController = TextEditingController();
  late final ChatUser _currentUser;

  @override
  void initState() {
    super.initState();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'user';
    _currentUser = ChatUser(id: userId, name: '我');
  }

  @override
  void dispose() {
    _messagesController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _toggleVoiceInput() async {
    final voice = ref.read(voiceInputProvider.notifier);
    if (ref.read(voiceInputProvider).isListening) {
      await voice.stopListening();
      return;
    }
    await voice.startListening(
      onPartialResult: (text) {
        _inputController.text = text;
        _inputController.selection = TextSelection.collapsed(offset: text.length);
      },
    );
  }

  /// The Edge Function (and the pomodoro timer's direct DB writes) are the only
  /// things that persist chat_messages -- this repo-backed stream is the single
  /// source of truth. Every emission fully replaces the controller's list rather
  /// than appending, so there's nothing to reconcile/dedupe by hand.
  void _syncFromRows(List<domain.ChatMessage> rows) {
    final mapped = rows
        .map((m) => ChatMessage(
              text: m.text,
              user: m.role == domain.ChatRole.user ? _currentUser : _aiUser,
              createdAt: m.createdAt,
            ))
        .where((m) => m.text.isNotEmpty)
        .toList();
    _messagesController.setMessages(mapped);
  }

  Future<void> _handleSendMessage(ChatMessage message) async {
    await ref.read(voiceInputProvider.notifier).stopListening();
    await ref.read(chatControllerProvider.notifier).send(message.text);
    _inputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatMessagesStreamProvider, (_, next) {
      next.whenData(_syncFromRows);
    });
    final messagesAsync = ref.watch(chatMessagesStreamProvider);
    final sendState = ref.watch(chatControllerProvider);
    final voiceState = ref.watch(voiceInputProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日清'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: '修改密码',
            onPressed: () => context.push('/change-password'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (sendState.error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: Text(
                sendState.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          Expanded(
            child: messagesAsync.when(
              data: (_) => AiChatWidget(
                currentUser: _currentUser,
                aiUser: _aiUser,
                controller: _messagesController,
                onSendMessage: _handleSendMessage,
                loadingConfig: LoadingConfig(isLoading: sendState.isSending),
                inputOptions: InputOptions(
                  textController: _inputController,
                  decoration: InputDecoration(
                    hintText: voiceState.isListening ? '正在听…' : '跟日清说点什么…',
                    border: InputBorder.none,
                  ),
                  sendOnEnter: true,
                  sendOrMicBuilder: (onSend, isEmpty) {
                    if (isEmpty) {
                      return _MicButton(
                        voiceState: voiceState,
                        onPressed: _toggleVoiceInput,
                      );
                    }
                    return IconButton.filled(
                      icon: const Icon(Icons.send),
                      onPressed: onSend,
                    );
                  },
                ),
                welcomeMessageConfig: const WelcomeMessageConfig(
                  title: '早安！今天要做的1-3件事是什么？',
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('加载失败: $err')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulses with the mic input level while listening -- a soft glow behind the
/// icon grows/fades with [VoiceInputState.amplitude], and the icon itself
/// scales slightly, so the user gets visual confirmation their voice is
/// actually being picked up (rather than staring at a static mic icon
/// wondering if it's working).
class _MicButton extends StatelessWidget {
  final VoiceInputState voiceState;
  final VoidCallback onPressed;

  const _MicButton({required this.voiceState, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amplitude = voiceState.isListening ? voiceState.amplitude.clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            width: 28 + amplitude * 22,
            height: 28 + amplitude * 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.error.withValues(alpha: 0.15 + amplitude * 0.25),
            ),
          ),
          AnimatedScale(
            scale: voiceState.isListening ? micScaleFor(amplitude) : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: IconButton(
              icon: Icon(
                voiceState.isListening ? Icons.mic : Icons.mic_none,
                color: voiceState.isListening ? scheme.error : null,
              ),
              tooltip: voiceState.checkedAvailability && !voiceState.isAvailable ? '这个设备不支持语音输入' : '语音输入',
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}
