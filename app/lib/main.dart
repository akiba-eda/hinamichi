import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme/hina_colors.dart';
import 'app/theme/hina_theme.dart';
import 'core/notifications.dart';
import 'features/agent_log/agent_log_page.dart';
import 'features/friends/friends_page.dart';
import 'features/home/home_page.dart';
import 'features/settings/settings_page.dart';
import 'firebase_options.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
  runApp(const ProviderScope(child: HinamichiApp()));
}

class HinamichiApp extends ConsumerStatefulWidget {
  const HinamichiApp({super.key});
  @override
  ConsumerState<HinamichiApp> createState() => _HinamichiAppState();
}

class _HinamichiAppState extends ConsumerState<HinamichiApp> {
  final _navKey = GlobalKey<NavigatorState>();
  int tab = 0;
  final _seenAlerts = <String>{};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    Notifications.onOpenAlert = _handleAlert;
    final token = await Notifications.init();
    try {
      await ref.read(apiProvider).register(fcmToken: token, platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
    } catch (e) {
      debugPrint('register failed: $e');
    }
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
      if (_seenAlerts.add(d.id)) {
        Notifications.showLocalAlert(d.id, (data['title'] ?? '災害情報') as String);
        _handleAlert(d.id);
      }
    });
  }

  Future<void> _handleAlert(String alertId) async {
    if (!mounted) return;
    setState(() => tab = 0);
    _navKey.currentState?.popUntil((r) => r.isFirst);
    try {
      await ref.read(agentControllerProvider).runForAlert(alertId);
    } catch (e) {
      debugPrint('runAgent failed: $e');
      final ctx = _navKey.currentContext;
      if (ctx != null) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('セナヴィに接続できませんでした: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ヒナミチ',
      debugShowCheckedModeBanner: false,
      theme: hinaTheme(),
      navigatorKey: _navKey,
      home: Scaffold(
        body: IndexedStack(index: tab, children: const [HomePage(), FriendsPage(), AgentLogPage(), SettingsPage()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          backgroundColor: HinaColors.surface,
          indicatorColor: HinaColors.mist,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'ホーム'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: '友だち'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: '記録'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '設定'),
          ],
        ),
      ),
    );
  }
}
