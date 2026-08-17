import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/chat_message.dart';

final chatMessagesStreamProvider = StreamProvider.autoDispose<List<ChatMessage>>((ref) {
  return ref.watch(chatRepositoryProvider).watchMessages();
});

final chatControllerProvider = NotifierProvider<ChatController, ChatSendState>(ChatController.new);

class ChatSendState {
  final bool isSending;
  final String? error;
  const ChatSendState({this.isSending = false, this.error});
}

/// Owns only the "is a message currently in flight" state -- the actual message
/// list is the realtime stream from chatMessagesStreamProvider, since the Edge
/// Function is the one writing both the user and assistant rows.
class ChatController extends Notifier<ChatSendState> {
  @override
  ChatSendState build() => const ChatSendState();

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;
    state = const ChatSendState(isSending: true);
    try {
      await ref.read(chatRepositoryProvider).sendMessage(trimmed);
      state = const ChatSendState(isSending: false);
    } catch (e) {
      state = ChatSendState(isSending: false, error: e.toString());
    }
  }
}
