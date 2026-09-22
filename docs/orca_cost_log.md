# OrcaRouter コスト実測ログ

README ② の数値の根拠です。2026-09-22 02:31 JST に、本番の Vercel
(`https://hinamichi.vercel.app`) へ実際に地震を1件発火させ、
`server/scripts/lastIncident.ts` で Firestore から読み出した生の出力をそのまま貼っています。

| 段 | Router | 実際に選ばれたモデル | コスト |
|---|---|---|---|
| 一次判定「関係あるか」 | `hina-triage` | `google/gemini-2.5-flash-lite` | **$0.000034** |
| 避難先の判断 | `hina-decide` | `anthropic/claude-sonnet-5` | **$0.010814** |
| | | **合計(LLM 3 回)** | **$0.010848** |

関係ない災害は一次判定で止まるので、高いモデルは動きません。
経路・ハザード・避難所検索・標高・混雑は LLM を使いません。

**`AIに渡した情報` の payload に座標・氏名・端末IDが無いこと**も、この出力で確認できます。
避難場所の候補は仮名 A〜H に置き換わっています。

> **地名の粒度について**: この実測時点の `areaName` は町丁目(「千葉県猫実二丁目」)でした。
> 判断に町丁目は使っていない(距離とハザードを別に渡している)ため、2026-09-23 以降は
> 市区町村(「千葉県浦安市」)で止めています(`server/lib/tools/areaCode.ts`)。
> コストと判断の内容はこの変更で変わらないので、ログはそのまま残しています。

**`[approval] 30秒応答がなかったため自動でナビを開始しました`** が、
誰もボタンを押さなくても案内が始まったことの記録です。

再現するには:

```bash
cd server && npx tsx --env-file=.env scripts/lastIncident.ts
```

---

```text
=== incident snIyVfb6qaWkjvbEeMkS__<uid> ===
{
  state: 'guiding',
  alertTitle: '地震(最大震度6弱・千葉県猫実二丁目付近)',
  alertType: 'earthquake',
  shelter: '浦安公園',
  validatedBy: 'llm+rules',
  reasons: [ '津波浸水想定なし', '徒歩8分で到着', '混雑0%で余裕あり' ],
  cost: { totalUsd: 0.010848, llmCalls: 3 },
  routeProvider: 'ors',
  routePoints: 16,
  createdAt: '2026-09-21T17:31:48.090Z'
}

=== agentLog (13件) ===
[info] セナヴィが状況を確認しはじめました
        位置情報の取得元: デモ用の固定地点。座標はサーバー内でのみ使い、保存もAIへの送信もしません。
[tool_call] 現在地の市区町村を特定しました
        千葉県猫実二丁目
        payload: {"areaName":"千葉県猫実二丁目"}
[tool_call] 現在地のハザードを確認しました
        浸水: 0.5〜3m / 津波: 想定あり / 土砂: なし
        payload: {"flood":2,"floodLabel":"0.5〜3m","tsunami":2,"landslide":false,"source":"tiles"}
[llm_request] AIに渡した情報(一次判定)
        座標・氏名・端末IDは含まれていません
        payload: {"disaster":{"type":"earthquake","title":"地震(最大震度6弱・千葉県猫実二丁目付近)","intensity":"6弱","severity":0.85,"affectedAreaIncludesUser":true,"epicenterDistanceKm":7},"user":{"areaName":"千葉県猫実二丁目","hazardHere":{"flood":"0.5〜3m","tsunamiZone":true,"landslideZone":false}}}
[llm_response] セナヴィの判断: この災害はあなたに関係あります  (model=google/gemini-2.5-flash-lite router=hina-triage fallback=L1 1709ms $0.000034)
        ユーザーの地域が影響エリアに含まれています
[tool_call] 避難場所の候補を8件見つけました
        国土地理院 指定緊急避難場所(地震)から半径2.5km・徒歩順
        payload: [{"id":"A","walkMin":6,"direction":"南","elevationM":1.2,"flood":"浸水想定なし","tsunami":"0.5〜3m","landslide":false,"crowdPct":0,"full":false},{"id":"B","walkMin":8,"direction":"南","elevationM":2.6,"flood":"浸水想定なし","tsunami":"浸水想定なし","landslide":false,"crowdPct":0,"full":false},{"id":"C","walkMin":12,"direction":"東","elevationM":3.3,"flood":"浸水想定なし","tsunami":"浸水想定なし","landslide":false,"crowdPct":0,"ful
[llm_request] AIに渡した情報(避難先の判断)
        候補は仮名A〜Hと徒歩分・方角・標高・ハザード・混雑率のみ。座標・実名は渡していません
        payload: {"disaster":{"type":"earthquake","title":"地震(最大震度6弱・千葉県猫実二丁目付近)","intensity":"6弱"},"user":{"areaName":"千葉県猫実二丁目","hazardHere":{"flood":"0.5〜3m","tsunamiZone":true,"landslideZone":false}},"candidatesPreview":[{"id":"A","walkMin":6,"direction":"南","elevationM":1.2,"flood":"浸水想定なし","tsunami":"0.5〜3m","landslide":false,"crowdPct":0,"full":false},{"id":"B","walkMin":8,"direction":"南","elevationM":2.6,"
[tool_call] AIが避難場所の候補(8件)を取得しました
        災害種別: 地震
[llm_response] セナヴィの判断: 候補 B へ避難  (model=anthropic/claude-sonnet-5 router=hina-decide 14020ms $0.010814)
        津波浸水想定なし / 徒歩8分で到着 / 混雑0%で余裕あり(確信度 90%)
[validator] 安全ルールを通過: 候補 B
        浸水・津波・土砂・満員・距離の全ルールに適合
[tool_call] 徒歩ルートを引きました(約7分)
        OpenRouteService 徒歩経路
[cost] 今回のAIコスト: $0.0108(LLM 3 回)
        OrcaRouter usage.cost_usd の合計。経路・ハザード・避難所検索はLLM不使用
[approval] 30秒応答がなかったため自動でナビを開始しました
        操作できない状況を想定し、AIが判断した経路で案内を続けます
```
