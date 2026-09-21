import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import 'meetup_sheet.dart';
import '../../domain/social.dart';
import '../../mock/mock_backend.dart';
import '../../ui/atoms/atoms.dart';
import 'chat_page.dart';

/// フレンドのアイコン / カードをタップしたときに出る詳細。
///
/// 見せるのは 3 つだけ:
///   1. いまの安否(5 段階)
///   2. 本人が書いた一言 ── 状態だけでは伝わらないことを本人の言葉で
///   3. 災害中なら向かっている避難場所
/// 位置は「いつの時点か」を必ず添える。
void showFriendDetail(BuildContext context, FriendOnMap f) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FriendDetail(f),
  );
}

class _FriendDetail extends ConsumerWidget {
  final FriendOnMap f;
  const _FriendDetail(this.f);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    // シートを開いたあとに状態が変わっても追従させる。
    final status = ref.watch(friendStatusProvider(f.entry.uid)).value ?? f.status;
    final loc = ref.watch(friendLocationProvider(f.entry.uid)).value ?? f.location;
    final c = statusColor(status.state);
    final name = f.entry.relation != null ? '${f.entry.displayName}(${f.entry.relation})' : f.entry.displayName;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(HinaSpace.s),
        padding: const EdgeInsets.all(HinaSpace.m),
        decoration: BoxDecoration(color: HinaColors.surface, borderRadius: BorderRadius.circular(HinaRadius.sheet), boxShadow: HinaShadow.card),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: HinaColors.line, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: HinaSpace.m),
          Row(children: [
            HinaAvatar(
              imageBase64: f.entry.avatarImage,
              moodName: f.entry.avatarMood,
              fallbackName: f.entry.displayName,
              size: 54,
              ringColor: c,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                StatusChip(status.state),
              ]),
            ),
          ]),

          // 本人の一言。この画面でいちばん読ませたいので大きく。
          const SizedBox(height: HinaSpace.m),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: HinaColors.sand.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(HinaRadius.card)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('本人からのメモ', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: HinaColors.ink)),
              const SizedBox(height: 6),
              Text(
                status.note?.isNotEmpty == true ? status.note! : 'メモはまだありません',
                style: status.note?.isNotEmpty == true ? t.bodyLarge : t.bodyMedium?.copyWith(color: HinaColors.inkSub),
              ),
            ]),
          ),

          // 災害中の行き先。平時は出さない。
          if (status.shelterName != null) ...[
            const SizedBox(height: 10),
            HinaCard(
              color: HinaColors.mist.withValues(alpha: 0.4),
              child: Row(children: [
                HinaIconView(HinaIcon.shelter, size: 26, color: HinaColors.sky),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(status.state == PublicStatus.arrived ? '到着した避難場所' : '向かっている避難場所', style: t.bodySmall),
                    Text(status.shelterName!, style: t.titleMedium),
                  ]),
                ),
                if (status.shelterPoint != null)
                  HinaButton.secondary('地図で見る', expand: false, onPressed: () => _focus(context, ref, status.shelterPoint!)),
              ]),
            ),
          ],

          const SizedBox(height: 10),
          // 最終ログイン / 最後にいた場所 / 電池。座標ではなく市区町村で読ませる。
          _Fact(
            icon: HinaIcon.done,
            label: '最終ログイン',
            value: loc.isOnline ? 'ログイン中' : '${loc.ageLabel} (${_hhmm(loc.at)})',
            emphasised: true,
            muted: loc.isStale,
          ),
          _Fact(
            icon: HinaIcon.locate,
            label: '最後にいた場所',
            value: loc.areaName ?? '取得できていません',
            emphasised: loc.areaName != null,
            muted: loc.isStale,
          ),
          if (loc.batteryPct != null)
            _Fact(
              icon: HinaIcon.battery,
              label: '電池',
              value: '${loc.batteryPct}%',
              emphasised: loc.batteryPct! <= 15,
              muted: false,
              danger: loc.batteryPct! <= 15,
            ),
          if (loc.isStale)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('しばらく更新がありません。表示は最後に受け取った情報です', style: t.bodySmall?.copyWith(color: HinaColors.stUnknown)),
            ),

          // 相手ごとの許可はここに置く。一覧はアイコンと名前だけに保つ。
          const SizedBox(height: HinaSpace.s),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
            decoration: BoxDecoration(color: HinaColors.mist.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(HinaRadius.chip)),
            child: Row(children: [
              Expanded(child: Text('この人に自分の現在地を見せる', style: t.bodySmall?.copyWith(fontWeight: f.entry.shareLocation ? FontWeight.w700 : null, color: HinaColors.ink))),
              Switch(
                value: f.entry.shareLocation,
                onChanged: (v) => ref.read(apiProvider).shareFriend(f.entry.uid, shareLocation: v),
              ),
            ]),
          ),

          // 文字を打たずに一言返せる経路。災害時にいちばん使われる想定。
          const SizedBox(height: HinaSpace.s),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final r in kReactions)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    backgroundColor: r.emoji == '🆘' ? HinaColors.alertBg : HinaColors.surface,
                    side: BorderSide(color: r.emoji == '🆘' ? HinaColors.alert : HinaColors.line),
                    label: Text('${r.emoji} ${r.label}', style: t.bodySmall),
                    onPressed: () {
                      if (ref.read(mockModeProvider)) {
                        ref.read(mockBackendProvider.notifier).send(f.entry.uid, reaction: r.emoji);
                      } else {
                        ref.read(apiProvider).sendMessage(toUid: f.entry.uid, reaction: r.emoji);
                      }
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r.emoji} を送りました')));
                    },
                  ),
                ),
            ]),
          ),

          const SizedBox(height: HinaSpace.s),
          Row(children: [
            Expanded(child: HinaButton.secondary('メッセージ', icon: Icons.chat_bubble_outline, onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(friend: f.entry)));
            })),
            const SizedBox(width: 8),
            Expanded(child: HinaButton.secondary('合流する', icon: Icons.handshake_outlined, onPressed: () => _openMeetup(context, ref))),
          ]),

          const SizedBox(height: HinaSpace.s),
          Row(children: [
            Expanded(child: HinaButton.secondary('地図で見る', icon: Icons.map_outlined, onPressed: loc.areaName == null && loc.at.millisecondsSinceEpoch == 0 ? null : () => _focus(context, ref, loc.point))),
            const SizedBox(width: 8),
            Expanded(child: HinaButton.primary('閉じる', onPressed: () => Navigator.of(context).pop())),
          ]),
        ]),
      ),
    );
  }

  /// 地図タブへ移ってから寄せる。「地図で見る」で今の画面に留まると
  /// 何が起きたか分からないので、タブごと切り替える。
  void _focus(BuildContext context, WidgetRef ref, LatLng p) {
    ref.read(mapFocusProvider.notifier).state = p;
    ref.read(selectedTabProvider.notifier).state = 1;
    Navigator.of(context).pop();
  }

  /// 合流の作成シートを開く。
  ///
  /// 以前はここで「相手のいる場所」に決め打ちして即作成していたが、
  /// 落ち合う場所も人数も選べず、災害時に避難所で落ち合うことが表現できなかった。
  /// 何を決めるかはシート側に寄せて、ここは開くだけにする。
  void _openMeetup(BuildContext context, WidgetRef ref) async {
    Navigator.of(context).pop();
    await showMeetupSheet(context, ref, initialFriendUid: f.entry.uid);
  }

  static String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 詳細の 1 行。アイコン・見出し・値。
class _Fact extends StatelessWidget {
  final HinaIcon icon;
  final String label, value;
  final bool emphasised, muted, danger;
  const _Fact({required this.icon, required this.label, required this.value, this.emphasised = false, this.muted = false, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = danger ? HinaColors.alert : (muted ? HinaColors.stUnknown : HinaColors.sky);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        HinaIconView(icon, size: 18, color: c),
        const SizedBox(width: 8),
        SizedBox(width: 108, child: Text(label, style: t.bodySmall)),
        Expanded(
          child: Text(
            value,
            style: emphasised
                ? t.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: danger ? HinaColors.alert : (muted ? HinaColors.stUnknown : HinaColors.ink))
                : t.bodyMedium?.copyWith(color: muted ? HinaColors.stUnknown : HinaColors.ink),
          ),
        ),
      ]),
    );
  }
}
