import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_message.dart';

/// Talks to the `chat` Edge Function and to chat_messages directly (for history +
/// realtime updates). The Edge Function is the only path that reaches the LLM;
/// everything else here is plain Supabase REST/Realtime, no LLM involved.
class ChatRepository {
  final SupabaseClient _client;
  ChatRepository(this._client);

  Future<List<ChatMessage>> loadRecentMessages({int limit = 100}) async {
    final rows = await _client
        .from('chat_messages')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromRow)
        .toList()
        .reversed
        .toList();
  }

  /// Sends [message] to the chat Edge Function and returns the assistant's final
  /// reply content blocks. The Edge Function itself persists both the user turn
  /// and the assistant turn to chat_messages -- this call is what triggers that.
  Future<List<dynamic>> sendMessage(String message) async {
    final res = await _client.functions.invoke(
      'chat',
      body: {'message': message},
    );
    if (res.status != 200) {
      throw Exception('chat function failed (${res.status}): ${res.data}');
    }
    final data = res.data as Map<String, dynamic>;
    return data['content'] as List<dynamic>;
  }

  /// Live updates for chat_messages -- picks up both LLM replies from other
  /// devices/sessions and synthetic pomodoro-end system messages written directly
  /// by the client's own timer service.
  Stream<List<ChatMessage>> watchMessages() {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.map(ChatMessage.fromRow).toList());
  }
}
