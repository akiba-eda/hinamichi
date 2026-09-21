import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../mock/mock_backend.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';

/// 合流の候補地点。名前と座標だけあれば合流は作れる。
typedef _Spot = ({String key, String label, String note, LatLng point});

/// 合流を作るシート。「誰と」「どこで」を決める。
///
/// 以前は友だち1人・相手のいる場所に決め打ちで、地点も人数も選べなかった。
/// 避難所を選べるようにしたのは、災害時に「どこで落ち合うか」が本題になるから。
/// 任意の地点を地図から立てられるようにはしていない ── 浸水想定の中を
/// 選べてしまい、避難先を安全ルールで検算している意味が無くなる。
Future<bool> showMeetupSheet(BuildContext context, WidgetRef ref, {required String initialFriendUid}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MeetupSheet(initialFriendUid: initialFriendUid),
  );
  return ok ?? false;
}

class _MeetupSheet extends ConsumerStatefulWidget {
  final String initialFriendUid;
  const _MeetupSheet({required this.initialFriendUid});
  @override
  ConsumerState<_MeetupSheet> createState() => _MeetupSheetState();
}

class _MeetupSheetState extends ConsumerState<_MeetupSheet> {
  late final Set<String> _selected = {widget.initialFriendUid};
  String? _spotKey;
  bool _busy = false;

  /// 候補は「自分の避難先 → 近くの避難場所 → 相手のいる場所」の順。
  /// 災害中は避難先が本題なので先頭に出す。
  List<_Spot> _spots(List<FriendEntry> friends) {
    final out = <_Spot>[];
    final inc = ref.watch(activeIncidentProvider);
    final shelter = inc?.shelter;
    if (shelter != null) {
      out.add((key: 'mine', label: shelter.name, note: 'あなたの避難先・徒歩${shelter.walkMin}分', point: shelter.point));
    }
    for (final s in ref.watch(nearbyProvider).value?.shelters ?? const <ShelterInfo>[]) {
      if (shelter != null && s.id == shelter.id) continue;
      out.add((key: 'sh_${s.id}', label: s.name, note: '徒歩${s.walkMin}分${s.full ? '・満員' : ''}', point: s.point));
    }
    for (final f in friends) {
      if (!_selected.contains(f.uid)) continue;
      // 位置を共有してくれていない相手は座標が無い。候補に出せない。
      final loc = ref.watch(friendLocationProvider(f.uid)).value;
      if (loc == null) continue;
      out.add((key: 'fr_${f.uid}', label: '${f.displayName}さんのいる場所', note: '最後に受け取った位置', point: loc.point));
    }
    return out;
  }

  Future<void> _create(List<_Spot> spots) async {
    final spot = spots.where((s) => s.key == _spotKey).firstOrNull;
    if (spot == null || _selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      // 災害中に作った合流は、色と文言が「避難先で合流」に変わる。
      final fromIncident = ref.read(activeIncidentProvider) != null;
      if (ref.read(mockModeProvider)) {
        ref.read(mockBackendProvider.notifier).startMeetup(
              name: spot.label,
              point: spot.point,
              memberUids: _selected.toList(),
              fromIncident: fromIncident,
            );
      } else {
        await ref.read(apiProvider).startMeetup(
              name: spot.label,
              lat: spot.point.latitude,
              lng: spot.point.longitude,
              memberUids: _selected.toList(),
              fromIncident: fromIncident,
            );
      }
      if (!mounted) return;
      ref.read(mapFocusProvider.notifier).state = spot.point;
      ref.read(selectedTabProvider.notifier).state = 0;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('合流を作れませんでした: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final friends = ref.watch(friendsProvider).value ?? const <FriendEntry>[];
    final spots = _spots(friends);
    // 選び直して候補が消えたときに、消えた地点を選んだままにしない。
    if (_spotKey != null && !spots.any((s) => s.key == _spotKey)) _spotKey = null;
    _spotKey ??= spots.firstOrNull?.key;

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m),
          child: Column(children: [
            const SizedBox(height: HinaSpace.s),
            Text('合流する', style: t.titleMedium),
            Text('落ち合う場所を決めて、全員の地図に旗を立てます', style: t.bodySmall),
            const SizedBox(height: HinaSpace.s),
            Expanded(
              child: ListView(controller: scroll, children: [
                const SectionHeader('誰と'),
                for (final f in friends)
                  CheckboxListTile(
                    value: _selected.contains(f.uid),
                    activeColor: HinaColors.sky,
                    title: Text(f.displayName),
                    subtitle: f.relation == null ? null : Text(f.relation!, style: t.bodySmall),
                    onChanged: (v) => setState(() => v == true ? _selected.add(f.uid) : _selected.remove(f.uid)),
                  ),
                if (friends.isEmpty)
                  Padding(padding: const EdgeInsets.all(HinaSpace.m), child: Text('まだ友だちがいません', style: t.bodySmall)),
                const SectionHeader('どこで'),
                if (spots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(HinaSpace.m),
                    child: Text('落ち合える場所が見つかりませんでした。近くの避難場所が読み込まれるまで待つか、位置を確認してください。', style: t.bodySmall),
                  ),
                for (final s in spots)
                  RadioListTile<String>(
                    // ignore: deprecated_member_use
                    value: s.key,
                    // ignore: deprecated_member_use
                    groupValue: _spotKey,
                    activeColor: HinaColors.sky,
                    title: Text(s.label),
                    subtitle: Text(s.note, style: t.bodySmall),
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => _spotKey = v),
                  ),
                const SizedBox(height: HinaSpace.m),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HinaSpace.s),
              child: Row(children: [
                Expanded(child: HinaButton.ghost('やめる', onPressed: () => Navigator.of(context).pop(false))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: HinaButton.primary(
                    _selected.isEmpty ? '相手を選んでください' : '${_selected.length}人と合流する',
                    loading: _busy,
                    onPressed: _busy || _selected.isEmpty || _spotKey == null ? null : () => _create(spots),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
