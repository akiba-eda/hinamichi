import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/senavi.dart';
import '../../features/settings/manual_location_sheet.dart';
import '../../state/providers.dart';
import '../atoms/atoms.dart';
import '../molecules/molecules.dart';

/// 位置が取れないときに、ホームとマップの代わりに出す画面。
/// 地図もセナヴィの判断も出さない ── 場所が分からないまま描くと嘘になる。
class LocationUnavailableView extends ConsumerStatefulWidget {
  const LocationUnavailableView({super.key});
  @override
  ConsumerState<LocationUnavailableView> createState() => LocationUnavailableViewState();
}

class LocationUnavailableViewState extends ConsumerState<LocationUnavailableView> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await ref.read(locationProvider.notifier).refresh();
    } catch (_) {
      // 取れなければ画面はそのまま。何度でも押せる。
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SenaviAvatar(SenaviMood.troubled, size: 96),
            const SizedBox(height: 16),
            Text('位置が取得できません', style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'いまいる場所が分からないと、近くの避難所もハザードも調べられません。\n窓の近くでもう一度試すか、仮の現在地を入れてください。',
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            HinaButton.primary('もう一度試す', loading: _retrying, onPressed: _retrying ? null : _retry),
            const SizedBox(height: 8),
            HinaButton.secondary('仮の現在地を入力する', onPressed: _retrying ? null : () => showManualLocationSheet(context, ref)),
          ]),
        ),
      ),
    );
  }
}
