# ヒナミチ (HINAMICHI) — 災害時、あなたの代わりに判断して安全な道へ

AI HACK 2026 #2「業務を自律化するAIエージェント」応募作品。

AIナビゲーター **セナヴィ (SENAvi)** が、気象庁の速報を掴むところから、
あなたに関係があるかの判定、避難先の選定、道案内、家族への安否連絡までを、
**人の操作を挟まずに**進めます。

平時は雨雲レーダーと見守りのアプリとして動きます。災害の日だけ開くアプリは、
その日も開かれないからです。

---

## 審査基準への回答

### ④ 自律性 — 人が操作しなくても、ここまで進む

```
cron-job.org (2分ごと)
  └→ GET /api/watch/disasters
       └→ 気象庁の防災情報XMLフィード / P2P地震情報 を読む
            └→ 新しい警報だけを alerts に書く          ← ここまで人は関与しない
                 └→ その市区町村にいる端末にだけ通知    ← 位置はサーバーに無い(後述)
                      └→ セナヴィが起動
                           ├ 一次判定: この災害はあなたに関係あるか
                           ├ 避難場所を8件集め、ハザード・標高・混雑・道のりを付ける
                           ├ 災害種別に合う候補を選ぶ
                           └ 安全ルールで検算する(LLMの答えを鵜呑みにしない)
                                └→ 30秒で自動承認して案内開始   ← 押さなくても進む
                                     ├ 行き先が満員 → 自動で選び直し
                                     ├ 100m圏内に入る → 自動で到着判定
                                     └ 家族へ「確認中 → 避難中 → 到着」を自動送信
```

実際に動いている証拠は `docs/api_integration_tasks.md` と、アプリ内の
**設定 →「判断の記録」**で確認できます。

### ① セキュリティ — 座標を渡さない・置かない

**LLM に位置を渡していません。** 避難場所の候補は仮名 A〜H に置き換え、
特徴だけを渡します。実際に送っている内容:

```json
{"disaster": {"type":"earthquake","title":"地震(最大震度6弱・千葉県猫実二丁目付近)","intensity":"6弱"},
 "user": {"areaName":"千葉県猫実二丁目","hazardHere":{"flood":"0.5〜3m","tsunamiZone":true}},
 "candidatesPreview": [{"id":"A","walkMin":6,"direction":"南","elevationM":1.2,
                        "flood":"浸水想定なし","tsunami":"0.5〜3m","crowdPct":0}]}
```

座標・氏名・連絡先・端末IDは含まれません。`assertNoCoordinates()`
(`server/lib/agent/abstraction.ts`)が送信前に機械的に検査します。

**警報の絞り込みでも、位置をサーバーに置きません。** 端末が自分の市区町村
コードで FCM トピックを購読し、サーバーは警報の対象市区町村のトピックへ送る
── この形なら、サーバーは誰がどこにいるかを知らないまま、その土地の人にだけ
鳴らせます(`server/lib/alerts.ts` の `broadcastAlert`)。

フレンドへの位置共有は**相手ごとの許可制**で、既定は共有しません。
許可されていない相手の位置は Firestore のルールが弾きます
(`firebase/firestore.rules`)。

### ② コストパフォーマンス — 1件 $0.013

判断を 2 段に分け、**安いモデルで足切りしてから高いモデルを使います**。
実測値(2026-09-21、実データでの1件):

| 段 | Router | モデル | コスト |
|---|---|---|---|
| 一次判定「関係あるか」 | `hina-triage` | `google/gemini-2.5-flash-lite` | **$0.000034** |
| 避難先の判断 | `hina-decide` | `anthropic/claude-sonnet-5` | **$0.01301** |

関係ない災害はここで止まるので、高いモデルは動きません。
コストは OrcaRouter の `/v1/generation` で確定値を照合して記録します
(インライン値と食い違う場合は確定値が正)。

