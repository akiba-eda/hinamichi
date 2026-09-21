# ヒナミチ セットアップ手順

[← README に戻る](../README.md)

実際に動かすための手順です。**テストだけなら鍵は要りません**
(`cd server && npm test` / `cd app && flutter test`)。

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
ORCA_ROUTER_DECIDE=orcarouter/hina-decide      # 例: anthropic/claude-sonnet-5
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
| POST | /api/senavi/ask | セナヴィへの問いかけ(平時)。座標は LLM に渡さない |
| POST | /api/me/register | プロフィール・アイコン・FCM トークン・同意 |
| POST | /api/me/area | 自分の市区町村コード(**何も保存しない**) |
| POST | /api/me/location | 最後にいた場所 + 到着/出発の判定 |
| POST | /api/me/status | 本人が書くメモ |
| POST | /api/me/places | よく行く場所の登録・削除 |
| POST | /api/friends/accept / share / send / message | 招待 / 共有設定 / 本人の送信 / AI代筆(承認ゲート) |
| POST | /api/meetup/start / end | 合流 |
| POST | /api/demo/fire / crowd / friends / reset | デモ操作 |
| POST | /api/route | 2点間の徒歩経路(ORS。失敗時は直線距離にフォールバック) |
| POST | /api/me/emergency | 緊急時情報(本名・住所・年齢・電話)。**LLM に渡らない別コレクション** |
| POST | /api/sos/request | 代理通報の依頼をフレンドへ。**119番には繋がらない** |
| POST | /api/sos/close | 依頼の取り下げ。開示していた個人情報も閉じる |
| GET | /api/health | 疎通確認(`{ok:true}`) |

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
