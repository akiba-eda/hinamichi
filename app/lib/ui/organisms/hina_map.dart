import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../app/theme/hina_colors.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../../core/rain_tiles.dart';
import '../../domain/social.dart';
import '../atoms/atoms.dart';
import 'hina_basemap.dart';

/// flutter_map wrapper: 地理院タイル(淡色) + hazard overlays + shelters + route + セナヴィ current-location marker.
/// No API key. Attribution is mandatory (地理院タイル / ハザードマップポータルサイト).
class HinaMap extends StatefulWidget {
  final MapController? controller;
  final LatLng center;
  final double zoom;
  final List<ShelterInfo> shelters;
  final ShelterInfo? selected;
  final List<LatLng> route;
  final bool showFlood, showTsunami, showLandslide;
  final SenaviMood mood;
  final ValueChanged<ShelterInfo>? onShelterTap;

  /// 基図の見た目。設定から切り替えられる。
  final HinaBasemap basemap;

  /// 位置を許可してくれたフレンド。タップで詳細を開く。
  final List<FriendOnMap> friends;
  final ValueChanged<FriendOnMap>? onFriendTap;

  /// 進行中の合流。地点に旗を立てる。
  final Meetup? meetup;

  /// 雨雲レーダーの観測時刻。null なら重ねない。
  /// **これが入っている間はハザードを出さない** ── 同じ場所に色を重ねると
  /// どちらも読めなくなるため。
  final RainFrame? rain;

  const HinaMap({
    super.key,
    this.controller,
    required this.center,
    this.zoom = 15,
    this.shelters = const [],
    this.selected,
    this.route = const [],
    this.showFlood = true,
    this.showTsunami = false,
    this.showLandslide = false,
    this.mood = SenaviMood.normal,
    this.onShelterTap,
    this.basemap = HinaBasemap.esriGray,
    this.friends = const [],
    this.onFriendTap,
    this.meetup,
    this.rain,
  });

  static const hazardBase = 'https://disaportaldata.gsi.go.jp/raster';

  @override
  State<HinaMap> createState() => _HinaMapState();
}

class _HinaMapState extends State<HinaMap> {
  /// 基図のタイルが読めなかった回数。一定数を超えたら配信元を諦めて逃がす。
  int _failures = 0;
  HinaBasemap? _fellBackTo;

  /// 逃げるしきい値。画面には十数枚しか出ないので、数枚の失敗は通信の揺らぎ、
  /// 5 枚落ちたら配信元の問題とみなす。
  static const _giveUpAfter = 5;

  HinaBasemap get _basemap => _fellBackTo ?? widget.basemap;

  @override
  void didUpdateWidget(HinaMap old) {
    super.didUpdateWidget(old);
    // 人が選び直したら、逃げた状態は解除してもう一度その基図を試す。
    if (old.basemap != widget.basemap) {
      _failures = 0;
      _fellBackTo = null;
    }
  }

