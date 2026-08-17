import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Streams raw 16kHz/16-bit/mono PCM audio to 讯飞 (iFlytek)'s "语音听写"
/// (IAT) streaming WebSocket API and reports back the accumulated recognized
/// text as it arrives. This is the fallback used when the platform's built-in
/// speech_to_text is unavailable or unreliable (the common case in mainland
/// China -- see china_region_detector.dart).
///
/// The signed connection URL is minted server-side by the `xfyun-auth` Edge
/// Function -- this class never sees the 讯飞 APIKey/APISecret.
class XfyunAsrService {
  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription? _socketSub;
  final _segments = <int, String>{};
  int _frameIndex = 0;
  Completer<void>? _finalReceived;

  bool get isActive => _channel != null;

  Future<void> start({
    required Stream<Uint8List> audioStream,
    required void Function(String text) onResult,
    required void Function(String error) onError,
  }) async {
    final res = await Supabase.instance.client.functions.invoke('xfyun-auth');
    if (res.status != 200) {
      onError('xfyun-auth failed (${res.status}): ${res.data}');
      return;
    }
    final auth = res.data as Map<String, dynamic>;
    final appId = auth['appId'] as String;
    final wsUrl = auth['wsUrl'] as String;

    _segments.clear();
    _frameIndex = 0;
    _finalReceived = Completer<void>();

    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _channel = channel;

    _socketSub = channel.stream.listen(
      (message) => _handleMessage(message as String, onResult, onError),
      onError: (Object e) => onError(e.toString()),
      onDone: () {
        if (_finalReceived != null && !_finalReceived!.isCompleted) {
          _finalReceived!.complete();
        }
      },
    );

    _audioSub = audioStream.listen(
      (chunk) => _sendAudioFrame(chunk, appId),
      onDone: () => _sendFinalFrame(),
    );
  }

  void _handleMessage(String raw, void Function(String) onResult, void Function(String) onError) {
    final Map<String, dynamic> msg = jsonDecode(raw) as Map<String, dynamic>;
    final code = msg['code'] as int?;
    if (code != null && code != 0) {
      onError('${msg['code']}: ${msg['message']}');
      return;
    }
    final data = msg['data'] as Map<String, dynamic>?;
    final result = data?['result'] as Map<String, dynamic>?;
    if (result != null) {
      final sn = result['sn'] as int? ?? _segments.length;
      final wsWords = (result['ws'] as List<dynamic>?) ?? const [];
      final buffer = StringBuffer();
      for (final w in wsWords) {
        final cwList = (w as Map<String, dynamic>)['cw'] as List<dynamic>? ?? const [];
        for (final cw in cwList) {
          buffer.write((cw as Map<String, dynamic>)['w'] as String? ?? '');
        }
      }
      _segments[sn] = buffer.toString();
      final ordered = _segments.keys.toList()..sort();
      onResult(ordered.map((k) => _segments[k]).join());
    }
    if (data?['status'] == 2 && _finalReceived != null && !_finalReceived!.isCompleted) {
      _finalReceived!.complete();
    }
  }

  void _sendAudioFrame(Uint8List chunk, String appId) {
    final audioB64 = base64Encode(chunk);
    final Map<String, dynamic> frame = _frameIndex == 0
        ? {
            'common': {'app_id': appId},
            'business': {
              'language': 'zh_cn',
              'domain': 'iat',
              'accent': 'mandarin',
              'vad_eos': 5000,
            },
            'data': {
              'status': 0,
              'format': 'audio/L16;rate=16000',
              'encoding': 'raw',
              'audio': audioB64,
            },
          }
        : {
            'data': {
              'status': 1,
              'format': 'audio/L16;rate=16000',
              'encoding': 'raw',
              'audio': audioB64,
            },
          };
    _channel?.sink.add(jsonEncode(frame));
    _frameIndex++;
  }

  void _sendFinalFrame() {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'data': {'status': 2, 'audio': ''},
    }));
  }

  /// Stops recording and waits briefly for 讯飞 to flush its final result
  /// before closing the socket, so the last word or two isn't dropped.
  Future<void> stop() async {
    await _audioSub?.cancel();
    _sendFinalFrame();
    if (_finalReceived != null) {
      await _finalReceived!.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    await _socketSub?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }
}
