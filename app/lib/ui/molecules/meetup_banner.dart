import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hina_colors.dart';
import '../../domain/social.dart';
import '../../mock/mock_backend.dart';
import '../../state/providers.dart';
import '../atoms/atoms.dart';

/// 進行中の合流。
///
/// ホームと友だちタブの両方に出す。**押したら地点へ寄るのではなく、
/// ホームに道案内が出ている前提**にしてある ── 旗だけ立てて放り出すと、
/// 「で、どう行くの」が残る。
class MeetupBanner extends ConsumerWidget {
  final Meetup meetup;

  /// ホームでは自分が今そこにいるので、寄せ直す動きは要らない。
  final bool focusOnTap;
  const MeetupBanner({super.key, required this.meetup, this.focusOnTap = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final here = ref.watch(locationProvider)?.point;
    final route = ref.watch(meetupRouteProvider).value;
    // 経路が引けたらその道のりで、駄目なら直線の目安で。
    // 避難時と同じ順序(実測 → 取れなければ直線)に揃えてある。
    final min = route != null ? (route.durationS / 60).ceil() : (here == null ? null : Meetup.walkMinutes(here, meetup.point));
    final c = meetup.fromIncident ? HinaColors.alert : HinaColors.stArrived;

    return HinaCard(
      color: c.withValues(alpha: 0.10),
      onTap: !focusOnTap
          ? null
          : () {
              ref.read(mapFocusProvider.notifier).state = meetup.point;
              ref.read(selectedTabProvider.notifier).state = 0;
            },
      child: Row(children: [
        Icon(Icons.handshake_outlined, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(meetup.fromIncident ? '避難先で合流' : '待ち合わせ中', style: t.bodySmall),
            Text(meetup.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (min != null)
              Text(
                route != null ? '徒歩 $min分 (約${route.distanceM}m)' : '徒歩 $min分 (直線の目安)',
                style: t.bodySmall,
              ),
          ]),
        ),
        TextButton(
          onPressed: () => ref.read(mockModeProvider)
              ? ref.read(mockBackendProvider.notifier).endMeetup()
              : ref.read(apiProvider).endMeetup(meetup.id),
          child: const Text('やめる'),
        ),
      ]),
    );
  }
}
