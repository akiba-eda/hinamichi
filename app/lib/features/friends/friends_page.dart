import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';

class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);
    final me = ref.watch(myProfileProvider).value;
    final myStatus = ref.watch(myStatusProvider).value ?? FriendStatus.unknown;
    return Scaffold(
      appBar: AppBar(title: const Text('Friends'), actions: [
        TextButton.icon(onPressed: () => _addDialog(context, ref), icon: const Icon(Icons.add, size: 18), label: const Text('追加')),
      ]),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.s, HinaSpace.m, 0),
          child: HinaCard(child: Row(children: [
            const SenaviAvatar(SenaviMood.normal, size: 44),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('あなた: ${me?['displayName'] ?? 'わたし'}', style: Theme.of(context).textTheme.titleMedium),
              Text('招待コード: ${me?['inviteCode'] ?? '------'}', style: Theme.of(context).textTheme.bodySmall),
            ])),
            StatusChip(myStatus.state),
          ])),
        ),
        const SectionHeader('見守りリスト'),
        friends.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('読み込めませんでした: $e')),
          data: (list) => list.isEmpty
              ? Padding(padding: const EdgeInsets.all(24), child: Column(children: [
                  const SenaviAvatar(SenaviMood.lying, size: 80),
                  const SizedBox(height: 8),
                  Text('まだ誰もいません。招待コードで家族や友人を追加すると、災害時にあなたの状態が自動で届きます。', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                ]))
              : Column(children: [for (final f in list) _FriendRow(f)]),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m),
          child: Text('状態は「安全 / 確認中 / 避難中 / 到着 / 不明」の5つ。避難所名は本人の同意がある場合のみ表示されます。位置情報そのものは共有されません。', style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(height: 24),
      ]),
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

class _FriendRow extends ConsumerWidget {
  final FriendEntry f;
  const _FriendRow(this.f);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(friendStatusProvider(f.uid)).value ?? FriendStatus.unknown;
    return Column(children: [
      FriendTile(friend: f, status: st),
      Padding(
        padding: const EdgeInsets.only(left: 72, right: 16),
        child: Row(children: [
          Expanded(child: Text('この人に自動共有する', style: Theme.of(context).textTheme.bodySmall)),
          Switch(value: f.autoShare, onChanged: (v) => ref.read(apiProvider).shareFriend(f.uid, v)),
        ]),
      ),
      const Divider(height: 1, indent: 16, endIndent: 16),
    ]);
  }
}
