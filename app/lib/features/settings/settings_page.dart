import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../core/config.dart';
import '../../domain/senavi.dart';
import '../../mock/mock_backend.dart';
import '../../ui/organisms/hina_basemap.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';
import '../agent_log/agent_log_page.dart';
import '../gallery/gallery_page.dart';
import 'about_page.dart';
import 'profile_page.dart';
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
        // 会場ビルドでは、触る人が最初に見る位置に「体験する」を置く。
        // 開発者向けの折りたたみの奥にあると、災害が起きないと何も起きない。
        if (AppConfig.kiosk) ...[
          const SectionHeader('災害を体験する'),
          const Padding(padding: EdgeInsets.symmetric(horizontal: HinaSpace.m), child: DemoPanel(kiosk: true)),
          const SizedBox(height: 8),
        ],
        // ボトムナビは設計書 §17.3 の 4 タブ構成にしたので、AgentLog はここから開く。
        const SectionHeader('セナヴィの記録'),
        ListTile(
          leading: const HinaIconView(HinaIcon.log, size: 24, color: HinaColors.inkSub),
          title: const Text('判断の記録 (AgentLog)'),
          subtitle: const Text('ツール呼び出し・AIに渡した入力・モデル名とコスト'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AgentLogPage())),
        ),
        const SectionHeader('プロフィール'),
        // アイコン / 名前 / メモ はまとめて 1 画面に。
        ListTile(
          leading: HinaAvatar(
            imageBase64: me?['avatarImage'] as String?,
            moodName: me?['avatarMood'] as String?,
            fallbackName: '${me?['displayName'] ?? 'わたし'}',
            size: 42,
            ringColor: HinaColors.sky,
          ),
          title: Text('${me?['displayName'] ?? 'わたし'}'),
          subtitle: Text('アイコン・名前・メモを編集', style: t.bodySmall),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage())),
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
        SwitchListTile(
          secondary: const Icon(Icons.share_location_outlined),
          title: const Text('現在地をフレンドに共有'),
          subtitle: Text(
            ref.watch(locationSharingProvider)
                ? 'バックグラウンドでも送ります。誰に見せるかは友だち一覧で個別に選びます'
                : 'オフの間は位置を測りません（電池を使いません）',
            style: t.bodySmall,
          ),
          activeColor: HinaColors.sky,
          value: ref.watch(locationSharingProvider),
          onChanged: (v) async {
            final ok = await ref.read(locationSharingProvider.notifier).set(v);
            if (!ok) showSenaviToast('位置情報の許可が要るよ。設定アプリで「常に許可」にしてね', error: true);
          },
        ),
        if (ref.watch(locationSharingProvider))
          ref.watch(pendingLocationCountProvider).maybeWhen(
                data: (n) => n == 0
                    ? const SizedBox.shrink()
                    : ListTile(
                        leading: const Icon(Icons.cloud_off_outlined, color: HinaColors.stEvacuating),
                        title: Text('送信待ち $n件', style: t.bodyMedium),
                        subtitle: Text('圏外で測った位置です。電波が戻ると古い順に送ります', style: t.bodySmall),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
        const SectionHeader('地図の見た目'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m),
          child: Column(children: [
            for (final b in HinaBasemap.values)
              RadioListTile<HinaBasemap>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: b,
                // ignore: deprecated_member_use
                groupValue: ref.watch(basemapProvider),
                activeColor: HinaColors.sky,
                title: Text(b.label, style: t.bodyLarge),
                subtitle: Text(b.note, style: t.bodySmall),
                // ignore: deprecated_member_use
                onChanged: (v) => v == null ? null : ref.read(basemapProvider.notifier).set(v),
              ),
          ]),
        ),
        const SectionHeader('地図レイヤー'),
        SwitchListTile(title: const Text('浸水想定区域'), value: demo.showFlood, onChanged: (v) => ref.read(demoProvider.notifier).setLayers(flood: v)),
        SwitchListTile(title: const Text('津波浸水想定'), value: demo.showTsunami, onChanged: (v) => ref.read(demoProvider.notifier).setLayers(tsunami: v)),
        SwitchListTile(title: const Text('土砂災害警戒区域'), value: demo.showLandslide, onChanged: (v) => ref.read(demoProvider.notifier).setLayers(landslide: v)),
        if (!AppConfig.kiosk) ...[
        const SectionHeader('開発者向け'),
        SwitchListTile(
          secondary: const Icon(Icons.dns_outlined),
          title: const Text('モックモード'),
          subtitle: const Text('サーバーを使わず端末内の仮データで動かす。繋ぎ込み後の挙動を先に確認するため'),
          activeColor: HinaColors.sky,
          value: ref.watch(mockModeProvider),
          onChanged: (v) => ref.read(mockModeProvider.notifier).set(v),
        ),
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
        ],
        const SizedBox(height: 16),
        // 画面ごとに注釈を散らすと説明文だらけになるので、断り書きはここへ集約する。
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('データについて'),
          subtitle: Text('混雑・ハザード・AIに渡す情報の出所', style: t.bodySmall),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
        ),
        const SizedBox(height: 8),
        Center(child: Text('ヒナミチ v0.1', style: t.bodySmall)),
      ]),
    );
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
