import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/user_message.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/social.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';

/// 届いた通報依頼。
///
/// **開くまで個人情報を出さない。** 一覧にも通知にも本名・住所は載せず、
/// 受け取った人が「確認する」を押して初めて読み出す。押した時点で
/// Firestore のルールが「この依頼の宛先か」を確かめる。
void showSosSheet(BuildContext context, SosRequest sos) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: HinaColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.m, HinaSpace.m, MediaQuery.of(context).viewInsets.bottom + 24),
      child: _SosBody(sos),
    ),
  );
}

class _SosBody extends ConsumerStatefulWidget {
  final SosRequest sos;
  const _SosBody(this.sos);
  @override
  ConsumerState<_SosBody> createState() => _SosBodyState();
}

class _SosBodyState extends ConsumerState<_SosBody> {
  bool _revealed = false;
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sos = widget.sos;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.sos, color: HinaColors.stUnknown),
        const SizedBox(width: 8),
        Expanded(child: Text('通報の依頼が届いています', style: t.titleLarge)),
      ]),
      const SizedBox(height: 10),
      Text(sos.headline, style: t.bodyLarge),
      const SizedBox(height: 4),
      Text('${sos.nickname}さんは自分で SOS を出せない状態かもしれません。', style: t.bodySmall),
      const SizedBox(height: 16),
      if (!_revealed)
        HinaCard(
          color: HinaColors.bg,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('本名・住所・年齢・電話番号が預けられています', style: t.titleMedium),
            const SizedBox(height: 6),
            Text('通報に要るぶんだけ、いま開けます。', style: t.bodySmall?.copyWith(color: HinaColors.inkSub)),
            const SizedBox(height: 12),
            HinaButton.primary('個人情報を確認する', onPressed: () => setState(() => _revealed = true)),
          ]),
        )
      else
        _Revealed(uid: sos.uid),
      const SizedBox(height: 12),
      Text(
        'このアプリは 119番や自治体には繋がりません。通報はあなたが電話でかけてください。',
        style: t.bodySmall?.copyWith(color: HinaColors.inkSub),
      ),
      const SizedBox(height: 12),
      HinaButton.secondary(
        '対応しました(依頼を閉じる)',
        loading: _closing,
        onPressed: () async {
          setState(() => _closing = true);
          final nav = Navigator.of(context);
          final messenger = ScaffoldMessenger.maybeOf(context);
          try {
            await ref.read(apiProvider).closeSos(sos.id);
            nav.pop();
          } catch (e) {
            messenger?.showSnackBar(SnackBar(content: Text(userMessage(e, action: '閉じる'))));
          } finally {
            if (mounted) setState(() => _closing = false);
          }
        },
      ),
    ]);
  }
}

class _Revealed extends ConsumerWidget {
  final String uid;
  const _Revealed({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final e = ref.watch(revealedEmergencyProvider(uid)).value;
    if (e == null) {
      return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
    }
    final phone = e['phone'] as String?;
    Widget row(String label, String? value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 76, child: Text(label, style: t.bodySmall?.copyWith(color: HinaColors.inkSub))),
            Expanded(child: Text(value?.isNotEmpty == true ? value! : '未登録', style: t.bodyLarge)),
          ]),
        );

    return HinaCard(
      color: HinaColors.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row('本名', e['legalName'] as String?),
        row('住所', e['address'] as String?),
        row('年齢', e['age'] == null ? null : '${e['age']}'),
        row('電話番号', phone),
        if (phone?.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          HinaButton.secondary('本人に電話をかける', icon: Icons.call, onPressed: () => launchUrl(Uri.parse('tel:$phone'))),
        ],
      ]),
    );
  }
}
