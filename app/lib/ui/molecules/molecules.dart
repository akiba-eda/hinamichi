import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../atoms/atoms.dart';

// ---------------------------------------------------------------- SenaviAvatar
/// Expression image with a 200 ms cross-fade. Falls back to a drawn placeholder until assets arrive.
class SenaviAvatar extends StatelessWidget {
  final SenaviMood mood;
  final double size;
  const SenaviAvatar(this.mood, {super.key, this.size = 72});
  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: SizedBox(
        key: ValueKey(mood),
        width: size,
        height: size,
        child: ClipOval(
          child: Image.asset(mood.asset, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _Placeholder(mood: mood, size: size)),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final SenaviMood mood;
  final double size;
  const _Placeholder({required this.mood, required this.size});
  @override
  Widget build(BuildContext context) {
    final face = switch (mood) {
      SenaviMood.smile => '😊',
      SenaviMood.serious => '🐶',
      SenaviMood.surprised => '😮',
      SenaviMood.troubled => '😟',
      SenaviMood.running => '🏃',
      _ => '🐕',
    };
    return Container(
      color: HinaColors.sand,
      alignment: Alignment.center,
      child: Text(face, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

// ---------------------------------------------------------------- SenaviSpeech
/// The one recurring element: avatar + speech bubble (sand). Present on every screen.
class SenaviSpeech extends StatelessWidget {
  final SenaviMood mood;
  final String text;
  final String? sub;
  final double avatarSize;
  const SenaviSpeech({super.key, required this.mood, required this.text, this.sub, this.avatarSize = 64});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SenaviAvatar(mood, size: avatarSize),
      const SizedBox(width: 12),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: HinaColors.sand,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
            if (sub != null) ...[const SizedBox(height: 4), Text(sub!, style: t.bodySmall)],
          ]),
        ),
      ),
    ]).animate(key: ValueKey(text)).fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0, duration: 250.ms);
  }
}

// ---------------------------------------------------------------- ReasonChips / CrowdMeter
class ReasonChips extends StatelessWidget {
  final List<String> reasons;
  const ReasonChips(this.reasons, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 6,
        children: reasons.map((r) => Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: HinaColors.leaf, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(r, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HinaColors.ink)),
            ])).toList(),
      );
}

class CrowdMeter extends StatelessWidget {
  final int pct;
  const CrowdMeter(this.pct, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = pct < 50 ? HinaColors.leaf : (pct < 80 ? HinaColors.sun : HinaColors.alert);
    return Row(children: [
      Text('混雑', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(width: 8),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct / 100, minHeight: 6, backgroundColor: HinaColors.line, color: c))),
      const SizedBox(width: 8),
      Text('$pct%', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: HinaColors.ink)),
    ]);
  }
}

// ---------------------------------------------------------------- CountdownButton
/// Primary CTA with a thin ring that drains over [seconds]; fires [onTimeout] once when it reaches 0.
class CountdownButton extends StatefulWidget {
  final String label;
  final int seconds;
  final VoidCallback onTap;
  final VoidCallback onTimeout;
  final bool loading;
  const CountdownButton({super.key, required this.label, this.seconds = 30, required this.onTap, required this.onTimeout, this.loading = false});
  @override
  State<CountdownButton> createState() => _CountdownButtonState();
}

