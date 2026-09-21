import 'package:shared_preferences/shared_preferences.dart';

/// Runtime configuration. API base can be overridden at build (--dart-define) or in Settings.
class AppConfig {
  static const defaultApiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://hinamichi.vercel.app');
  /// 会場に置いて誰でも触れる状態にするビルド(`--dart-define=KIOSK=true`)。
  ///
  /// 平時の画面はそのままに、開発用の道具(モックモード・Widget ギャラリー・
  /// API の向き先・位置の固定)だけ隠す。代わりに災害の発火を「体験する」として
  /// 前に出し、フレンドは初回起動で入れておく ── 触る人に設定を辿らせないため。
  static const kiosk = bool.fromEnvironment('KIOSK');

  static Future<String> apiBase() async => (await SharedPreferences.getInstance()).getString('apiBase') ?? defaultApiBase;
  static Future<void> setApiBase(String v) async => (await SharedPreferences.getInstance()).setString('apiBase', v.trim());
}
