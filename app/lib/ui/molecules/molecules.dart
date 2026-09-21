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
///
/// アセットはデザイン書から切り出した全身の透過 PNG。円形に切ると耳と前足が
/// 落ちるので、そのまま contain で収める。
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
        child: Image.asset(mood.asset, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _Placeholder(mood: mood, size: size)),
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

/// 混雑バー。
///
/// この数字は**ヒナミチでその避難場所に向かっている人の割合**で、実際の
/// 避難所の収容状況ではない(自治体の開設情報との連携は Phase 2)。
/// 誤解されると避難判断を誤らせるので、出所は設定の「データについて」に
/// まとめてある。画面ごとに注釈を足すと、説明文ばかりになって本文が読まれない。
class CrowdMeter extends StatelessWidget {
  final int pct;
  const CrowdMeter(this.pct, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = pct < 50 ? HinaColors.leaf : (pct < 80 ? HinaColors.sun : HinaColors.alert);
    final bar = Row(children: [
      Text('混雑', style: t.bodySmall),
      const SizedBox(width: 8),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct / 100, minHeight: 6, backgroundColor: HinaColors.line, color: c))),
      const SizedBox(width: 8),
      Text('$pct%', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: HinaColors.ink)),
    ]);
    return bar;
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
/// 見守りリストの 1 行。アイコンと名前だけ。
///
/// 一覧では情報を足さない。安否・メモ・電池・最終位置は全部タップした先で出す。
/// 平時に開くことの方が多い画面なので、5 人並んでも圧が無いことを優先した。
/// 状態はアイコン右下の小さな点だけで表す(LINE のオンライン表示と同じ扱い)。
///
/// 安否そのものは相手を承認した時点で自動的に届く ── それがこのアプリの目的
/// なので、相手ごとに切る設定は置かない。選べるのは位置を見せるかどうかだけで、
/// それも詳細側にある。
class FriendTile extends StatelessWidget {
  final FriendEntry friend;
  final FriendStatus status;
  final FriendLocation? location;
  final VoidCallback? onTap;
  const FriendTile({super.key, required this.friend, required this.status, this.location, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = statusColor(status.state);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m, vertical: 10),
        child: Row(children: [
          Stack(children: [
            HinaAvatar(
              imageBase64: friend.avatarImage,
              moodName: friend.avatarMood,
              fallbackName: friend.displayName,
              size: 48,
              ringColor: HinaColors.line,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: HinaColors.surface, width: 2.5)),
              ),
            ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              friend.relation != null ? '${friend.displayName}(${friend.relation})' : friend.displayName,
              style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: HinaColors.inkSub),
        ]),
      ),
    );
  }
}

