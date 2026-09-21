import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/senavi.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';

/// Human gate for free-text messages (設計書 §6.4). セナヴィ peeks over the sheet.
Future<void> showApprovalSheet(BuildContext context, WidgetRef ref, {String? incidentId}) {
  final ctrl = TextEditingController(text: '今、避難所に向かっています。無事です。');
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Container(
          margin: const EdgeInsets.only(top: 44),
          padding: const EdgeInsets.fromLTRB(HinaSpace.l, 56, HinaSpace.l, HinaSpace.l),
          decoration: const BoxDecoration(color: HinaColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(HinaRadius.sheet))),
          child: _ApprovalBody(ctrl: ctrl, incidentId: incidentId),
        ),
        const Positioned(top: 0, child: SenaviAvatar(SenaviMood.lookback, size: 96)),
      ]),
    ),
  );
}

class _ApprovalBody extends ConsumerStatefulWidget {
  final TextEditingController ctrl;
  final String? incidentId;
  const _ApprovalBody({required this.ctrl, this.incidentId});
  @override
  ConsumerState<_ApprovalBody> createState() => _ApprovalBodyState();
}

class _ApprovalBodyState extends ConsumerState<_ApprovalBody> {
  bool sending = false;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('家族・友人に\nこのメッセージを送っていい?', textAlign: TextAlign.center, style: t.titleLarge),
      const SizedBox(height: 6),
      Text('自由文はセナヴィが勝手に送りません。あなたが承認したものだけ届きます。', textAlign: TextAlign.center, style: t.bodySmall),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: HinaColors.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: HinaColors.line)),
        child: TextField(controller: widget.ctrl, maxLines: 3, maxLength: 120, decoration: const InputDecoration(border: InputBorder.none, counterText: ''), style: t.bodyLarge),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: HinaButton.secondary('やめる', onPressed: () => Navigator.of(context).pop())),
        const SizedBox(width: 10),
        Expanded(
          child: HinaButton.primary('送信する', loading: sending, onPressed: () async {
            setState(() => sending = true);
            final messenger = ScaffoldMessenger.maybeOf(context);
            final nav = Navigator.of(context);
            try {
              final r = await ref.read(apiProvider).messageFriends(widget.ctrl.text.trim());
              nav.pop();
              messenger?.showSnackBar(SnackBar(content: Text('${r['sent']}人に送りました: ${r['text']}')));
            } catch (e) {
              messenger?.showSnackBar(SnackBar(content: Text('送信できませんでした: $e')));
            } finally {
              if (mounted) setState(() => sending = false);
            }
          }),
        ),
      ]),
    ]);
  }
}
