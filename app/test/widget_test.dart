import 'package:flutter_test/flutter_test.dart';

import 'package:dailyclear/core/config/app_config.dart';

void main() {
  test('AppConfig.isConfigured is false without --dart-define values', () {
    // In the test runner no --dart-define is passed, so both should be empty.
    expect(AppConfig.supabaseUrl.isEmpty, isTrue);
    expect(AppConfig.isConfigured, isFalse);
  });
}
