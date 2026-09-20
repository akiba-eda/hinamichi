import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../app/theme/hina_colors.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';

/// flutter_map wrapper: 地理院タイル(淡色) + hazard overlays + shelters + route + セナヴィ current-location marker.
/// No API key. Attribution is mandatory (地理院タイル / ハザードマップポータルサイト).
class HinaMap extends StatelessWidget {
  final MapController? controller;
  final LatLng center;
  final double zoom;
  final List<ShelterInfo> shelters;
  final ShelterInfo? selected;
  final List<LatLng> route;
  final bool showFlood, showTsunami, showLandslide;
  final SenaviMood mood;
  final ValueChanged<ShelterInfo>? onShelterTap;

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
  });

  static const gsiPale = 'https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png';
  static const hazardBase = 'https://disaportaldata.gsi.go.jp/raster';

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(initialCenter: center, initialZoom: zoom, minZoom: 5, maxZoom: 18, interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
      children: [
        // Base map, warmed slightly toward the brand palette.
        ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            1.02, 0, 0, 0, 6, //
            0, 1.0, 0, 0, 4,
            0, 0, 0.96, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: TileLayer(urlTemplate: gsiPale, userAgentPackageName: 'jp.hinamichi.app', maxNativeZoom: 18),
        ),
        if (showFlood) TileLayer(urlTemplate: '$hazardBase/01_flood_l2_shinsuishin_data/{z}/{x}/{y}.png', userAgentPackageName: 'jp.hinamichi.app', maxNativeZoom: 17, tileBuilder: (c, w, _) => Opacity(opacity: 0.35, child: w), errorTileCallback: (_, __, ___) {}),
        if (showTsunami) TileLayer(urlTemplate: '$hazardBase/04_tsunami_newlegend_data/{z}/{x}/{y}.png', userAgentPackageName: 'jp.hinamichi.app', maxNativeZoom: 17, tileBuilder: (c, w, _) => Opacity(opacity: 0.35, child: w), errorTileCallback: (_, __, ___) {}),
        if (showLandslide) ...[
          TileLayer(urlTemplate: '$hazardBase/05_dosekiryukeikaikuiki/{z}/{x}/{y}.png', userAgentPackageName: 'jp.hinamichi.app', maxNativeZoom: 17, tileBuilder: (c, w, _) => Opacity(opacity: 0.4, child: w), errorTileCallback: (_, __, ___) {}),
          TileLayer(urlTemplate: '$hazardBase/05_kyukeishakeikaikuiki/{z}/{x}/{y}.png', userAgentPackageName: 'jp.hinamichi.app', maxNativeZoom: 17, tileBuilder: (c, w, _) => Opacity(opacity: 0.4, child: w), errorTileCallback: (_, __, ___) {}),
        ],
        if (route.length > 1)
          PolylineLayer(polylines: [
            Polyline(points: route, color: Colors.white, strokeWidth: 9),
            Polyline(points: route, color: HinaColors.sky, strokeWidth: 6),
          ]),
        MarkerLayer(markers: [
          for (final s in shelters)
            Marker(
              point: s.point,
              width: 40,
              height: 40,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: onShelterTap == null ? null : () => onShelterTap!(s),
                child: Icon(Icons.location_on, size: s.id == selected?.id ? 40 : 30, color: s.id == selected?.id ? HinaColors.sun : (s.full ? HinaColors.stUnknown : HinaColors.sky), shadows: const [Shadow(color: Colors.black26, blurRadius: 4)]),
              ),
            ),
          Marker(point: center, width: 54, height: 62, alignment: Alignment.topCenter, child: _SenaviMarker(mood: mood)),
        ]),
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          showFlutterMapAttribution: false,
          attributions: [TextSourceAttribution('地理院タイル'), TextSourceAttribution('ハザードマップポータルサイト(国土交通省)')],
        ),
      ],
    );
  }
}

class _SenaviMarker extends StatelessWidget {
  final SenaviMood mood;
  const _SenaviMarker({required this.mood});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: HinaColors.sky, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))]),
        child: ClipOval(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Image.asset('assets/brand/marker_senavi.png', errorBuilder: (_, __, ___) => Image.asset(mood.smallAsset, errorBuilder: (_, __, ___) => const Icon(Icons.pets, color: Colors.white))),
          ),
        ),
      ),
      CustomPaint(size: const Size(14, 10), painter: _Tip()),
    ]);
  }
}

class _Tip extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Path()..moveTo(0, 0)..lineTo(s.width, 0)..lineTo(s.width / 2, s.height)..close();
    c.drawPath(p, Paint()..color = HinaColors.sky);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
