import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'core/user_message.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/theme/hina_colors.dart';
import 'app/theme/hina_theme.dart';
import 'core/config.dart';
import 'core/nav.dart';
import 'core/notifications.dart';
import 'domain/senavi.dart';
import 'features/friends/friends_page.dart';
import 'features/home/home_page.dart';
import 'features/map/map_page.dart';
import 'features/settings/settings_page.dart';
import 'features/splash/splash_page.dart';
import 'firebase_options.dart';
import 'state/providers.dart';
import 'ui/atoms/atoms.dart';
import 'ui/molecules/molecules.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 描画中に例外が起きたときの既定は、英語のスタックとソースが載った赤い画面。
  // 利用者に見せるものではないので、セナヴィの言葉に差し替える。原因はログに残す。
  ErrorWidget.builder = (details) {
    debugPrint('[widget error] ${details.exceptionAsString()}');
    return const _FriendlyError();
  };
  // 描画の外(非同期)で誰も受け取らなかった例外。落とさずログに残す。
  PlatformDispatcher.instance.onError = (e, st) {
    debugPrint('[uncaught] $e\n$st');
    return true;
  };

  final bootError = await _boot();
  // 起動に失敗しても必ず何かを描く。ここで例外を素通しにすると、上の onError が
  // 受けて runApp に届かず、真っ白な画面のまま止まる(実機で起きた)。
  runApp(bootError == null ? const ProviderScope(child: HinamichiApp()) : _BootFailedApp(error: bootError));
}

/// Firebase の初期化と匿名サインイン。失敗の理由を返す(成功なら null)。
/// 圏外・Wi-Fi 切れ・時計のずれで落ちる。ここが通らないと何も動かない。
Future<Object?> _boot() async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
    return null;
  } catch (e, st) {
    debugPrint('[boot] $e\n$st');
    return e;
  }
}

/// 起動できなかったときの画面。理由と、もう一度試す手段だけを出す。
class _BootFailedApp extends StatefulWidget {
  final Object error;
  const _BootFailedApp({required this.error});
  @override
  State<_BootFailedApp> createState() => _BootFailedAppState();
}

class _BootFailedAppState extends State<_BootFailedApp> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    final err = await _boot();
    if (!mounted) return;
    if (err == null) {
      runApp(const ProviderScope(child: HinamichiApp()));
      return;
    }
    setState(() => _retrying = false);
    showSenaviToast(userMessage(err, action: 'セナヴィに接続'), error: true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ヒナミチ',
        debugShowCheckedModeBanner: false,
        theme: hinaTheme(),
        navigatorKey: rootNavigatorKey,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SenaviAvatar(SenaviMood.troubled, size: 96),
                const SizedBox(height: 12),
                Text('セナヴィに接続できませんでした', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(userMessage(widget.error), style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                HinaButton.primary('もう一度試す', loading: _retrying, onPressed: _retrying ? null : _retry),
              ]),
            ),
          ),
        ),
      );
}

