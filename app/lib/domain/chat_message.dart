enum ChatRole { user, assistant, tool }

ChatRole chatRoleFromString(String value) => switch (value) {
      'user' => ChatRole.user,
      'assistant' => ChatRole.assistant,
      _ => ChatRole.tool,
    };

/// A single turn in the conversation. [content] mirrors the Anthropic content-block
/// array stored in chat_messages.content (jsonb) -- we only ever render the text
/// blocks; tool_use/tool_result blocks are hidden from the transcript UI.
class ChatMessage {
  final int? id;
  final ChatRole role;
  final List<dynamic> content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromRow(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as int?,
      role: chatRoleFromString(row['role'] as String),
      content: (row['content'] as List<dynamic>?) ?? const [],
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  factory ChatMessage.local({required ChatRole role, required String text}) {
    return ChatMessage(
      id: null,
      role: role,
      content: [
        {'type': 'text', 'text': text}
      ],
      createdAt: DateTime.now(),
    );
  }

  /// Concatenates all text blocks -- the only content type we render for now.
  String get text {
    final buffer = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        buffer.write(block['text'] as String? ?? '');
      }
    }
    return buffer.toString();
  }
}
