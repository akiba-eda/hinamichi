import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hina_theme.dart';
import '../../core/address_search.dart';
import '../../core/location_service.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';

/// 仮の現在地を住所で入れてもらうシート。
///
/// GPS が取れない場所(地下・屋内・機内モード)で、避難所もハザードも調べられずに
/// 止まってしまうのを避けるため。[force] はリハーサル用で、GPS が取れても
/// こちらを使い続ける。
Future<bool> showManualLocationSheet(BuildContext context, WidgetRef ref, {bool force = false}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ManualLocationSheet(force: force),
    ),
  );
  return ok ?? false;
}

class _ManualLocationSheet extends ConsumerStatefulWidget {
  final bool force;
  const _ManualLocationSheet({required this.force});
  @override
  ConsumerState<_ManualLocationSheet> createState() => _ManualLocationSheetState();
}

class _ManualLocationSheetState extends ConsumerState<_ManualLocationSheet> {
  final _c = TextEditingController();
  List<AddressHit> _hits = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hits = await searchAddress(_c.text);
      setState(() => _hits = hits);
      if (hits.isEmpty) setState(() => _error = '見つかりませんでした。市区町村から入れると当たりやすいです');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(AddressHit h) async {
    await LocationService.setManual(h.point, h.title, force: widget.force);
    try {
      await ref.read(locationProvider.notifier).refresh();
    } catch (_) {
      // 入れた地点で解決できるはずだが、失敗しても画面は閉じて次へ進ませる。
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(HinaSpace.m),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.force ? '現在地を指定する' : '仮の現在地を入力する', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('住所や地名を入れてください。ここで選んだ場所を中心に、避難所とハザードを調べます。', style: t.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '例: 東京都千代田区丸の内1-9-1',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _busy ? null : _search),
            ),
            onSubmitted: (_) => _search(),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error))),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_hits.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _hits.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(_hits[i].title, style: t.bodyLarge),
                  onTap: () => _pick(_hits[i]),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: HinaButton.ghost('やめる', onPressed: () => Navigator.of(context).pop(false))),
        ]),
      ),
    );
  }
}
