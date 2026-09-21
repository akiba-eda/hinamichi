import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/social.dart';
import '../../mock/mock_backend.dart';
import '../../state/providers.dart';
import '../atoms/atoms.dart';

/// 進行中の合流。
///
/// ホームと友だちタブの両方に出す。**押したら地点へ寄るのではなく、
/// ホームに道案内が出ている前提**にしてある ── 旗だけ立てて放り出すと、
/// 「で、どう行くの」が残る。
class MeetupBanner extends ConsumerStatefulWidget {
  final Meetup meetup;

  /// ホームでは自分が今そこにいるので、寄せ直す動きは要らない。
  final bool focusOnTap;
  const MeetupBanner({super.key, required this.meetup, this.focusOnTap = true});

  @override
  ConsumerState<MeetupBanner> createState() => _MeetupBannerState();
}

class _MeetupBannerState extends ConsumerState<MeetupBanner> {
  bool _leaving = false;

  /// 合流から抜ける。以前は Future を投げっぱなしで、403 や通信断でも
  /// 成功したように見えていた。失敗したことは押した人に見せる。
  Future<void> _leave() async {
    setState(() => _leaving = true);
    try {
      if (ref.read(mockModeProvider)) {
        ref.read(mockBackendProvider.notifier).endMeetup();
      } else {
        await ref.read(apiProvider).leaveMeetup(widget.meetup.id);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('合流から抜けられませんでした: $e')));
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meetup = widget.meetup;
    final focusOnTap = widget.focusOnTap;
    final t = Theme.of(context).textTheme;
    final here = ref.watch(locationProvider)?.point;
    final others = ref.watch(meetupMemberEtasProvider);
    final route = ref.watch(meetupRouteProvider).value;
    // 経路が引けたらその道のりで、駄目なら直線の目安で。
    // 避難時と同じ順序(実測 → 取れなければ直線)に揃えてある。
    final min = route != null ? (route.durationS / 60).ceil() : (here == null ? null : Meetup.walkMinutes(here, meetup.point));
    final c = meetup.fromIncident ? HinaColors.alert : HinaColors.stArrived;

    // 地図の上に置くので背景は不透明にする。透かすと下の地名が文字に重なって
    // 読めない。色は左の帯とアイコンだけで出し、平時(紫)と災害時(赤)を分ける。
    return Container(
      decoration: BoxDecoration(
        color: HinaColors.surface,
        borderRadius: BorderRadius.circular(HinaRadius.card),
        boxShadow: HinaShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: !focusOnTap
              ? null
              : () {
                  ref.read(mapFocusProvider.notifier).state = meetup.point;
                  ref.read(selectedTabProvider.notifier).state = 0;
                },
          child: IntrinsicHeight(
            child: Row(children: [
              Container(width: 4, color: c),
              const SizedBox(width: 12),
              Icon(Icons.handshake_outlined, color: c),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(meetup.fromIncident ? '避難先で合流' : '待ち合わせ中', style: t.bodySmall),
                    Text(meetup.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (min != null)
                      Text(
                        route != null ? 'あなた 徒歩 $min分 (約${route.distanceM}m)' : 'あなた 徒歩 $min分 (直線の目安)',
                        style: t.bodySmall,
                      ),
                    // 位置を共有してくれている相手だけ。分からない相手は
                    // 勝手に埋めず、行ごと出さない。
                    if (others.isNotEmpty)
                      Text(
                        others.map((o) => '${o.name} 徒歩 ${o.walkMin}分').join(' / '),
                        style: t.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ]),
                ),
              ),
              TextButton(
                onPressed: _leaving ? null : _leave,
                child: _leaving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('抜ける'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
