import 'dart:ui' as ui;

/// Heuristic check for "should we prefer the domestic (讯飞) ASR path instead
/// of the platform's built-in speech_to_text". There's no reliable single
/// signal for "this device is in mainland China without access to Google's
/// speech backend", so this combines a few:
///
/// - Device locale region == CN (strongest signal for user preference/market)
/// - Device timezone is a mainland China zone
///
/// This is intentionally a static, offline heuristic (no network probe to
/// Google) -- a probe would add latency to every voice-input attempt and
/// still be unreliable (a blocked host can time out slowly instead of
/// failing fast). Combined with speech_to_text's own initialize() returning
/// false on devices without Google Play Services (most China-market Android
/// phones), this catches the common cases without over-engineering it.
bool isLikelyMainlandChina() {
  final locale = ui.PlatformDispatcher.instance.locale;
  if (locale.countryCode == 'CN') return true;

  final tz = DateTime.now().timeZoneName;
  // Common abbreviations seen for Asia/Shanghai across platforms; not
  // exhaustive, but combined with the locale check above it's good enough as
  // a bias rather than a hard gate -- speech_to_text's own availability check
  // is still the deciding factor when this heuristic says "false".
  if (tz == 'CST' && DateTime.now().timeZoneOffset.inHours == 8) return true;

  return false;
}
