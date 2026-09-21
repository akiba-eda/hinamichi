import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';
import '../../mock/mock_backend.dart';
import '../../domain/social.dart';
import 'friend_detail_sheet.dart';

/// 並び替え。災害時は「危ない人から」、平時は「最近動いた人から」見たい。
enum FriendSort { byStatus, byUpdated }

final friendSortProvider = StateProvider<FriendSort>((_) => FriendSort.byStatus);

/// 安否の重さ。小さいほど気にかけるべき。
int _weight(PublicStatus s) => switch (s) {
      PublicStatus.unknown => 0,
      PublicStatus.evacuating => 1,
      PublicStatus.assessing => 2,
      PublicStatus.arrived => 3,
      PublicStatus.safeZone => 4,
      PublicStatus.safe => 5,
    };

class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);
    final me = ref.watch(myProfileProvider).value;
    final myStatus = ref.watch(myStatusProvider).value ?? FriendStatus.unknown;
    final sort = ref.watch(friendSortProvider);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: HinaColors.bg,
      body: ListView(padding: EdgeInsets.zero, children: [
        _Header(onAdd: () => _addDialog(context, ref)),
        // 自分のカードはヘッダーに少し重ねる(デザイン案の見え方)。
        Transform.translate(
          offset: const Offset(0, -26),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m),
            child: HinaCard(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                HinaAvatar(
                  imageBase64: me?['avatarImage'] as String?,
                  moodName: me?['avatarMood'] as String?,
                  fallbackName: '${me?['displayName'] ?? 'わたし'}',
                  size: 46,
                  ringColor: HinaColors.sky,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('あなた: ${me?['displayName'] ?? 'わたし'}', style: t.titleMedium),
                    const SizedBox(height: 2),
                    _InviteCode(code: '${me?['inviteCode'] ?? '------'}'),
                  ]),
                ),
                StatusChip(myStatus.state, compact: true),
              ]),
            ),
          ),
        ),
        // 自分のメモ。状態の5段階では伝わらないことを自分の言葉で残す欄。
        Transform.translate(
          offset: const Offset(0, -22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m),
            child: InkWell(
              borderRadius: BorderRadius.circular(HinaRadius.card),
              onTap: () => _editNote(context, ref, myStatus.note ?? ''),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: HinaColors.sand.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(HinaRadius.card)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('あなたのメモ(みんなに見えます)', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: HinaColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                        myStatus.note?.isNotEmpty == true ? myStatus.note! : '例: 3階にいます / 水と食料あり / 今日は在宅',
                        style: myStatus.note?.isNotEmpty == true ? t.bodyMedium : t.bodySmall?.copyWith(color: HinaColors.inkSub),
                      ),
                    ]),
                  ),
                  const Icon(Icons.edit_outlined, size: 18, color: HinaColors.inkSub),
                ]),
              ),
            ),
          ),
        ),
        // 進行中の合流。災害から作られたものは色を変える。
        if (ref.watch(meetupProvider) != null)
          Transform.translate(
            offset: const Offset(0, -18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m),
              child: MeetupBanner(meetup: ref.watch(meetupProvider)!),
            ),
          ),
        // 到着/出発のできごと。新しいものから数件。
        if (ref.watch(placeEventsProvider).isNotEmpty)
          Transform.translate(
            offset: const Offset(0, -12),
            child: Column(children: [
              const SectionHeader('できごと'),
              for (final e in ref.watch(placeEventsProvider).take(3))
                ListTile(
                  dense: true,
                  leading: HinaIconView(e.arrived ? HinaIcon.done : HinaIcon.locate, size: 20, color: e.arrived ? HinaColors.stSafe : HinaColors.inkSub),
                  title: Text(e.line, style: t.bodyMedium),
                  trailing: Text('${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}', style: t.bodySmall),
                ),
            ]),
          ),
        Transform.translate(
          offset: const Offset(0, -18),
          child: Column(children: [
            SectionHeader(
              '見守りリスト',
              trailing: TextButton.icon(
                onPressed: () => ref.read(friendSortProvider.notifier).state = sort == FriendSort.byStatus ? FriendSort.byUpdated : FriendSort.byStatus,
                icon: const Icon(Icons.swap_vert, size: 18, color: HinaColors.inkSub),
                label: Text(sort == FriendSort.byStatus ? '気になる順' : '更新順', style: t.bodySmall),
              ),
            ),
            friends.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: HinaColors.sky))),
              error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('読み込めませんでした: $e', style: t.bodySmall)),
              data: (list) => list.isEmpty ? const _Empty() : Column(children: [for (final f in _sorted(ref, list, sort)) _FriendCard(f)]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(HinaSpace.m, 0, HinaSpace.m, HinaSpace.l),
          child: Text(
            '安否(安全 / 確認中 / 避難中 / 到着 / 不明)は、追加した相手に自動で届きます。'
            '現在地はこの一覧で許可した相手だけに届き、表示されるのは最後に受け取った位置です。',
            style: t.bodySmall,
          ),
        ),
      ]),
    );
  }

  List<FriendEntry> _sorted(WidgetRef ref, List<FriendEntry> list, FriendSort sort) {
    final out = [...list];
    out.sort((a, b) {
      final sa = ref.read(friendStatusProvider(a.uid)).value ?? FriendStatus.unknown;
      final sb = ref.read(friendStatusProvider(b.uid)).value ?? FriendStatus.unknown;
      if (sort == FriendSort.byStatus) {
        final w = _weight(sa.state).compareTo(_weight(sb.state));
        if (w != 0) return w;
      }
      final ua = sa.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final ub = sb.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ub.compareTo(ua);
    });
    return out;
  }

  void _editNote(BuildContext context, WidgetRef ref, String cur) {
    final c = TextEditingController(text: cur);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('あなたのメモ'),
        content: TextField(
          controller: c,
          maxLength: 60,
          maxLines: 2,
          decoration: const InputDecoration(hintText: '3階にいます / 水と食料あり / 今日は在宅'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HinaColors.sun, foregroundColor: HinaColors.ink),
            onPressed: () async {
              if (ref.read(mockModeProvider)) {
                ref.read(mockBackendProvider.notifier).setMyNote(c.text);
              } else {
                try {
                  await ref.read(apiProvider).setNote(c.text.trim());
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('\$e')));
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _addDialog(BuildContext context, WidgetRef ref) {
    final c = TextEditingController();
    final r = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('招待コードで追加'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: c, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: '相手の招待コード(6文字)')),
          TextField(controller: r, decoration: const InputDecoration(labelText: '続柄(任意: 家族・友人…)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HinaColors.sun, foregroundColor: HinaColors.ink),
            onPressed: () async {
              try {
                await ref.read(apiProvider).acceptFriend(c.text.trim().toUpperCase(), relation: r.text.trim().isEmpty ? null : r.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }
}

/// スプラッシュと同じ夕景から切り出した帯。世界観を繋ぐために新規素材は足していない。
class _Header extends StatelessWidget {
  final VoidCallback onAdd;
  const _Header({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: 168,
      child: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/brand/friends_header.png', fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: (_, __, ___) => const ColoredBox(color: HinaColors.mist)),
        // 下端を背景色に溶かして、カードが乗る余白を作る。
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Color(0x00FAF8F4), HinaColors.bg],
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.s, HinaSpace.m, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Friends', style: t.displaySmall?.copyWith(color: const Color(0xFF1E3D5C), shadows: const [Shadow(color: Color(0x55FFFFFF), blurRadius: 8)])),
                  const SizedBox(height: 2),
                  Text('つながることで、もっと安心になる。',
                      style: t.bodySmall?.copyWith(color: const Color(0xFF1E3D5C), fontWeight: FontWeight.w600, shadows: const [Shadow(color: Color(0x55FFFFFF), blurRadius: 6)])),
                ]),
              ),
              FilledButton.icon(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: HinaColors.surface,
                  foregroundColor: HinaColors.ink,
                  elevation: 2,
                  shadowColor: Colors.black26,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HinaRadius.button)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('追加', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _InviteCode extends StatelessWidget {
  final String code;
  const _InviteCode({required this.code});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: code));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('招待コードをコピーしました')));
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('招待コード: $code', style: t.bodySmall),
        const SizedBox(width: 4),
        const Icon(Icons.copy_rounded, size: 13, color: HinaColors.inkSub),
      ]),
    );
  }
}

class _FriendCard extends ConsumerWidget {
  final FriendEntry f;
  const _FriendCard(this.f);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(friendStatusProvider(f.uid)).value ?? FriendStatus.unknown;
    final location = ref.watch(friendLocationProvider(f.uid)).value;
    return FriendTile(
      friend: f,
      status: status,
      location: location,
      // 位置が届いていない相手も、安否とメモは見せたい。
      onTap: () => showFriendDetail(
        context,
        FriendOnMap(entry: f, status: status, location: location ?? FriendLocation(point: const LatLng(0, 0), at: DateTime.fromMillisecondsSinceEpoch(0))),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SenaviAvatar(SenaviMood.lying, size: 96),
          const SizedBox(height: 8),
          Text('まだ誰もいません。招待コードで家族や友人を追加すると、災害時にあなたの状態が自動で届きます。',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
