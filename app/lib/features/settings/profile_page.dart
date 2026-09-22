import 'dart:convert';
import '../../core/user_message.dart';
import '../../ui/molecules/molecules.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../../domain/social.dart';
import '../../mock/mock_backend.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import 'emergency_page.dart';
import 'places_page.dart';

/// 設定 → プロフィール。
///
/// プロフィール名(ニックネーム)は AI も受け取る。緊急時情報は別画面に分けて
/// あり、そちらは AI に渡らない ── 同じ画面に並べると境界が曖昧になる。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final me = ref.watch(myProfileProvider).value;
    final myStatus = ref.watch(myStatusProvider).value ?? FriendStatus.unknown;
    final name = '${me?['displayName'] ?? 'わたし'}';
    final avatarImage = me?['avatarImage'] as String?;
    final avatarMood = me?['avatarMood'] as String?;
    final emergency = ref.watch(myEmergencyProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.all(HinaSpace.l),
          child: Center(
            child: Column(children: [
              HinaAvatar(imageBase64: avatarImage, moodName: avatarMood, fallbackName: name, size: 108, ringColor: HinaColors.sky),
              const SizedBox(height: 10),
              Text(name, style: t.titleLarge),
              Text('招待コード: ${me?['inviteCode'] ?? '------'}', style: t.bodySmall),
            ]),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.face_retouching_natural_outlined),
          title: const Text('アイコン'),
          subtitle: Text(avatarImage != null ? '選んだ画像' : (avatarMood != null ? 'セナヴィ' : '未設定'), style: t.bodySmall),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickIcon(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('プロフィール名'),
          subtitle: Text(name, style: t.bodySmall),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editName(context, ref, name),
        ),
        ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: const Text('メモ'),
          subtitle: Text(
            myStatus.note?.isNotEmpty == true ? myStatus.note! : '未設定 (例: 3階にいます / 水と食料あり)',
            style: t.bodySmall?.copyWith(color: myStatus.note?.isNotEmpty == true ? HinaColors.ink : HinaColors.inkSub),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editNote(context, ref, myStatus.note ?? ''),
        ),
        const Divider(height: 1),
        // 平時に登録してもらうための入口。災害時だけの機能にすると、
        // いざという時に誰も設定していない。
        Consumer(builder: (context, ref, _) {
          final places = ref.watch(placesProvider).value ?? const <SavedPlace>[];
          return ListTile(
            leading: const Icon(Icons.home_outlined, color: HinaColors.sky),
            title: const Text('よく行く場所'),
            subtitle: Text(
              places.isEmpty
                  ? '未登録 — 出入りしたとき、家族に自動で知らせます'
                  : places.map((p) => p.name).join(' / '),
              style: t.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlacesPage())),
          );
        }),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.sos_outlined, color: HinaColors.stUnknown),
          title: const Text('緊急時情報'),
          subtitle: Text(
            emergency?['legalName'] != null ? '登録済み(本名・住所・年齢・電話)' : '未登録 — 通報を代わりに頼むのに要ります',
            style: t.bodySmall,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmergencyPage())),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(HinaSpace.m),
          child: Text(
            'アイコンと名前は、招待した家族・友人の一覧に表示されます。メモは安否と一緒に相手へ届きます。\n\n'
            'よく行く場所は出入りの判定にだけ使い、相手に届くのは場所の名前だけです。座標は送りません。\n\n'
            'プロフィール名は AI も受け取ります。緊急時情報(本名・住所・年齢・電話)は AI に一度も渡りません。',
            style: t.bodySmall,
          ),
        ),
      ]),
    );
  }

  Future<void> _save(WidgetRef ref, {String? displayName, String? avatarImage, String? avatarMood, bool clearImage = false}) async {
    if (ref.read(mockModeProvider)) {
      ref.read(mockBackendProvider.notifier).setProfile(displayName: displayName, avatarImage: clearImage ? '' : avatarImage, avatarMood: avatarMood);
      return;
    }
    await ref.read(apiProvider).setProfile(displayName: displayName, avatarImage: clearImage ? '' : avatarImage, avatarMood: avatarMood);
  }

  void _pickIcon(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: HinaColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HinaRadius.sheet))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(HinaSpace.m),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('セナヴィから選ぶ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final m in SenaviMood.values)
                  InkWell(
                    borderRadius: BorderRadius.circular(40),
                    onTap: () async {
                      await _save(ref, avatarMood: m.name, clearImage: true);
                      if (sheet.mounted) Navigator.pop(sheet);
                    },
                    child: HinaAvatar(moodName: m.name, size: 62),
                  ),
              ],
            ),
            const SizedBox(height: HinaSpace.m),
            HinaButton.secondary('写真を選ぶ', icon: Icons.photo_library_outlined, onPressed: () => _pickPhoto(sheet, ref)),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickPhoto(BuildContext sheet, WidgetRef ref) async {
    try {
      // 256px / 品質80 まで落として選ばせる。Firestore のドキュメントに
      // そのまま入れるので、ここで小さくしておかないと 1MB 上限に当たる。
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256, imageQuality: 80);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.lengthInBytes > 180 * 1024) {
        showSenaviToast('その写真は大きすぎるみたい。別の写真を選んでね', error: true);
        return;
      }
      await _save(ref, avatarImage: base64Encode(bytes), avatarMood: '');
      if (sheet.mounted) Navigator.pop(sheet);
    } catch (e) {
      showSenaviToast(userMessage(e, action: '画像を読み込み'), error: true);
    }
  }

  void _editName(BuildContext context, WidgetRef ref, String cur) {
    final c = TextEditingController(text: cur);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('プロフィール名'),
        content: TextField(controller: c, maxLength: 30, decoration: const InputDecoration(hintText: '家族や友人に見える名前')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HinaColors.sun, foregroundColor: HinaColors.ink),
            onPressed: () async {
              final v = c.text.trim();
              if (v.isNotEmpty) await _save(ref, displayName: v);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _editNote(BuildContext context, WidgetRef ref, String cur) {
    final c = TextEditingController(text: cur);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('メモ'),
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
                  showSenaviToast(userMessage(e), error: true);
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
}