外部データは**すべて無料・カード登録不要**です。気象庁、国土地理院、
ハザードマップポータル、OpenRouteService、P2P地震情報、cron-job.org。
Firebase は Spark、Vercel は Hobby。

### ③ 信頼性・堅牢性 — 落ちても案内を止めない

| 落ちたもの | どうするか |
|---|---|
| LLM(遅い・不正な答え) | **安全ルールだけで選定して案内を続ける**(`validatedBy: 'fallback'`) |
| OrcaRouter の第一候補 | フォールバックチェーンで次のモデルへ |
| 経路API(OpenRouteService) | 直線距離 + 80m/分の目安に切り替え |
| 地図タイルの配信元 | 5枚失敗したら別の配信元へ逃げる |
| 圏外 | 位置を端末に溜めて、繋がったら古い順に送る |
| 逆ジオ・標高・混雑 | 取れなかった項目だけ落として、判断は続ける |

テストは server 43 件 / app 26 件。バリデータ、フォールバック、データ最小化、
ハザードの色判定、経路の残距離、気象XMLの解析を固定しています。

### ⑤ アイデア・独創性 — 平時と災害時を同じ仕組みで賄う

防災アプリの最大の問題は「その日まで開かれない」ことです。ヒナミチは
到着通知・見守り・雨雲レーダー・やりとりを**災害時と同じ部品**で動かします。

- よく行く場所への到着判定 = 避難場所への到着判定(同じジオフェンス)
- 家族への「自宅に着いたよ」= 「避難所に着いたよ」(同じ経路)
- 平時の雨雲レーダー = 豪雨警報時のハザード判断(同じタイル)

普段から使っている場所にスタンプの「無事」「助けて」があるから、とっさに押せます。

---

## 構成

```
hinamichi/
  app/        Flutter (iOS / Android)            ← UI。設計書 §17
  server/     Vercel Functions (Node/TS)         ← エージェント本体・実データツール・OrcaRouter
  firebase/   Firestore rules / indexes          ← Spark プランのまま
  docs/       設計書・API繋ぎ込みのタスク表
```

| 使っているもの | 用途 | 料金 |
|---|---|---|
| **OrcaRouter** | LLM のルーティング・フォールバック・コスト照合 | 提供クレジット |
| Firebase (Spark) | 匿名認証 / Firestore / FCM | 無料 |
| Vercel (Hobby) | エージェント API(関数1本に集約) | 無料 |
| cron-job.org | 2分ごとの災害監視 | 無料 |
| 気象庁 防災情報XML | 気象警報・注意報 | 無料・登録不要 |
| 気象庁 降水ナウキャスト | 雨雲レーダー | 無料・登録不要 |
| 国土地理院 | 避難場所 / 標高 / 逆ジオ / 地図タイル | 無料・登録不要 |
| ハザードマップポータル | 浸水・津波・土砂の想定区域 | 無料・登録不要 |
| P2P地震情報 | 地震速報 | 無料・登録不要 |
| OpenRouteService | 徒歩経路・多地点距離 | 無料(要キー) |

---

## 0. 必要なアカウント(すべて無料)

| サービス | 用途 | 取るもの |
|---|---|---|
| Firebase (Spark) | Auth(匿名) / Firestore / FCM | プロジェクト + **サービスアカウント JSON**(プロジェクト設定 → サービスアカウント → 新しい秘密鍵) |
| Vercel (Hobby) | エージェント API | GitHub 連携でデプロイ |
| cron-job.org | 2分ごとの災害監視 | ジョブ 1 本 |
| OpenRouteService | 徒歩ルート | API キー(メール登録) |
| OrcaRouter | LLM(必須スポンサー) | API キー(取得済み) |

---

## 1. サーバー(server/)

