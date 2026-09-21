import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../core/address_search.dart';
import '../../domain/senavi.dart';
import '../../domain/social.dart';
import '../../mock/mock_backend.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';

/// よく行く場所の登録。
///
/// ここに入れた場所を出入りすると、家族・友人へ「◯◯が自宅に着きました」が
/// 自動で飛ぶ。判定はサーバーがやる ── 画面を開いていない・寝ている間の到着こそ
/// 知りたいので、端末側でやると意味が無い。
///
/// 平時の「帰宅を知る」と災害時の「避難所に着いたのを知らせる」は同じ仕組み。
/// 災害時だけの機能にすると、いざという時に誰も登録していない。
class PlacesPage extends ConsumerWidget {
  const PlacesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final places = ref.watch(placesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('よく行く場所')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: HinaColors.sun,
        foregroundColor: HinaColors.ink,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('場所を追加'),
        onPressed: () => showPlaceEditor(context, ref),
      ),
      body: places.when(
        loading: () => const Center(child: CircularProgressIndicator(color: HinaColors.sky)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('$e', style: t.bodySmall))),
        data: (list) => ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Padding(
            padding: const EdgeInsets.all(HinaSpace.m),
            child: Text(
              '登録した場所を出入りすると、家族・友人に「◯◯が自宅に着きました」が自動で届きます。\n'
              '届くのは場所の名前だけで、座標は送りません。',
              style: t.bodySmall,
            ),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(children: [
                const SenaviAvatar(SenaviMood.lying, size: 96),
                const SizedBox(height: 12),
                Text('まだ登録がありません。自宅や学校を入れておくと、帰り着いたことが家族に伝わります。',
                    textAlign: TextAlign.center, style: t.bodySmall),
              ]),
            ),
          for (final p in list)
            ListTile(
              leading: Icon(_icon(p.kind), color: HinaColors.sky),
              title: Text(p.name),
              subtitle: Text('${p.kind.label} / 半径${p.radiusM}m', style: t.bodySmall),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '削除',
                onPressed: () => _remove(context, ref, p),
              ),
              onTap: () => showPlaceEditor(context, ref, editing: p),
            ),
        ]),
      ),
    );
  }

  static IconData _icon(PlaceKind k) => switch (k) {
        PlaceKind.home => Icons.home_outlined,
        PlaceKind.work => Icons.work_outline,
        PlaceKind.school => Icons.school_outlined,
        PlaceKind.shelter => Icons.shield_outlined,
        PlaceKind.other => Icons.place_outlined,
      };

  Future<void> _remove(BuildContext context, WidgetRef ref, SavedPlace p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${p.name}」を削除しますか'),
        content: const Text('この場所の出入りは、家族へ届かなくなります。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('やめる')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (ref.read(mockModeProvider)) {
        ref.read(mockBackendProvider.notifier).removePlace(p.id);
      } else {
        await ref.read(apiProvider).removePlace(p.id);
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('削除できませんでした: $e')));
    }
  }
}

/// 1件の登録・編集。住所で引くか、いまいる場所をそのまま使う。
Future<void> showPlaceEditor(BuildContext context, WidgetRef ref, {SavedPlace? editing}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _PlaceEditor(editing: editing),
      ),
    );

class _PlaceEditor extends ConsumerStatefulWidget {
  final SavedPlace? editing;
  const _PlaceEditor({this.editing});
  @override
  ConsumerState<_PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends ConsumerState<_PlaceEditor> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  final _address = TextEditingController();
  late PlaceKind _kind = widget.editing?.kind ?? PlaceKind.home;
  late int _radius = widget.editing?.radiusM ?? 150;
  late LatLng? _point = widget.editing?.point;

  /// 選んだ地点の出どころ。何を登録しようとしているかが分からないまま
  /// 保存させない ── 地図を出していないので、文字で示す必要がある。
  String? _pointLabel;
  List<AddressHit> _hits = const [];
  bool _busy = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) _pointLabel = '登録済みの位置';
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hits = await searchAddress(_address.text);
      setState(() => _hits = hits);
      if (hits.isEmpty) setState(() => _error = '見つかりませんでした。市区町村から入れると当たりやすいです');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useHere() {
    final loc = ref.read(locationProvider);
    if (loc == null) {
      setState(() => _error = 'いまの位置が取れていません。住所で入れてください');
      return;
    }
    setState(() {
      _point = loc.point;
      _pointLabel = 'いまいる場所';
      _hits = const [];
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_point == null || _name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final place = SavedPlace(
        id: widget.editing?.id ?? '',
        name: _name.text.trim(),
        point: _point!,
        radiusM: _radius,
        kind: _kind,
      );
      if (ref.read(mockModeProvider)) {
        ref.read(mockBackendProvider.notifier).savePlace(place);
      } else {
        await ref.read(apiProvider).addPlace({
          ...place.toJson(),
          if (widget.editing != null) 'id': widget.editing!.id,
        });
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存できませんでした: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(HinaSpace.m),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.editing == null ? '場所を追加' : '場所を編集', style: t.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '登録住所名', hintText: '例: 自宅 / ひなたの学校', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text('種類', style: t.bodySmall),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              for (final k in PlaceKind.values)
                ChoiceChip(
                  label: Text(k.label),
                  selected: _kind == k,
                  selectedColor: HinaColors.mist,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ]),
            const SizedBox(height: 16),
            Text('場所', style: t.bodySmall),
            const SizedBox(height: 4),
            if (_pointLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.check_circle, size: 18, color: HinaColors.stArrived),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_pointLabel!, style: t.bodyLarge)),
                ]),
              ),
            Row(children: [
              Expanded(child: HinaButton.secondary('いまいる場所を使う', icon: Icons.my_location, onPressed: _useHere)),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: '住所で探す',
                hintText: '例: 東京都千代田区丸の内1-9-1',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _busy ? null : _search),
              ),
              onSubmitted: (_) => _search(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
              ),
            if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_hits.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _hits.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(_hits[i].title, style: t.bodyLarge),
                    onTap: () => setState(() {
                      _point = _hits[i].point;
                      _pointLabel = _hits[i].title;
                      _hits = const [];
                    }),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // 半径は測位誤差と敷地の広さを吸収する幅。狭すぎると着いたのに
            // 通知が飛ばず、広すぎると通りかかっただけで飛ぶ。
            Text('着いたとみなす範囲: 半径 $_radius m', style: t.bodySmall),
            Slider(
              value: _radius.toDouble(),
              min: 50,
              max: 500,
              divisions: 9,
              label: '$_radius m',
              activeColor: HinaColors.sky,
              onChanged: (v) => setState(() => _radius = v.round()),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: HinaButton.ghost('やめる', onPressed: () => Navigator.of(context).pop())),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: HinaButton.primary(
                  '保存',
                  loading: _saving,
                  onPressed: _saving || _point == null || _name.text.trim().isEmpty ? null : _save,
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
