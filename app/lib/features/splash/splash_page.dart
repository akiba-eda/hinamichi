import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme/hina_theme.dart';
import '../../ui/atoms/atoms.dart';

/// 01 スプラッシュ(デザイン書 シート2)。
///
/// ロゴ・キャッチコピー・セナヴィまで一枚絵に焼き込まれているので、画面側は
/// 全面に敷いて「はじめる」を重ねるだけ。絵は 870x1808(アスペクト 0.481)で、
/// 端末(iPhone 17 Pro は 0.460)とはわずかにずれる。cover で左右を 2% ほど
/// 切る側に倒している ── ロゴもセナヴィも中央付近にあるので欠けない。
class SplashPage extends StatelessWidget {
  final VoidCallback onStart;
  const SplashPage({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 絵が読めないときでも「はじめる」が押せるよう、空の色を敷いておく。
      backgroundColor: const Color(0xFFBBD3EA),
      body: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/brand/splash.png', fit: BoxFit.cover, alignment: Alignment.center),
        SafeArea(
          child: Column(children: [
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(HinaSpace.l, 0, HinaSpace.l, HinaSpace.l),
              child: HinaButton.secondary('はじめる', onPressed: onStart)
                  .animate()
                  .fadeIn(delay: 500.ms, duration: 600.ms)
                  .slideY(begin: 0.30, end: 0, curve: Curves.easeOutCubic),
            ),
          ]),
        ),
      ]),
    );
  }
}
