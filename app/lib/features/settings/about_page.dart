import 'package:flutter/material.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/senavi.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';

/// データの出所と、何をどこへ渡しているか。
///
/// 画面ごとに注釈を足すと説明文ばかりになって本文が読まれないので、
/// 断り書きはここ 1 か所にまとめる。数字の意味を疑ったときに辿り着ける
/// 場所があれば足りる。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('データについて')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.all(HinaSpace.m),
          child: HinaCard(
            child: SenaviSpeech(
              mood: SenaviMood.normal,
              text: 'ぼくが見ているもの',
              sub: '画面に出る数字がどこから来ているかをまとめています',
              avatarSize: 52,
            ),
          ),
        ),

        const SectionHeader('画面の数字'),
        const _Item(
          title: '混雑',
          body: 'ヒナミチでその避難場所へ向かっている人の割合です。'
              '実際の避難所の受け入れ状況ではありません。'
              '収容人数は一律300人と仮定しています — 国土地理院の避難場所データに'
              '収容人数が含まれていないためです。'
              '自治体の開設情報との連携は今後の課題です。',
        ),
        const _Item(
          title: '浸水・津波・土砂',
          body: 'ハザードマップポータルサイト(国土交通省)のタイルを読み、'
              'いる場所がどの想定区域に当たるかを判定しています。',
        ),
        const _Item(
          title: '徒歩◯分',
          body: 'OpenRouteService の徒歩経路から算出します。'
              '取得できないときは直線距離を毎分80mで割った目安に切り替わります。',
        ),
        const _Item(
          title: '標高',
          body: '国土地理院の標高データです。豪雨や津波では、近さより高さを優先します。',
        ),

        const SectionHeader('AI に渡しているもの'),
        const _Item(
          title: '渡していないもの',
          body: '座標・氏名・連絡先・端末ID は AI に渡していません。'
              '避難場所の候補も仮名(A〜H)に置き換えて渡します。',
          emphasis: true,
        ),
        const _Item(
          title: '渡しているもの',
          body: '市区町村レベルの地名、災害の種別と規模、'
              '候補ごとの徒歩分・方角・標高・ハザード・混雑率です。',
        ),
        const _Item(
          title: '確かめ方',
          body: '設定 →「判断の記録」→「審査員向け」で、実際に AI へ渡した内容を'
              'そのまま表示しています。',
        ),

        const SectionHeader('家族・友人に届くもの'),
        const _Item(
          title: '安否',
          body: '安全 / 確認中 / 避難中 / 到着 / 不明 の5つは、追加した相手に自動で届きます。',
        ),
        const _Item(
          title: '現在地',
          body: '相手ごとに許可したときだけ届きます。既定は共有しません。'
              '届くのは最後に受け取った位置で、いつの時点かを必ず添えて表示します。',
        ),

        const SectionHeader('出典'),
        Padding(
          padding: const EdgeInsets.fromLTRB(HinaSpace.m, 0, HinaSpace.m, HinaSpace.m),
          child: Text(
            '地理院タイル / ハザードマップポータルサイト(国土交通省) / '
            '指定緊急避難場所データ(国土地理院) / 標高API(国土地理院) / '
            'OpenRouteService / P2P地震情報 / 気象庁 / '
            'Esri・HERE・Garmin・OpenStreetMap contributors',
            style: t.bodySmall,
          ),
        ),
      ]),
    );
  }
}

class _Item extends StatelessWidget {
  final String title, body;
  final bool emphasis;
  const _Item({required this.title, required this.body, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(HinaSpace.m, 0, HinaSpace.m, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(color: emphasis ? HinaColors.sun : HinaColors.line, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(title, style: t.titleMedium),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(body, style: t.bodyMedium?.copyWith(color: HinaColors.inkSub, height: 1.6)),
        ),
      ]),
    );
  }
}
