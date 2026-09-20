import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ブランドロゴ「ヒナミチ / -HINAMICHI-」(デザイン書 横組みロゴ)。
///
/// ビットマップではなく描画で組んでいる。デザイン書に載っているロゴ画像は
/// 135x50px しかなく、スプラッシュの大きさまで引き伸ばすと潰れるため。
/// 色はデザイン書から実測した値(文字 #1E3D5C / ピン #F59A1E)。
class HinaLogo extends StatelessWidget {
  /// 「ヒナミチ」の文字高。他の寸法はすべてこれに追従する。
  final double size;
  final Color color;
  final Color pinColor;

  /// 夕景の上に置くときは白抜きにする(スプラッシュ)。
  final bool light;
  const HinaLogo({super.key, this.size = 34, this.color = const Color(0xFF1E3D5C), this.pinColor = const Color(0xFFF59A1E), this.light = false});

  @override
  Widget build(BuildContext context) {
    final fg = light ? Colors.white : color;
    final title = GoogleFonts.notoSansJp(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: fg,
      letterSpacing: size * 0.20,
      height: 1.0,
    );
    final sub = GoogleFonts.notoSansJp(
      fontSize: size * 0.28,
      fontWeight: FontWeight.w500,
      color: fg.withValues(alpha: light ? 0.92 : 0.86),
      letterSpacing: size * 0.13,
      height: 1.0,
    );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // 末尾の letterSpacing のぶん右に余白が出るので、ピンはその上に重ねる。
      Stack(clipBehavior: Clip.none, children: [
        Padding(padding: EdgeInsets.only(right: size * 0.42), child: Text('ヒナミチ', style: title)),
        Positioned(
          right: 0,
          top: -size * 0.12,
          child: _Pin(size: size * 0.52, color: pinColor),
        ),
      ]),
      SizedBox(height: size * 0.04),
      SizedBox(
        width: size * 4.9,
        height: size * 0.30,
        child: CustomPaint(painter: _Swoosh(fg, size * 0.055)),
      ),
      SizedBox(height: size * 0.12),
      Text('- HINAMICHI -', style: sub),
    ]);
  }
}

/// ロゴの下をくぐる手書き風のはらい。ゆるく沈んでから、右端で跳ね上がる。
class _Swoosh extends CustomPainter {
  final Color color;
  final double weight;
  const _Swoosh(this.color, this.weight);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Path()
      ..moveTo(w * 0.015, h * 0.16)
      ..cubicTo(w * 0.20, h * 0.92, w * 0.50, h * 1.00, w * 0.72, h * 0.72)
      ..cubicTo(w * 0.86, h * 0.54, w * 0.94, h * 0.30, w * 0.995, h * 0.00);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = weight
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _Swoosh old) => old.color != color || old.weight != weight;
}

/// ロゴと地図マーカーで共用する雫型のピン。
class _Pin extends StatelessWidget {
  final double size;
  final Color color;
  const _Pin({required this.size, required this.color});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size * 1.32, child: CustomPaint(painter: _PinPainter(color)));
}

class _PinPainter extends CustomPainter {
  final Color color;
  const _PinPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = w / 2;
    final body = Path()
      ..moveTo(w / 2, h)
      ..cubicTo(w / 2 - r * 0.30, h * 0.66, 0, r * 1.45, 0, r)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r), clockwise: true)
      ..cubicTo(w, r * 1.45, w / 2 + r * 0.30, h * 0.66, w / 2, h)
      ..close();
    canvas.drawPath(body, Paint()..color = color);
    canvas.drawCircle(Offset(w / 2, r), r * 0.38, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PinPainter old) => old.color != color;
}
