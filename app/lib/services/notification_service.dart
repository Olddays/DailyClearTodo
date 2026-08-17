import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications, initialized once at app
/// startup. Cross-platform: libnotify (Linux), WinRT toast (Windows),
/// UNUserNotificationCenter (macOS/iOS), NotificationManager (Android).
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const linuxInit = LinuxInitializationSettings(defaultActionName: '打开日清');
    const darwinInit = DarwinInitializationSettings();
    const windowsInit = WindowsInitializationSettings(
      appName: '日清',
      appUserModelId: 'com.dailyclear.app',
      guid: 'e9b1f4e2-6b3a-4a7b-9b7a-2b6f1a2c9d3e',
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
        linux: linuxInit,
        windows: windowsInit,
      ),
    );
    _initialized = true;
  }

  Future<void> showPomodoroComplete(String taskTitle) async {
    await _plugin.show(
      id: 0,
      title: '番茄钟结束',
      body: '「$taskTitle」的番茄钟结束了，该任务是否完成？',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'pomodoro_channel',
          '番茄钟提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        linux: LinuxNotificationDetails(),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
    );
  }
}