```bash
cd server
npm install
cp .env.example .env         # 値を埋める(下記)
npm test                      # 純粋ロジックのユニットテスト(バリデータ・フォールバック・データ最小化・ハザード色)
npm run typecheck
# 以下は .env を読むので --env-file が要る
npx tsx --env-file=.env scripts/orcaCheck.ts     # OrcaRouter 疎通: モデル一覧 / usage.cost_usd / tool calling
npx tsx --env-file=.env scripts/smoke.ts 35.6588 139.9013   # 実データ疎通(南行徳駅): 逆ジオ・ハザード・避難所・標高・経路
npx tsx --env-file=.env scripts/lastIncident.ts  # 直近の判断とAgentLogをFirestoreから直読み
npx vercel dev                # http://localhost:3000
```

`.env`
```
ORCA_API_KEY=sk-orca-...
ORCA_ROUTER_TRIAGE=orcarouter/hina-triage      # コンソールで作る(§1.2)。未作成なら直接モデルIDでも可 例: openai/gpt-4o-mini
ORCA_ROUTER_DECIDE=orcarouter/hina-decide      # 例: anthropic/claude-sonnet-4.5
ORCA_USE_PROMPT_REF=false                      # Prompts を登録したら true
ORCA_FALLBACK_TRIAGE=openai/gpt-4o-mini,google/gemini-2.5-flash-lite
ORCA_FALLBACK_DECIDE=openai/gpt-4o,google/gemini-2.5-pro   # orcaCheck の一覧にある ID に置き換える
FIREBASE_SERVICE_ACCOUNT_B64=$(base64 -i serviceAccount.json | tr -d '\n')
ORS_API_KEY=...
CRON_TOKEN=<ランダム文字列>
DEMO_ADMIN_UIDS=                               # 空=誰でもデモ操作可(ハッカソン中はこれでOK)
```

### 1.1 Vercel にデプロイ
1. GitHub にこのリポジトリを push → Vercel で **Root Directory = `server`** として Import
2. Environment Variables に上記 `.env` の中身を登録(`FIREBASE_SERVICE_ACCOUNT_B64` は 1 行の base64)
3. デプロイ後 `https://<project>.vercel.app/api/health` が `{ok:true}` を返せば OK
4. **cron-job.org** で `GET https://<project>.vercel.app/api/watch/disasters?token=<CRON_TOKEN>` を **2 分間隔**で登録

### 1.2 OrcaRouter コンソール設定(設計書 §18.2 / 30 分)
1. **Named Router** を 2 本
   - `hina-triage`: strategy **cheapest**、allowed models 例 `openai/gpt-4o-mini, google/gemini-2.5-flash-lite, deepseek/*`
   - `hina-decide`: strategy **quality**(または balanced)、allowed models は上位 3〜4 本
   - 両方 Frontier Escalation = **Manual**、Escalate to = 最上位モデル(却下時の一回昇格 `X-OrcaRouter-Escalate: once` が効く)
2. **Prompts** に 2 本登録し label `production`(本文は `server/lib/agent/prompts.ts` の `TRIAGE_SYSTEM` / `DECIDE_SYSTEM` をコピー。変数 `{{disaster_type}}` `{{area_name}}` をそのまま使う)
   - `hina-triage-system` / `hina-decide-system`(任意で `hina-message-system`)
   - 登録したら `ORCA_USE_PROMPT_REF=true`
3. **Guardrail**: type PII、stage input、action mask、entities `email, phone`、`credit_card: block` → デモ用 API キーにアタッチ(承認カードから電話番号入りメッセージを送ると `[PHONE]` になる)
4. (余裕があれば)**Firewall** rule: stage response / tool_name_glob `notify_*` / verdict pending_approval

