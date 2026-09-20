import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../core/config.dart';
import '../../domain/senavi.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';
import '../gallery/gallery_page.dart';
import 'demo_panel.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).value;
    final consent = (me?['consent'] as Map?) ?? const {};
    final demo = ref.watch(demoProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.all(HinaSpace.m),
          child: HinaCard(child: Row(children: [
            const SenaviAvatar(SenaviMood.normal, size: 56),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('セナヴィ', style: t.titleMedium),
              Text('Safety Navigator AI\n災害時、あなたの代わりに状況を確認し、最適な避難経路を提案するAIナビゲーター。', style: t.bodySmall),
            ])),
          ])),
        ),
        const SectionHeader('プロフィール'),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('表示名'),
          subtitle: Text('${me?['displayName'] ?? 'わたし'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editName(context, ref, '${me?['displayName'] ?? ''}'),
        ),
        ListTile(leading: const Icon(Icons.qr_code_2), title: const Text('招待コード'), subtitle: Text('${me?['inviteCode'] ?? '------'}')),
        const SectionHeader('共有の同意'),
        SwitchListTile(
          secondary: const Icon(Icons.groups_outlined),
          title: const Text('状態を家族・友人に自動共有'),
          subtitle: const Text('確認中 / 避難中 / 到着 などの状態だけ。位置情報は送りません'),
          value: consent['shareStatusWithFriends'] != false,
          onChanged: (v) => ref.read(apiProvider).register(consent: {'shareStatusWithFriends': v}),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.location_city_outlined),
          title: const Text('避難所名も共有する'),
          value: consent['shareShelterName'] != false,
          onChanged: (v) => ref.read(apiProvider).register(consent: {'shareShelterName': v}),
        ),
        const SwitchListTile(secondary: Icon(Icons.gps_off_outlined), title: Text('生の位置情報を共有'), subtitle: Text('常にオフ(設計上、共有しません)'), value: false, onChanged: null),
        const SectionHeader('地図レイヤー'),
        SwitchListTile(title: const Text('浸水想定区域'), value: demo.showFlood, onChanged: (v) => ref.read(demoProvider.notifier).setLayers(flood: v)),
        SwitchListTile(title: const Text('津波浸水想定'), value: demo.showTsunami, onChanged: (v) => ref.read(demoProvider.notifier).setLayers(tsunami: v)),
        SwitchListTile(title: const Text('土砂災害警戒区域'), value: demo.showLandslide, onChanged: (v) => ref.read(demoProvider.notifier).setLayers(landslide: v)),
        const SectionHeader('開発者向け'),
        SwitchListTile(
          secondary: const Icon(Icons.science_outlined),
          title: const Text('DEMO モード'),
          subtitle: const Text('災害の発生だけを再現します。判断・避難所・経路は実データ'),
          activeColor: HinaColors.sun,
          value: demo.enabled,
          onChanged: (v) => ref.read(demoProvider.notifier).setEnabled(v),
        ),
        if (demo.enabled) const Padding(padding: EdgeInsets.symmetric(horizontal: HinaSpace.m), child: DemoPanel()),
        ListTile(leading: const Icon(Icons.cloud_outlined), title: const Text('API サーバー'), subtitle: FutureBuilder(future: AppConfig.apiBase(), builder: (_, s) => Text(s.data ?? '')), trailing: const Icon(Icons.edit_outlined), onTap: () => _editApi(context, ref)),
        ListTile(leading: const Icon(Icons.widgets_outlined), title: const Text('Widget ギャラリー'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GalleryPage()))),
        const SizedBox(height: 16),
        Center(child: Text('ヒナミチ v0.1 — 地理院タイル / ハザードマップポータルサイト / 指定緊急避難場所データ(国土地理院) / P2P地震情報 / 気象庁', textAlign: TextAlign.center, style: t.bodySmall)),
      ]),
    );
  }

  void _editName(BuildContext context, WidgetRef ref, String cur) {
    final c = TextEditingController(text: cur);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('表示名'),
      content: TextField(controller: c, maxLength: 30),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
        FilledButton(onPressed: () async { await ref.read(apiProvider).register(displayName: c.text.trim()); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('保存')),
      ],
    ));
  }

  void _editApi(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController(text: await AppConfig.apiBase());
    if (!context.mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('API サーバー URL'),
      content: TextField(controller: c, decoration: const InputDecoration(hintText: 'https://xxx.vercel.app または http://192.168.x.x:3000')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
        FilledButton(onPressed: () async { await AppConfig.setApiBase(c.text); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('保存')),
      ],
    ));
  }
}
