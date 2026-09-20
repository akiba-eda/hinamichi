import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/hina_colors.dart';
import '../../domain/senavi.dart';

/// プロフィールのアイコン。
///
/// 中身は 3 通りで、この 1 つの部品に閉じ込めてある:
///   1. 自分で選んだ画像(縮小して base64 で users/{uid} に入れる)
///   2. セナヴィの表情から選んだもの
///   3. どちらも無ければ名前の頭文字
///
/// 画像は Firestore のドキュメントに直接入れる。256px / JPEG に落としてあるので
/// 10KB 程度で、1MB のドキュメント上限に対して十分小さい。Storage を足さずに
/// 済むぶん、無料枠の構成を崩さない。
class HinaAvatar extends StatelessWidget {
  /// base64 の画像(data URI ではなく素の base64)。
  final String? imageBase64;

  /// セナヴィの表情名(SenaviMood.name)。
  final String? moodName;

  /// 1 と 2 が無いときに出す頭文字の元。
  final String? fallbackName;

  final double size;
  final Color? ringColor;

  const HinaAvatar({super.key, this.imageBase64, this.moodName, this.fallbackName, this.size = 48, this.ringColor});

  static Uint8List? decode(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null; // 壊れた値で画面ごと落とさない
    }
  }

  SenaviMood? get _mood {
    if (moodName == null) return null;
    for (final m in SenaviMood.values) {
      if (m.name == moodName) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ring = ringColor ?? HinaColors.line;
    final bytes = decode(imageBase64);
    final mood = _mood;

    Widget inner;
    if (bytes != null) {
      inner = Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (mood != null) {
      inner = Image.asset(mood.asset, width: size, height: size, fit: BoxFit.cover);
    } else {
      inner = ColoredBox(
        color: ring.withValues(alpha: 0.18),
        child: Center(
          child: Text(
            (fallbackName?.isNotEmpty ?? false) ? fallbackName!.characters.first : '?',
            style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: HinaColors.ink),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
      child: ClipOval(child: SizedBox(width: size, height: size, child: inner)),
    );
  }
}
