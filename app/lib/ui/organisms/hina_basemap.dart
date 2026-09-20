import 'package:flutter/material.dart';

/// 地図の基図。
///
/// 選定の条件は「**キー登録なしで使えて、日本語のラベルが出ること**」。
/// CARTO(Voyager / Positron)は見た目がいちばん近かったが、いまは API キーが
/// 要る ── しかも **HTTP 200 のまま「API KEY REQUIRED」と焼き込んだ画像**を
/// 返してくるので、ステータスコードでは気づけない。採用しない。
///
/// ハザードの重ね合わせは基図に関係なく地理院のままなので、出典表記は
/// 「基図の出典 + ハザードの出典」を両方出す。
enum HinaBasemap {
  /// Esri ライトグレー + ラベル層。ほぼ無彩色で iOS 標準地図に近い。
  /// 町丁目まで日本語ラベルが入る。
  esriGray,

  /// 地理院 淡色を強く脱色して持ち上げたもの。日本の細かさ(避難所記号・
  /// 細街路)は最良。
  gsiSoft,

  /// 地理院 淡色そのまま。情報量は最大だが、ハザードマップらしい見た目。
  gsiPale,

  /// OpenStreetMap 標準。色味は強いが、施設名まで出る。
  osm;

  String get label => switch (this) {
        esriGray => 'ライトグレー',
        gsiSoft => '地理院 やわらかめ',
        gsiPale => '地理院 淡色',
        osm => 'OpenStreetMap',
      };

  String get note => switch (this) {
        esriGray => 'iOS標準地図に近い。ピンとルートがいちばん映える',
        gsiSoft => '地理院の細かさのまま彩度だけ落とす',
        gsiPale => '情報量は最大。避難所記号や細街路まで出る',
        osm => '施設名まで出るが色味は強い',
      };

  String get urlTemplate => switch (this) {
        esriGray => 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
        gsiSoft || gsiPale => 'https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png',
        osm => 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      };

  /// 地名・道路番号だけの透過レイヤー。Esri は基図とラベルが分かれている。
  String? get labelUrlTemplate => switch (this) {
        esriGray => 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
        _ => null,
      };

  int get maxNativeZoom => switch (this) {
        esriGray => 16, // これ以上は Esri 側に用意が無く、拡大表示になる
        gsiSoft || gsiPale => 18,
        osm => 19,
      };

  /// 出典表記は任意ではなく条件。基図を変えたら表記も変える。
  List<String> get attributions => switch (this) {
        esriGray => const ['Esri', 'HERE', 'Garmin', '© OpenStreetMap contributors'],
        gsiSoft || gsiPale => const ['地理院タイル'],
        osm => const ['© OpenStreetMap contributors'],
      };

  /// 色の当て直し。null ならタイルをそのまま使う。
  ColorFilter? get colorFilter => switch (this) {
        // ブランド側(温かい白)へわずかに寄せるだけ。
        gsiPale => const ColorFilter.matrix(<double>[
            1.02, 0, 0, 0, 6, //
            0, 1.0, 0, 0, 4,
            0, 0, 0.96, 0, 0,
            0, 0, 0, 1, 0,
          ]),
        // 輝度を残したまま彩度を 35% まで落とし、全体を持ち上げる。
        // 係数は Rec.709 の輝度(0.2126 / 0.7152 / 0.0722)から作った。
        gsiSoft => const ColorFilter.matrix(<double>[
            0.4882, 0.4649, 0.0469, 0, 14, //
            0.1382, 0.8149, 0.0469, 0, 14,
            0.1382, 0.4649, 0.3969, 0, 16,
            0, 0, 0, 1, 0,
          ]),
        esriGray || osm => null,
      };

  /// 配信元に繋がらないときの逃げ先。
  ///
  /// 地理院は日本の公的配信でいちばん落ちにくく、この用途の最後の砦なので、
  /// 何から落ちても最終的にここへ寄せる(地理院自身が落ちたときは諦める)。
  HinaBasemap? get fallback => this == gsiSoft ? null : gsiSoft;
}
