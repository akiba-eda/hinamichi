import 'package:shared_preferences/shared_preferences.dart';

/// Runtime configuration. API base can be overridden at build (--dart-define) or in Settings.
class AppConfig {
  static const defaultApiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://hinamichi.vercel.app');
  static const demoDefaultLat = 35.6588; // 南行徳駅
  static const demoDefaultLng = 139.9013;

  static Future<String> apiBase() async => (await SharedPreferences.getInstance()).getString('apiBase') ?? defaultApiBase;
  static Future<void> setApiBase(String v) async => (await SharedPreferences.getInstance()).setString('apiBase', v.trim());
}