/// 赤いエラー画面の代わり。何が壊れたかではなく、どうすればいいかだけを出す。
class _FriendlyError extends StatelessWidget {
  const _FriendlyError();
  @override
  Widget build(BuildContext context) => Material(
        color: HinaColors.bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SenaviAvatar(SenaviMood.troubled, size: 96),
              const SizedBox(height: 12),
              Text('うまく表示できませんでした', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('画面を開き直すか、アプリを再起動してください。', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}

class HinamichiApp extends ConsumerStatefulWidget {
  const HinamichiApp({super.key});
  @override
  ConsumerState<HinamichiApp> createState() => _HinamichiAppState();
}

class _HinamichiAppState extends ConsumerState<HinamichiApp> {
  final _seenAlerts = <String>{};

  /// 01 スプラッシュを抜けたか。アラートが来たら待たずに本体へ送る。
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _register(String? fcmToken) async {
    try {
      await ref.read(apiProvider).register(fcmToken: fcmToken, platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
    } catch (e) {
      debugPrint('register failed: $e');
    }
  }

  /// 会場ビルドの初回起動だけ、見守りリストに3人入れておく。
  ///
  /// 空のリストだと「安否が家族に自動で届く」という肝心のところが見えない。
  /// かといって触る人に開発者向けの画面を辿らせるわけにもいかないので、
  /// 起動時に一度だけ入れる。作られるのは Firestore の本物のドキュメントで、
  /// 画面は通常どおり API 経由で読む(モックモードではない)。
  Future<void> _seedKioskFriends(LatLng here) async {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool('kioskSeeded') ?? false) return;
    try {
      await ref.read(apiProvider).demoFriends('seed', lat: here.latitude, lng: here.longitude);
      await sp.setBool('kioskSeeded', true);
    } catch (e) {
      // 入らなくても平時の画面は成立する。記録だけ残して次の起動でまた試す。
      debugPrint('kiosk seed failed: $e');
    }
  }

  Future<void> _bootstrap() async {
    Notifications.onOpenAlert = _handleAlert;
    // 合流に誘われた通知を開いたら、ホームで旗の所まで寄せる。
    Notifications.onOpenMeetup = () {
      if (!mounted) return;
      final m = ref.read(meetupProvider);
      if (m != null) ref.read(mapFocusProvider.notifier).state = m.point;
      ref.read(selectedTabProvider.notifier).state = 0;
      setState(() => _started = true);
    };

    // 通知の初期化を待たない。iOS シミュレータ(APNs なし)では
    // FirebaseMessaging.getInitialMessage() が返らないことがあり、以前はここで
    // 起動処理ごと止まって、招待コードの払い出しもアラートの購読も動いていなかった。
    // 先に登録だけ済ませ、トークンは取れた時点で追記する(登録は upsert)。
    await _register(null);
    unawaited(Notifications.init().then((t) {
      if (t != null) _register(t);
    }));
    // 自分の市区町村を把握して、その土地のトピックを購読する。
    // 座標はサーバーに預けず、コードだけを端末が持つ。
    final area = ref.read(myAreaProvider);
    await area.load();
    unawaited(ref.read(locationProvider.notifier).refresh().then((l) async {
      await area.update(l.point);
      if (AppConfig.kiosk) await _seedKioskFriends(l.point);
      return null;
    }).catchError((Object e) {
      debugPrint('area update failed: $e');
      return null;
    }));

    // Mirror new alerts from Firestore (works without push, e.g. iOS without APNs).
    final uid = FirebaseAuth.instance.currentUser?.uid;
    FirebaseFirestore.instance.collection('alerts').orderBy('createdAt', descending: true).limit(1).snapshots().listen((q) {
      if (q.docs.isEmpty) return;
      final d = q.docs.first;
      final data = d.data();
      final created = (data['createdAt'] as Timestamp?)?.toDate();
      if (created == null || DateTime.now().difference(created) > const Duration(minutes: 5)) return;
      final target = data['demoTargetUid'] as String?;
      if (target != null && target != uid) return;
      // その土地に出ていない警報では動かさない。関東の大雨で北海道の端末が
      // 鳴ると、肝心なときに通知を切られてしまう。対象が空なら全国向け(地震)。
      final codes = ((data['areaCodes'] as List?) ?? const []).map((e) => e.toString()).toList();
      if (target == null && !area.matches(codes)) return;
      if (_seenAlerts.add(d.id)) {
        Notifications.showLocalAlert(d.id, (data['title'] ?? '災害情報') as String);
        _handleAlert(d.id);
      }
    });
  }

  Future<void> _handleAlert(String alertId) async {
    if (!mounted) return;
    ref.read(selectedTabProvider.notifier).state = 0;
    setState(() => _started = true);
    rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    try {
      await ref.read(agentControllerProvider).runForAlert(alertId);
    } catch (e) {
      debugPrint('runAgent failed: $e');
      final ctx = rootNavigatorKey.currentContext;
      showSenaviToast(userMessage(e, action: 'セナヴィに接続'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ヒナミチ',
      debugShowCheckedModeBanner: false,
      theme: hinaTheme(),
      navigatorKey: rootNavigatorKey,
      home: _started
          ? Scaffold(
              body: IndexedStack(index: ref.watch(selectedTabProvider), children: const [HomePage(), MapPage(), FriendsPage(), SettingsPage()]),
              bottomNavigationBar: NavigationBar(
                selectedIndex: ref.watch(selectedTabProvider),
                onDestinationSelected: (i) => ref.read(selectedTabProvider.notifier).state = i,
                backgroundColor: HinaColors.surface,
                indicatorColor: HinaColors.mist,
                destinations: [
                  _tab(HinaIcon.home, 'ホーム'),
                  _tab(HinaIcon.map, '近隣情報'),
                  _tab(HinaIcon.friends, '友だち'),
                  _tab(HinaIcon.settings, '設定'),
                ],
              ),
            )
          : SplashPage(onStart: () => setState(() => _started = true)),
    );
  }
}

/// デザイン書のアイコンセット(§17.3 の 4 タブ)。選択中は sky + 塗り。
NavigationDestination _tab(HinaIcon icon, String label) => NavigationDestination(
      icon: HinaIconView(icon, size: 24, color: HinaColors.inkSub),
      selectedIcon: HinaIconView(icon, size: 24, color: HinaColors.sky, filled: true),
      label: label,
    );