### 1.3 API 一覧
| Method | Path | 用途 |
|---|---|---|
| GET | /api/watch/disasters?token= | **実データ監視(cron が2分ごとに叩く)** |
| POST | /api/agent/run | アラートに対してエージェント起動 |
| POST | /api/agent/action | start(承認) / later / arrived / safe_zone / close |
| POST | /api/agent/reselect | 再選定(満員 / 別の場所へ) |
| POST | /api/agent/position | 誘導中の位置 → 到着ジオフェンス(100m) |
| POST | /api/shelters/nearby | 平時の周辺避難所 + 現在地ハザード |
| POST | /api/weather/nowcast | 雨雲ナウキャスト(直近60分) |
| POST | /api/me/register | プロフィール・アイコン・FCM トークン・同意 |
| POST | /api/me/area | 自分の市区町村コード(**何も保存しない**) |
| POST | /api/me/location | 最後にいた場所 + 到着/出発の判定 |
| POST | /api/me/status | 本人が書くメモ |
| POST | /api/me/places | よく行く場所の登録・削除 |
| POST | /api/friends/accept / share / send / message | 招待 / 共有設定 / 本人の送信 / AI代筆(承認ゲート) |
| POST | /api/meetup/start / end | 合流 |
| POST | /api/demo/fire / crowd / friends / reset | デモ操作 |

Vercel Hobby は 1 デプロイ 12 関数までなので、全部を `api/[...path].ts`
1 本に束ねて `lib/routes/` へ振り分けています。URL は変わりません。

すべて `Authorization: Bearer <Firebase ID token>`(cron は token クエリ)。

---

## 2. Firebase

```bash
cd firebase
npm i -g firebase-tools && firebase login
firebase use <project-id>
firebase deploy --only firestore:rules,firestore:indexes
```
Authentication → **匿名**を有効化。Cloud Messaging はそのまま(Android は google-services.json、iOS は APNs 無しなのでプッシュ非対応=見守り端末として使う)。

---

## 3. アプリ(app/)

```bash
cd app
flutter pub get
dart pub global activate flutterfire_cli
flutterfire configure --project=<project-id>   # lib/firebase_options.dart と各 OS の設定ファイルを生成
flutter analyze && flutter test
flutter run -d <android> --dart-define=API_BASE=https://<project>.vercel.app
```
- API の向き先は設定画面からも変更可(LAN 開発時 `http://<MacのIP>:3000`)
- 設定 → **DEMO モード** ON → 発火パネル(地震 / 豪雨 / 津波 / 満員 / 移動シミュレーション / LLM 障害注入 / モックフレンド)
- 設定 → **Widget ギャラリー** で全部品を全状態で確認(デザイン書と並べて見比べる)
- `ios/` `android/` はリポジトリに入っているので `flutter create` は不要。
  位置情報の用途説明なども当たった状態です

### 端末の役割
- **Android = 本人端末(主デモ機)**: プッシュあり
- **iPhone = 見守り端末**: Friends 画面は Firestore 購読なのでプッシュ不要。無料署名は 7 日で切れるので前日に入れ直す

---

## 4. デモの流れ(発表 4 分)
0. **雨雲ボタン** → いま降っている雨が地図に乗る(平時の使い道)
1. 平時 Home(現地の実データ: 避難所ピン + 浸水想定)
2. 設定 → DEMO → **地震** → Home に戻ると 2〜3 秒で「◯◯へ。徒歩◯分」+ 理由 3 点、家族には「確認中→避難中」
3. 「このルートで行く」(押さなければ 30 秒で自動開始)
4. **満員** → 自動で次点へ、フレンドにも行き先変更
5. **豪雨**で発火し直す → 浸水想定外の別の場所へ(判断が変わる)
6. 記録タブ →「審査員向け」: AI に渡した入力に座標が無い / 却下 → 昇格 / モデル名とコスト
7. **LLM 障害注入** ON で発火 → 安全ルールで選定され案内は止まらない
8. 移動シミュレーション → 到着 → 家族に「到着」

---

## 5. 設計書
`docs/ヒナミチ_設計書_v1.md`(審査 5 基準への回答 / エージェント設計 / OrcaRouter 活用マトリクス / UI 実装設計 / 無課金構成)