class _CountdownButtonState extends State<CountdownButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(seconds: widget.seconds))..forward();
  bool _fired = false;
  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_fired) {
        _fired = true;
        widget.onTimeout();
      }
    });
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final remain = (widget.seconds * (1 - _c.value)).ceil();
        return Stack(alignment: Alignment.center, children: [
          HinaButton.primary('${widget.label}  ($remain)', onPressed: widget.loading ? null : () { _fired = true; _c.stop(); widget.onTap(); }, loading: widget.loading),
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(HinaRadius.button),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FractionallySizedBox(widthFactor: 1 - _c.value, child: Container(height: 3, color: HinaColors.ink.withOpacity(0.55))),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- ShelterCard
class ShelterCard extends StatelessWidget {
  final ShelterInfo shelter;
  final List<String> reasons;
  final String? header;
  final int? remainingMin;
  final Widget? actions;
  final VoidCallback? onDetail;
  final bool compact;
  const ShelterCard({super.key, required this.shelter, required this.reasons, this.header, this.remainingMin, this.actions, this.onDetail, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return HinaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (header != null) ...[
          Row(children: [
            Container(width: 22, height: 22, decoration: const BoxDecoration(color: HinaColors.sun, shape: BoxShape.circle), child: const Icon(Icons.pets, size: 13, color: HinaColors.ink)),
            const SizedBox(width: 8),
            Text(header!, style: t.bodySmall?.copyWith(color: HinaColors.ink, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
        ],
        InkWell(
          onTap: onDetail,
          child: Row(children: [
            const Icon(Icons.location_on, color: HinaColors.sky, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shelter.name, style: compact ? t.titleMedium : t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(remainingMin != null ? 'あと約$remainingMin分 (${shelter.distanceM}m)' : '徒歩 ${shelter.walkMin}分 (約${shelter.distanceM}m)', style: t.bodySmall),
            ])),
            if (onDetail != null) const Icon(Icons.chevron_right, color: HinaColors.inkSub),
          ]),
        ),
        if (!compact) ...[const SizedBox(height: 10), ReasonChips(reasons), const SizedBox(height: 10), CrowdMeter(shelter.crowdPct)],
        if (actions != null) ...[const SizedBox(height: 14), actions!],
      ]),
    );
  }
}

// ---------------------------------------------------------------- FriendTile
class FriendTile extends StatelessWidget {
  final FriendEntry friend;
  final FriendStatus status;
  final ValueChanged<bool>? onAutoShare;
  const FriendTile({super.key, required this.friend, required this.status, this.onAutoShare});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final time = status.updatedAt == null ? '' : '${status.updatedAt!.hour.toString().padLeft(2, '0')}:${status.updatedAt!.minute.toString().padLeft(2, '0')}';
    final sub = status.shelterName ?? status.note ?? (status.state == PublicStatus.unknown ? '応答なし' : '');
    return ListTile(
      leading: CircleAvatar(backgroundColor: statusColor(status.state).withOpacity(0.18), child: Text(friend.displayName.characters.first, style: const TextStyle(fontWeight: FontWeight.w700, color: HinaColors.ink))),
      title: Row(children: [
        Flexible(child: Text(friend.relation != null ? '${friend.displayName}(${friend.relation})' : friend.displayName, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        StatusChip(status.state, compact: true),
      ]),
      subtitle: sub.isEmpty ? null : Text(sub, style: t.bodySmall),
      trailing: Text(time, style: t.bodySmall),
    );
  }
}

// ---------------------------------------------------------------- AlertBanner
class AlertBanner extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  const AlertBanner({super.key, required this.title, this.subtitle, this.onClose});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: HinaColors.alert, borderRadius: BorderRadius.circular(14), boxShadow: HinaShadow.card),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.bodyLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (subtitle != null) Text(subtitle!, style: t.bodySmall?.copyWith(color: Colors.white.withOpacity(0.9))),
        ])),
        if (onClose != null) IconButton(onPressed: onClose, icon: const Icon(Icons.close, color: Colors.white, size: 20)),
      ]),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.2, end: 0);
  }
}

// ---------------------------------------------------------------- AgentLogTile
class AgentLogTile extends StatefulWidget {
  final AgentLogEntry e;
  const AgentLogTile(this.e, {super.key});
  @override
  State<AgentLogTile> createState() => _AgentLogTileState();
}

