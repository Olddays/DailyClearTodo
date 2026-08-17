import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'china_region_detector.dart';
import 'xfyun_asr_service.dart';

/// Routes between two speech-to-text backends:
/// - speech_to_text (system-native: Android SpeechRecognizer / iOS+macOS
///   Speech framework / Web Speech API / Windows) -- free, but its Google-
///   backed implementations are effectively unusable in mainland China (no
///   Google Play Services on most China-market Android phones, and the
///   underlying network calls are blocked without a VPN).
/// - 讯飞 (iFlytek) streaming ASR -- used when the device looks like it's in
///   mainland China, or when speech_to_text itself reports unavailable
///   (covers GMS-less devices generally, not just China).
final voiceInputProvider = NotifierProvider<VoiceInputNotifier, VoiceInputState>(
  VoiceInputNotifier.new,
);

class VoiceInputState {
  final bool isAvailable;
  final bool isListening;
  final bool checkedAvailability;
  final bool usesXfyun;

  /// Normalized 0.0-1.0 mic input level while listening, for a reactive UI
  /// (mic button pulsing with the user's voice). 0 when idle.
  final double amplitude;

  const VoiceInputState({
    this.isAvailable = false,
    this.isListening = false,
    this.checkedAvailability = false,
    this.usesXfyun = false,
    this.amplitude = 0.0,
  });

  VoiceInputState copyWith({
    bool? isAvailable,
    bool? isListening,
    bool? checkedAvailability,
    bool? usesXfyun,
    double? amplitude,
  }) {
    return VoiceInputState(
      isAvailable: isAvailable ?? this.isAvailable,
      isListening: isListening ?? this.isListening,
      checkedAvailability: checkedAvailability ?? this.checkedAvailability,
      usesXfyun: usesXfyun ?? this.usesXfyun,
      amplitude: amplitude ?? this.amplitude,
    );
  }
}

/// Both backends report loudness on a roughly-dB-like scale but with
/// different practical ranges (record's is real dBFS, ~-45..0 for normal
/// speech; speech_to_text's varies per platform). This isn't meant to be
/// scientifically accurate -- just clamps+normalizes into 0..1 so the mic
/// button has something reactive to animate against.
double _normalizeDb(double db, {double floor = -45, double ceiling = 0}) {
  final clamped = db.clamp(floor, ceiling);
  return (clamped - floor) / (ceiling - floor);
}

class VoiceInputNotifier extends Notifier<VoiceInputState> {
  final _speech = stt.SpeechToText();
  final _recorder = AudioRecorder();
  final _xfyun = XfyunAsrService();
  StreamSubscription<Amplitude>? _amplitudeSub;

  @override
  VoiceInputState build() {
    ref.onDispose(() {
      if (_speech.isListening) _speech.stop();
      if (_xfyun.isActive) _xfyun.stop();
      _amplitudeSub?.cancel();
      _recorder.dispose();
    });
    return const VoiceInputState();
  }

  Future<void> _ensureInitialized() async {
    if (state.checkedAvailability) return;

    // Region heuristic short-circuits straight to 讯飞 without even trying
    // the system recognizer -- in mainland China that attempt would just
    // hang/fail slowly rather than fail fast.
    var useXfyun = isLikelyMainlandChina();
    var systemAvailable = false;

    if (!useXfyun) {
      systemAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            state = state.copyWith(isListening: false, amplitude: 0.0);
          }
        },
        onError: (_) => state = state.copyWith(isListening: false, amplitude: 0.0),
      );
      if (!systemAvailable) useXfyun = true;
    }

    state = state.copyWith(
      isAvailable: useXfyun || systemAvailable,
      usesXfyun: useXfyun,
      checkedAvailability: true,
    );
  }

  Future<void> startListening({required void Function(String text) onPartialResult}) async {
    await _ensureInitialized();
    if (!state.isAvailable) return;

    if (state.usesXfyun) {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return;
      state = state.copyWith(isListening: true, amplitude: 0.0);
      final audioStream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );
      _amplitudeSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        state = state.copyWith(amplitude: _normalizeDb(amp.current));
      });
      await _xfyun.start(
        audioStream: audioStream,
        onResult: onPartialResult,
        onError: (_) => state = state.copyWith(isListening: false, amplitude: 0.0),
      );
    } else {
      state = state.copyWith(isListening: true, amplitude: 0.0);
      await _speech.listen(
        onResult: (result) => onPartialResult(result.recognizedWords),
        onSoundLevelChange: (level) {
          // speech_to_text's level isn't a fixed dBFS range across platforms;
          // this floor/ceiling pair is looser than record's to compensate.
          state = state.copyWith(amplitude: _normalizeDb(level, floor: -2, ceiling: 10));
        },
        listenOptions: stt.SpeechListenOptions(localeId: 'zh_CN'),
      );
    }
  }

  Future<void> stopListening() async {
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    if (state.usesXfyun) {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      if (_xfyun.isActive) await _xfyun.stop();
    } else if (_speech.isListening) {
      await _speech.stop();
    }
    state = state.copyWith(isListening: false, amplitude: 0.0);
  }
}

/// Small helper so the UI doesn't need to know the raw amplitude semantics --
/// just a scale multiplier for the mic button/glow.
double micScaleFor(double amplitude) => 1.0 + math.min(amplitude, 1.0) * 0.6;
