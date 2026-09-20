import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// FCM + local notifications. Alerts arrive as data {type:"alert", alertId, title}.
class Notifications {
  static final _local = FlutterLocalNotificationsPlugin();
  static const channel = AndroidNotificationChannel('hinamichi_alerts', '災害アラート', description: 'ヒナミチの災害通知', importance: Importance.max);

  /// Called with the alertId whenever the user opens the app from an alert notification.
  static void Function(String alertId)? onOpenAlert;

  static Future<String?> init() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true),
    );
    await _local.initialize(initSettings, onDidReceiveNotificationResponse: (r) {
      final id = r.payload;
      if (id != null && id.isNotEmpty) onOpenAlert?.call(id);
    });
    if (!kIsWeb && Platform.isAndroid) {
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channel);
      await android?.requestNotificationsPermission();
    }

    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission(alert: true, badge: true, sound: true);
    String? token;
    try {
      token = await fcm.getToken();
      await fcm.subscribeToTopic('all');
    } catch (e) {
      debugPrint('FCM unavailable (iOS without APNs is expected): $e');
    }

    FirebaseMessaging.onMessage.listen((m) {
      final data = m.data;
      final title = m.notification?.title ?? data['title'] ?? 'ヒナミチ';
      final body = m.notification?.body ?? '';
      _local.show(m.hashCode, title, body,
          const NotificationDetails(android: AndroidNotificationDetails('hinamichi_alerts', '災害アラート', importance: Importance.max, priority: Priority.high), iOS: DarwinNotificationDetails()),
          payload: data['type'] == 'alert' ? data['alertId'] : null);
      if (data['type'] == 'alert' && data['alertId'] != null) onOpenAlert?.call(data['alertId']!);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      if (m.data['type'] == 'alert' && m.data['alertId'] != null) onOpenAlert?.call(m.data['alertId']!);
    });
    final initial = await fcm.getInitialMessage();
    if (initial != null && initial.data['type'] == 'alert' && initial.data['alertId'] != null) {
      Future.delayed(const Duration(milliseconds: 800), () => onOpenAlert?.call(initial.data['alertId']!));
    }
    return token;
  }

  /// iOS without APNs, or any device: mirror a Firestore alert as a local notification.
  static Future<void> showLocalAlert(String alertId, String title) => _local.show(alertId.hashCode, '⚠️ $title', 'セナヴィがあなたへの影響を確認します',
      const NotificationDetails(android: AndroidNotificationDetails('hinamichi_alerts', '災害アラート', importance: Importance.max, priority: Priority.high), iOS: DarwinNotificationDetails()),
      payload: alertId);
}
