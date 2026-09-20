import 'package:flutter/material.dart';
import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';

// ---------------------------------------------------------------- HinaButton
enum HinaButtonKind { primary, secondary, danger, ghost }

/// Pill button. primary = sun / ink text, secondary = white + line, danger = alert, ghost = text only.
class HinaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final HinaButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;
  const HinaButton(this.label, {super.key, this.onPressed, this.kind = HinaButtonKind.primary, this.icon, this.loading = false, this.expand = true});
  const HinaButton.primary(this.label, {super.key, this.onPressed, this.icon, this.loading = false, this.expand = true}) : kind = HinaButtonKind.primary;
  const HinaButton.secondary(this.label, {super.key, this.onPressed, this.icon, this.loading = false, this.expand = true}) : kind = HinaButtonKind.secondary;
  const HinaButton.danger(this.label, {super.key, this.onPressed, this.icon, this.loading = false, this.expand = true}) : kind = HinaButtonKind.danger;
  const HinaButton.ghost(this.label, {super.key, this.onPressed, this.icon, this.loading = false, this.expand = true}) : kind = HinaButtonKind.ghost;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      HinaButtonKind.primary => (HinaColors.sun, HinaColors.ink, Colors.transparent),
      HinaButtonKind.secondary => (HinaColors.surface, HinaColors.ink, HinaColors.line),
      HinaButtonKind.danger => (HinaColors.alert, Colors.white, Colors.transparent),
      HinaButtonKind.ghost => (Colors.transparent, HinaColors.inkSub, Colors.transparent),
    };
    final child = loading
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
            Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: 16)),
          ]);
    final btn = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        disabledBackgroundColor: bg.withOpacity(kind == HinaButtonKind.ghost ? 0 : 0.5),
        foregroundColor: fg,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HinaRadius.button), side: BorderSide(color: border)),
        elevation: 0,
      ),
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

// ---------------------------------------------------------------- StatusChip
Color statusColor(PublicStatus s) => switch (s) {
      PublicStatus.safe => HinaColors.stSafe,
      PublicStatus.assessing => HinaColors.stAssessing,
      PublicStatus.evacuating => HinaColors.stEvacuating,
      PublicStatus.arrived || PublicStatus.safeZone => HinaColors.stArrived,
      PublicStatus.unknown => HinaColors.stUnknown,
    };

class StatusChip extends StatelessWidget {
  final PublicStatus state;
  final bool compact;
  const StatusChip(this.state, {super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(state);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(color: c.withOpacity(0.14), borderRadius: BorderRadius.circular(HinaRadius.chip)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(state.label, style: TextStyle(fontSize: compact ? 12 : 13, fontWeight: FontWeight.w700, color: HinaColors.ink)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- HinaCard
class HinaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final VoidCallback? onTap;
  const HinaCard({super.key, required this.child, this.padding = const EdgeInsets.all(HinaSpace.m), this.color = HinaColors.surface, this.onTap});
  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(HinaRadius.card), boxShadow: HinaShadow.card),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(HinaRadius.card), onTap: onTap, child: card));
  }
}

// ---------------------------------------------------------------- HinaTag
class HinaTag extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  const HinaTag(this.label, {super.key, this.color, this.icon});
  @override
  Widget build(BuildContext context) {
    final c = color ?? HinaColors.sky;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: HinaColors.ink.withOpacity(0.85))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- SectionHeader
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.m, HinaSpace.m, HinaSpace.s),
        child: Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)), if (trailing != null) trailing!]),
      );
}

// ---------------------------------------------------------------- DemoBand
class DemoBand extends StatelessWidget {
  final String text;
  const DemoBand({super.key, this.text = 'DEMO モード — 災害の発生だけを再現しています(判断・避難所・経路は実データ)'});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: HinaColors.demoBand,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          const Icon(Icons.science_outlined, size: 16, color: HinaColors.ink),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: HinaColors.ink), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      );
}
