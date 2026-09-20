import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/hina_colors.dart';

/// デザイン書のアイコンセット(シート2「デザインシステム / アイコン」)。
///
/// Material のアイコンは線が硬く、デザイン書の丸いストロークと並べると浮く。
/// 角を丸めた 2px ストロークで描き直したもの。24 グリッドで設計し、[size] に
/// 合わせて等倍スケールする。
enum HinaIcon { home, map, friends, settings, locate, warning, done, log, shelter, chat, battery }

class HinaIconView extends StatelessWidget {
  final HinaIcon icon;
  final double size;
  final Color color;

  /// 選択中のタブは線を太くして塗りを足す(デザイン書の選択状態)。
  final bool filled;
  const HinaIconView(this.icon, {super.key, this.size = 24, this.color = HinaColors.ink, this.filled = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _HinaIconPainter(icon, color, filled)),
      );
}

class _HinaIconPainter extends CustomPainter {
  final HinaIcon icon;
  final Color color;
  final bool filled;
  const _HinaIconPainter(this.icon, this.color, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24.0;
    canvas.save();
    canvas.scale(k);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = filled ? 2.1 : 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: filled ? 0.18 : 0.0);

    switch (icon) {
      case HinaIcon.home:
        final body = Path()
          ..moveTo(4, 10.4)
          ..lineTo(12, 4)
          ..lineTo(20, 10.4)
          ..lineTo(20, 19)
          ..arcToPoint(const Offset(18.4, 20.5), radius: const Radius.circular(1.6))
          ..lineTo(5.6, 20.5)
          ..arcToPoint(const Offset(4, 19), radius: const Radius.circular(1.6))
          ..close();
        canvas.drawPath(body, fill);
        canvas.drawPath(body, stroke);
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(10, 14, 4, 6.5), const Radius.circular(1.2)),
          stroke,
        );
      case HinaIcon.map:
        // 三つ折りの地図。山折り・谷折りで左右のパネルがずれる。
        final sheet = Path()
          ..moveTo(3.2, 7)
          ..lineTo(9, 4.6)
          ..lineTo(15, 7.4)
          ..lineTo(20.8, 5)
          ..lineTo(20.8, 17)
          ..lineTo(15, 19.4)
          ..lineTo(9, 16.6)
          ..lineTo(3.2, 19)
          ..close();
        canvas.drawPath(sheet, fill);
        canvas.drawPath(sheet, stroke);
        canvas.drawLine(const Offset(9, 4.6), const Offset(9, 16.6), stroke);
        canvas.drawLine(const Offset(15, 7.4), const Offset(15, 19.4), stroke);
      case HinaIcon.friends:
        // 手前の人と、肩越しに覗くもう一人。
        canvas.drawCircle(const Offset(9.6, 8.4), 3.1, stroke);
        final near = Path()
          ..moveTo(3.8, 19.6)
          ..arcToPoint(const Offset(15.4, 19.6), radius: const Radius.circular(5.9), clockwise: true);
        canvas.drawPath(near, stroke);
        canvas.drawArc(Rect.fromCircle(center: const Offset(16.4, 8.0), radius: 2.5), -1.25, 2.6, false, stroke);
        final far = Path()
          ..moveTo(16.2, 14.6)
          ..arcToPoint(const Offset(20.8, 18.6), radius: const Radius.circular(4.4), clockwise: true);
        canvas.drawPath(far, stroke);
      case HinaIcon.settings:
        // 歯車: 外周に 8 枚の歯を立て、中央に軸穴。
        const teeth = 8;
        const rIn = 6.4, rOut = 8.6;
        final gear = Path();
        for (var i = 0; i < teeth; i++) {
          final a0 = (i * 2 - 0.62) * math.pi / teeth;
          final a1 = (i * 2 + 0.62) * math.pi / teeth;
          final a2 = (i * 2 + 1.34) * math.pi / teeth;
          final a3 = (i * 2 + 2 - 1.34) * math.pi / teeth;
          Offset at(double a, double r) => Offset(12 + r * math.cos(a), 12 + r * math.sin(a));
          if (i == 0) gear.moveTo(at(a0, rOut).dx, at(a0, rOut).dy);
          gear.lineTo(at(a1, rOut).dx, at(a1, rOut).dy);
          gear.lineTo(at(a2, rIn).dx, at(a2, rIn).dy);
          gear.lineTo(at(a3, rIn).dx, at(a3, rIn).dy);
        }
        gear.close();
        canvas.drawPath(gear, fill);
        canvas.drawPath(gear, stroke);
        canvas.drawCircle(const Offset(12, 12), 2.7, stroke);
      case HinaIcon.locate:
        canvas.drawCircle(const Offset(12, 12), 4.2, stroke);
        canvas.drawCircle(const Offset(12, 12), 1.5, Paint()..color = color);
        for (final o in const [
          [Offset(12, 2.6), Offset(12, 5.6)],
          [Offset(12, 18.4), Offset(12, 21.4)],
          [Offset(2.6, 12), Offset(5.6, 12)],
          [Offset(18.4, 12), Offset(21.4, 12)],
        ]) {
          canvas.drawLine(o[0], o[1], stroke);
        }
      case HinaIcon.warning:
        final tri = Path()
          ..moveTo(12, 3.6)
          ..lineTo(21.4, 19.6)
          ..arcToPoint(const Offset(19.8, 21.2), radius: const Radius.circular(1.7))
          ..lineTo(4.2, 21.2)
          ..arcToPoint(const Offset(2.6, 19.6), radius: const Radius.circular(1.7))
          ..close();
        canvas.drawPath(tri, fill);
        canvas.drawPath(tri, stroke);
        canvas.drawLine(const Offset(12, 10), const Offset(12, 15), stroke);
        canvas.drawCircle(const Offset(12, 18), 0.95, Paint()..color = color);
      case HinaIcon.done:
        canvas.drawCircle(const Offset(12, 12), 8.6, fill);
        canvas.drawCircle(const Offset(12, 12), 8.6, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(8, 12.2)
            ..lineTo(11, 15.2)
            ..lineTo(16.2, 9),
          stroke,
        );
      case HinaIcon.log:
        // レシート状の記録。下端をギザギザにして「記録」と分かるように。
        final slip = Path()
          ..moveTo(5, 3.4)
          ..lineTo(19, 3.4)
          ..lineTo(19, 20.6)
          ..lineTo(16.5, 19)
          ..lineTo(14, 20.6)
          ..lineTo(11.5, 19)
          ..lineTo(9, 20.6)
          ..lineTo(6.5, 19)
          ..lineTo(5, 20.6)
          ..close();
        canvas.drawPath(slip, fill);
        canvas.drawPath(slip, stroke);
        canvas.drawLine(const Offset(8.4, 8.2), const Offset(15.6, 8.2), stroke);
        canvas.drawLine(const Offset(8.4, 12.2), const Offset(15.6, 12.2), stroke);
      case HinaIcon.shelter:
        final pin = Path()
          ..moveTo(12, 21.2)
          ..cubicTo(12, 21.2, 4.6, 14.6, 4.6, 9.8)
          ..arcToPoint(const Offset(19.4, 9.8), radius: const Radius.circular(7.4), clockwise: true)
          ..cubicTo(19.4, 14.6, 12, 21.2, 12, 21.2)
          ..close();
        canvas.drawPath(pin, fill);
        canvas.drawPath(pin, stroke);
        canvas.drawCircle(const Offset(12, 9.8), 2.6, stroke);
      case HinaIcon.battery:
        // 横向きの電池。残量は数値で隣に出すので、ここは器だけ描く。
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(2.6, 7.4, 16.4, 9.2), const Radius.circular(2.6)),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(19.6, 10.2, 2.2, 3.6), const Radius.circular(1.1)),
          Paint()..color = color,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(4.8, 9.6, 8.4, 4.8), const Radius.circular(1.2)),
          Paint()..color = color,
        );
      case HinaIcon.chat:
        final bubble = Path()
          ..moveTo(6.4, 4.2)
          ..lineTo(17.6, 4.2)
          ..arcToPoint(const Offset(20.4, 7), radius: const Radius.circular(2.8))
          ..lineTo(20.4, 14.2)
          ..arcToPoint(const Offset(17.6, 17), radius: const Radius.circular(2.8))
          ..lineTo(10.8, 17)
          ..lineTo(6.6, 20.4)
          ..lineTo(6.6, 17)
          ..arcToPoint(const Offset(3.6, 14.2), radius: const Radius.circular(2.8))
          ..lineTo(3.6, 7)
          ..arcToPoint(const Offset(6.4, 4.2), radius: const Radius.circular(2.8))
          ..close();
        canvas.drawPath(bubble, fill);
        canvas.drawPath(bubble, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HinaIconPainter old) => old.icon != icon || old.color != color || old.filled != filled;
}