  void _onTileFailed(Object error) {
    if (_fellBackTo != null) return; // 逃げた先で落ちても、もう逃げ先が無い
    _failures++;
    if (_failures < _giveUpAfter) return;
    final to = widget.basemap.fallback;
    if (to == null) return;
    debugPrint('[HinaMap] ${widget.basemap.name} unreachable ($_failures tiles) -> ${to.name}');
    if (mounted) setState(() => _fellBackTo = to);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      _map(context),
      if (_fellBackTo != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _FallbackNotice(from: widget.basemap, to: _fellBackTo!),
        ),
    ]);
  }

  Widget _map(BuildContext context) {
    return FlutterMap(
      mapController: widget.controller,
      options: MapOptions(initialCenter: widget.center, initialZoom: widget.zoom, minZoom: 5, maxZoom: 18, interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
      children: [
        ..._baseLayers(context),
        if (widget.rain != null)
          _rain(widget.rain!)
        else ...[
          if (widget.showFlood) _hazard('01_flood_l2_shinsuishin_data', 0.35),
          if (widget.showTsunami) _hazard('04_tsunami_newlegend_data', 0.35),
          if (widget.showLandslide) ...[
            _hazard('05_dosekiryukeikaikuiki', 0.4),
            _hazard('05_kyukeishakeikaikuiki', 0.4),
          ],
        ],
        if (widget.route.length > 1)
          PolylineLayer(polylines: [
            Polyline(points: widget.route, color: Colors.white, strokeWidth: 9),
            Polyline(points: widget.route, color: HinaColors.sky, strokeWidth: 6),
          ]),
        // alignment.topCenter は「マーカーの下端が point に来る」意味なので、
        // 雫の先端がちょうど座標を指す。
        MarkerLayer(markers: [
          for (final s in widget.shelters)
            Marker(
              point: s.point,
              width: s.id == widget.selected?.id ? 36 : 28,
              height: s.id == widget.selected?.id ? 46 : 36,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: widget.onShelterTap == null ? null : () => widget.onShelterTap!(s),
                child: CustomPaint(
                  painter: _Pin(s.id == widget.selected?.id ? HinaColors.sun : (s.full ? HinaColors.stUnknown : HinaColors.sky)),
                ),
              ),
            ),
          // フレンドは自分より一回り小さく。自分の現在地が埋もれないように。
          for (final f in widget.friends)
            Marker(
              point: f.location.point,
              width: 40,
              height: 50,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: widget.onFriendTap == null ? null : () => widget.onFriendTap!(f),
                child: _FriendMarker(f),
              ),
            ),
          if (widget.meetup != null)
            Marker(
              point: widget.meetup!.point,
              width: 38,
              height: 48,
              alignment: Alignment.topCenter,
              child: Stack(alignment: Alignment.topCenter, children: [
                // 災害から作った合流は赤。バナーと色を揃えて、平時の待ち合わせと区別する。
                Positioned.fill(child: CustomPaint(painter: _Pin(widget.meetup!.fromIncident ? HinaColors.alert : HinaColors.stArrived))),
                const Positioned(top: 6, child: Icon(Icons.handshake, size: 18, color: Colors.white)),
              ]),
            ),
          Marker(point: widget.center, width: 50, height: 62, alignment: Alignment.topCenter, child: _SenaviMarker(mood: widget.mood)),
        ]),
        RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          showFlutterMapAttribution: false,
          attributions: [
            // 出典表記は任意ではなく条件。基図を変えたら表記も変える。
            for (final a in _basemap.attributions) TextSourceAttribution(a),
            if (widget.rain != null)
              const TextSourceAttribution('高解像度降水ナウキャスト(気象庁)')
            else if (widget.showFlood || widget.showTsunami || widget.showLandslide)
              const TextSourceAttribution('ハザードマップポータルサイト(国土交通省)'),
          ],
        ),
      ],
    );
  }

  /// ハザードの重ね。
  ///
  /// 地理院のハザードタイルは「想定区域が無い場所にはタイルが無い」ので、
  /// 404 が大量に出るのが正常。`silenceExceptions` を立てないと画像デコード層が
  /// 例外を投げ続け、平常時のコンソールが埋まって本当の異常が見えなくなる。
  Widget _hazard(String layer, double opacity) => TileLayer(
        urlTemplate: '${HinaMap.hazardBase}/$layer/{z}/{x}/{y}.png',
        userAgentPackageName: 'jp.hinamichi.app',
        maxNativeZoom: 17,
        tileBuilder: (c, w, _) => Opacity(opacity: opacity, child: w),
        errorTileCallback: (_, __, ___) {},
        tileProvider: NetworkTileProvider(silenceExceptions: true),
      );

  /// 雨雲の重ね。
  ///
  /// z=10 までしか配信が無いので、拡大時はそのタイルを引き伸ばす
  /// (`maxNativeZoom`)。指定しないと拡大した瞬間に雨雲だけ消える。
  Widget _rain(RainFrame f) => TileLayer(
        urlTemplate: f.urlTemplate,
        userAgentPackageName: 'jp.hinamichi.app',
        maxNativeZoom: RainFrame.maxNativeZoom,
        tileBuilder: (c, w, _) => Opacity(opacity: 0.6, child: w),
        errorTileCallback: (_, __, ___) {},
        tileProvider: NetworkTileProvider(silenceExceptions: true),
      );

  /// 基図。Esri のように基図とラベルが分かれている配信元では 2 枚重ねる。
  List<Widget> _baseLayers(BuildContext context) {
    final b = _basemap;
    final layer = TileLayer(
      urlTemplate: b.urlTemplate,
      userAgentPackageName: 'jp.hinamichi.app',
      maxNativeZoom: b.maxNativeZoom,
      // 配信元が落ちたときに気づけるようにする。ここを黙らせると
      // 「タイルが出ない」以外の手がかりが残らない。
      // (地理院タイルは日本国外を持っていないので、海外では全部 404 になる)
      errorTileCallback: (tile, error, _) {
        debugPrint('[HinaMap] base tile failed z=${tile.coordinates.z} x=${tile.coordinates.x} y=${tile.coordinates.y}: $error');
        _onTileFailed(error);
      },
    );
    final f = b.colorFilter;
    return [
      f == null ? layer : ColorFiltered(colorFilter: f, child: layer),
      if (b.labelUrlTemplate != null)
        TileLayer(
          urlTemplate: b.labelUrlTemplate!,
          userAgentPackageName: 'jp.hinamichi.app',
          maxNativeZoom: b.maxNativeZoom,
          // ラベルだけ落ちても地図は読めるので、ここでは逃がさない。
          errorTileCallback: (_, __, ___) {},
        ),
    ];
  }
}