/// 旧レイアウト(状態・位置・トグルを一覧に出す版)。Widget ギャラリーで
/// 見比べるために残してある。画面からは使っていない。
class FriendTileDetailed extends StatelessWidget {
  final FriendEntry friend;
  final FriendStatus status;
  final FriendLocation? location;
  final ValueChanged<bool>? onShareLocation;
  final VoidCallback? onTap;
  const FriendTileDetailed({super.key, required this.friend, required this.status, this.location, this.onShareLocation, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = statusColor(status.state);
    final time = status.updatedAt == null ? '' : '${status.updatedAt!.hour.toString().padLeft(2, '0')}:${status.updatedAt!.minute.toString().padLeft(2, '0')}';
    final place = status.shelterName ?? status.note;

    return Container(
      margin: const EdgeInsets.fromLTRB(HinaSpace.m, 0, HinaSpace.m, 10),
      decoration: BoxDecoration(color: HinaColors.surface, borderRadius: BorderRadius.circular(HinaRadius.card), boxShadow: HinaShadow.card),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 状態色の帯。一覧を流し見したときに、色だけで安否が拾える。
          Container(width: 5, color: c),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    HinaAvatar(
                      imageBase64: friend.avatarImage,
                      moodName: friend.avatarMood,
                      fallbackName: friend.displayName,
                      size: 46,
                      ringColor: c,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(
                            child: Text(
                              friend.relation != null ? '${friend.displayName}(${friend.relation})' : friend.displayName,
                              style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusChip(status.state, compact: true),
                        ]),
                        if (place != null && place.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            HinaIconView(status.shelterName != null ? HinaIcon.shelter : HinaIcon.home, size: 15, color: HinaColors.inkSub),
                            const SizedBox(width: 5),
                            Flexible(child: Text(place, style: t.bodySmall, overflow: TextOverflow.ellipsis)),
                          ]),
                        ],
                        if (location != null) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            HinaIconView(HinaIcon.locate, size: 15, color: location!.isStale ? HinaColors.stUnknown : HinaColors.sky),
                            const SizedBox(width: 5),
                            // 鮮度は名前と同じ強さで出す。古い位置を現在地と
                            // 読み違えるのが、この画面でいちばん危ない。
                            Text('${location!.ageLabel}の位置',
                                style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: location!.isStale ? HinaColors.stUnknown : HinaColors.ink)),
                            if (location!.batteryPct != null) ...[
                              const SizedBox(width: 10),
                              Text('電池 ${location!.batteryPct}%',
                                  style: t.bodySmall?.copyWith(color: location!.batteryPct! <= 15 ? HinaColors.alert : HinaColors.inkSub)),
                            ],
                          ]),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 6),
                    Column(children: [
                      Text(time, style: t.bodySmall),
                      if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: HinaColors.inkSub),
                    ]),
                  ]),
                  if (onShareLocation != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
                      decoration: BoxDecoration(color: HinaColors.mist.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(HinaRadius.chip)),
                      child: Row(children: [
                        Expanded(child: Text('この人に現在地を見せる', style: t.bodySmall?.copyWith(fontWeight: friend.shareLocation ? FontWeight.w700 : null, color: HinaColors.ink))),
                        Switch(value: friend.shareLocation, onChanged: onShareLocation),
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- AlertBanner
/// 03「災害発生時」の検知カード(デザイン書 シート3)。
///
/// 設計書 §17.5 のとおり別画面にはせず、Home の地図の上に重ねる。見た目だけ
/// デザイン書に合わせて、アイコンを白丸に載せた 2 行構成にしている。
class AlertBanner extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  const AlertBanner({super.key, required this.title, this.subtitle, this.onClose});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(color: HinaColors.alert, borderRadius: BorderRadius.circular(16), boxShadow: HinaShadow.card),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
          child: const HinaIconView(HinaIcon.warning, size: 21, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.bodyLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.35), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.95))),
            ],
          ]),
        ),
        if (onClose != null)
          GestureDetector(onTap: onClose, child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.close, color: Colors.white, size: 20))),
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

// ---------------------------------------------------------------- DisasterTypeSelector
/// 地図に重ねるハザードを切り替えるピル(ホームとマップで共用)。
class DisasterTypeSelector extends StatelessWidget {
  final DisasterType selected;
  final ValueChanged<DisasterType> onChanged;
  static const types = [DisasterType.earthquake, DisasterType.flood, DisasterType.tsunami];
  const DisasterTypeSelector({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: HinaColors.surface, borderRadius: BorderRadius.circular(22), boxShadow: HinaShadow.card),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final d in types)
            GestureDetector(
              onTap: () => onChanged(d),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: selected == d ? HinaColors.mist : Colors.transparent, borderRadius: BorderRadius.circular(18)),
                child: Text(d.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected == d ? HinaColors.ink : HinaColors.inkSub)),
              ),
            ),
        ]),
      );
}

// ---------------------------------------------------------------- RainLegend
/// 雨雲レーダーの凡例。
///
/// 観測時刻を必ず添える ── 雨雲は5分で変わるので、「いつの雨か」が分からない
/// 絵は判断材料にならない。
class RainLegend extends StatelessWidget {
  final DateTime? at;
  const RainLegend({super.key, this.at});

  /// 気象庁の降水強度の凡例(弱い方から4段階ぶんだけ。強い雨は稀なので畳む)。
  static const _steps = <(Color, String)>[
    (Color(0xFFA0D2FF), '1〜5mm/h'),
    (Color(0xFF218CFF), '5〜10'),
    (Color(0xFF0041FF), '10〜20'),
    (Color(0xFFFAF500), '20〜30'),
    (Color(0xFFFF9900), '30〜50'),
    (Color(0xFFFF2800), '50〜'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = at?.toLocal();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: HinaColors.surface.withOpacity(0.92), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(
          t == null ? '雨雲 読み込み中' : '雨雲 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} 現在',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: HinaColors.ink),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (c, _) in _steps)
              Container(width: 13, height: 10, color: c.withOpacity(0.7)),
          ],
        ),
        const SizedBox(height: 2),
        const Text('弱い　　　　　　強い', style: TextStyle(fontSize: 9, color: HinaColors.inkSub)),
        const Text('高解像度降水ナウキャスト(気象庁)', style: TextStyle(fontSize: 9, color: HinaColors.inkSub)),
      ]),
    );
  }
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
