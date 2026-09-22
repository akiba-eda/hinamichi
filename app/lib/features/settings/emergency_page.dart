import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/user_message.dart';
import '../../ui/molecules/molecules.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';

/// 緊急時情報。**ここに入れたものは AI に一切渡りません。**
///
/// 代わりに通報してもらうには本名と住所が要る。けれど、それを避難先の判断に
/// 使う理由は無い。だから置き場所ごと分けて、サーバーでも別コレクション、
/// LLM へ送る手前でも機械的に検査している。
class EmergencyPage extends ConsumerStatefulWidget {
  const EmergencyPage({super.key});
  @override
  ConsumerState<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends ConsumerState<EmergencyPage> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _age = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _age, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cur = ref.watch(myEmergencyProvider).value;
    if (!_loaded && cur != null) {
      _loaded = true;
      _name.text = (cur['legalName'] ?? '') as String;
      _address.text = (cur['address'] ?? '') as String;
      _age.text = cur['age'] == null ? '' : '${cur['age']}';
      _phone.text = (cur['phone'] ?? '') as String;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('緊急時情報')),
      body: ListView(padding: const EdgeInsets.all(HinaSpace.m), children: [
        HinaCard(
          color: const Color(0xFFFFF6D6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI には渡りません', style: t.titleMedium),
            const SizedBox(height: 6),
            Text(
              'ここに入れた本名・住所・年齢・電話番号は、避難先を選ぶ AI に一度も渡りません。'
              'AI が受け取るのはプロフィール名(ニックネーム)と市区町村までです。\n\n'
              '使うのは、あなたが動けなくなって家族や友人に通報を頼むときだけ。'
              '相手の画面でも、本人が「確認する」を押すまで伏せられています。',
              style: t.bodySmall?.copyWith(height: 1.6),
            ),
          ]),
        ),
        const SizedBox(height: HinaSpace.m),
        _field(_name, '本名', '例: 山田 太郎', required: true),
        _field(_address, '住所', '例: 千葉県浦安市北栄1-1-1'),
        _field(_age, '年齢', '例: 42', keyboard: TextInputType.number),
        _field(_phone, '電話番号', '例: 090-1234-5678', keyboard: TextInputType.phone),
        const SizedBox(height: HinaSpace.m),
        HinaButton.primary('保存する', loading: _saving, onPressed: _save),
        const SizedBox(height: HinaSpace.m),
        Text(
          '通報を依頼しても、119番や自治体には繋がりません。'
          '家族や友人に「代わりに通報してほしい」と伝えるだけの機能です。',
          style: t.bodySmall?.copyWith(color: HinaColors.inkSub),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label, String hint, {bool required = false, TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          inputFormatters: keyboard == TextInputType.number ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            labelText: required ? '$label(必須)' : label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSenaviToast('本名を入れてね。通報を代わりに頼むときに要るんだ', error: true);
      return;
    }
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).setEmergency(
            legalName: name,
            address: _address.text.trim(),
            age: int.tryParse(_age.text.trim()),
            phone: _phone.text.trim(),
          );
      ref.invalidate(myEmergencyProvider);
      nav.pop();
      showSenaviToast('保存したよ。相手が確認したときだけ見える情報だから安心してね');
    } catch (e) {
      showSenaviToast(userMessage(e, action: '保存'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