/// デザイン書「地図上の現在地マーカー(セナヴィ小アイコン)」。
/// 雫型のピンの中にセナヴィの顔。円と三角を別々に置くと継ぎ目が見えるので、
/// ピンは一筆のパスで描いて、その上に顔を載せる。
class _SenaviMarker extends StatelessWidget {
  final SenaviMood mood;
  const _SenaviMarker({required this.mood});
  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.topCenter, children: [
      const Positioned.fill(child: CustomPaint(painter: _Pin(HinaColors.sky))),
      Positioned(
        top: 5,
        child: ClipOval(
          child: SizedBox(
            width: 40,
            height: 40,
            child: Image.asset(
              'assets/brand/marker_senavi.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.asset(mood.smallAsset, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.white, child: Icon(Icons.pets, color: HinaColors.sky))),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// 雫型のピン。先端が下端に来るので、Marker.alignment: topCenter と組で座標を指す。
class _Pin extends CustomPainter {
  final Color color;
  const _Pin(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = w / 2;
    final path = Path()
      ..moveTo(r, h)
      ..cubicTo(r - r * 0.34, h * 0.64, 0, r * 1.5, 0, r)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r), clockwise: true)
      ..cubicTo(w, r * 1.5, r + r * 0.34, h * 0.64, r, h)
      ..close();
    canvas.drawShadow(path, Colors.black54, 3, true);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _Pin old) => old.color != color;
}

/// 地図上のフレンド。状態色の雫ピンにアイコンを載せる。
///
/// 一覧・詳細・地図でアイコンを揃えると、地図上の点と名前が頭の中で結びつく。
/// 色(安否)と顔(誰か)を同時に拾えるので、災害時に一覧へ戻らなくて済む。
class _FriendMarker extends StatelessWidget {
  final FriendOnMap f;
  const _FriendMarker(this.f);

  @override
  Widget build(BuildContext context) {
    final c = statusColor(f.status.state);
    return Stack(alignment: Alignment.topCenter, children: [
      Positioned.fill(child: CustomPaint(painter: _Pin(c))),
      Positioned(
        top: 4,
        child: HinaAvatar(
          imageBase64: f.entry.avatarImage,
          moodName: f.entry.avatarMood,
          fallbackName: f.entry.displayName,
          size: 32,
          ringColor: Colors.white,
        ),
      ),
      // 位置が古いときは印を薄くして、現在地と読み違えないようにする。
      if (f.location.isStale)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(decoration: BoxDecoration(color: HinaColors.bg.withValues(alpha: 0.45))),
          ),
        ),
    ]);
  }
}

/// 基図の配信元に繋がらず、別の基図に切り替えたことを伝える帯。
/// 黙って別の地図に変わると「表示がおかしい」と誤解されるので、必ず出す。
class _FallbackNotice extends StatelessWidget {
  final HinaBasemap from, to;
  const _FallbackNotice({required this.from, required this.to});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: HinaColors.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const HinaIconView(HinaIcon.warning, size: 18, color: HinaColors.stEvacuating),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${from.label}に繋がらないため${to.label}で表示しています',
              style: const TextStyle(fontSize: 12, color: HinaColors.ink),
            ),
          ),
        ]),
      );
}