class _AgentLogTileState extends State<AgentLogTile> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    final t = Theme.of(context).textTheme;
    final (icon, color) = switch (e.kind) {
      LogKind.toolCall || LogKind.toolResult => (Icons.build_circle_outlined, HinaColors.sky),
      LogKind.llmRequest => (Icons.upload_file_outlined, HinaColors.stArrived),
      LogKind.llmResponse => (Icons.psychology_alt_outlined, HinaColors.leaf),
      LogKind.validator => (Icons.verified_user_outlined, HinaColors.alert),
      LogKind.fallback => (Icons.shield_moon_outlined, HinaColors.stEvacuating),
      LogKind.action || LogKind.approval => (Icons.touch_app_outlined, HinaColors.sun),
      LogKind.cost => (Icons.payments_outlined, HinaColors.inkSub),
      LogKind.info => (Icons.info_outline, HinaColors.inkSub),
    };
    final time = '${e.at.toLocal().hour.toString().padLeft(2, '0')}:${e.at.toLocal().minute.toString().padLeft(2, '0')}:${e.at.toLocal().second.toString().padLeft(2, '0')}';
    final metaBits = <String>[
      if (e.model != null) e.model!,
      if (e.router != null) 'router=${e.router}',
      if ((e.fallbackLevel ?? 0) > 0) 'fallback L${e.fallbackLevel}',
      if (e.sessionTier != null) 'tier=${e.sessionTier}',
      if (e.promptRef != null) 'prompt=${e.promptRef}',
      if (e.latencyMs != null) '${e.latencyMs}ms',
      if (e.costUsd != null && e.costUsd! > 0) '\$${e.costUsd!.toStringAsFixed(5)}',
      if (e.chosenBy != null) (e.chosenBy == 'llm' ? 'AIが選択' : 'システム補完'),
    ];
    return InkWell(
      onTap: () => setState(() => open = !open),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withOpacity(0.14), shape: BoxShape.circle), child: Icon(icon, size: 18, color: color)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(time, style: t.bodySmall?.copyWith(fontSize: 11)),
              Text(e.title, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (e.detail != null) Text(e.detail!, style: t.bodySmall, maxLines: open ? null : 2, overflow: open ? null : TextOverflow.ellipsis),
              if (metaBits.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 6, runSpacing: 4, children: metaBits.map((m) => HinaTag(m, color: HinaColors.inkSub)).toList())),
            ])),
            Icon(open ? Icons.expand_less : Icons.chevron_right, color: HinaColors.inkSub),
          ]),
          if (open && e.payload != null)
            Container(
              margin: const EdgeInsets.only(top: 8, left: 42),
              padding: const EdgeInsets.all(10),
              width: double.infinity,
              decoration: BoxDecoration(color: HinaColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: HinaColors.line)),
              child: SelectableText(_pretty(e.payload), style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: HinaColors.ink)),
            ),
        ]),
      ),
    );
  }

  static String _pretty(Object? o, [int indent = 0]) {
    final pad = '  ' * indent;
    if (o is Map) return o.entries.map((e) => '$pad${e.key}: ${e.value is Map || e.value is List ? '\n${_pretty(e.value, indent + 1)}' : e.value}').join('\n');
    if (o is List) return o.map((e) => e is Map || e is List ? _pretty(e, indent + 1) : '$pad- $e').join('\n');
    return '$pad$o';
  }
}

// ---------------------------------------------------------------- RerouteToast
void showRerouteToast(BuildContext context, String text) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: HinaCard(child: SenaviSpeech(mood: SenaviMood.surprised, text: text, avatarSize: 44)).animate().slideY(begin: -0.6, end: 0, duration: 350.ms, curve: Curves.easeOutBack).fadeIn(),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(const Duration(seconds: 4), () => entry.remove());
}

// ---------------------------------------------------------------- HazardLegend
class HazardLegend extends StatelessWidget {
  final bool flood, tsunami, landslide;
  const HazardLegend({super.key, this.flood = true, this.tsunami = false, this.landslide = false});
  @override
  Widget build(BuildContext context) {
    Widget row(Color c, String s) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: c.withOpacity(0.6), borderRadius: BorderRadius.circular(3))), const SizedBox(width: 6), Text(s, style: const TextStyle(fontSize: 11, color: HinaColors.ink))]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: HinaColors.surface.withOpacity(0.92), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (flood) row(HinaColors.hzFlood, '浸水想定'),
        if (tsunami) row(HinaColors.hzTsunami, '津波浸水想定'),
        if (landslide) row(HinaColors.hzLandslide, '土砂災害警戒'),
        const Text('地理院タイル / ハザードマップポータル', style: TextStyle(fontSize: 9, color: HinaColors.inkSub)),
      ]),
    );
  }
}
