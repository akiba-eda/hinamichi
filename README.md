# ヒナミチ (HINAMICHI) — 災害時、あなたの代わりに判断して安全な道へ

AI HACK 2026 #2「業務を自律化するAIエージェント」応募作品。
AIナビゲーター **セナヴィ (SENAvi)** が、速報 → 関係判定 → 避難先選定 → 道案内 → 家族への状態共有までを自律的に進めます。

```
hinamichi/
  app/        Flutter (iOS / Android)            ← UI。設計書 §17
  server/     Vercel Functions (Node/TS)         ← エージェント本体・実データツール・OrcaRouter。設計書 §6, §7, §15, §18, §20
  firebase/   Firestore rules / indexes           ← Spark プランのまま
  docs/       設計書
```

全部 **カード登録なしの無料枠** で動きます(Firebase Spark / Vercel Hobby / cron-job.org / OpenRouteService / 地理院タイル)。

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
npx tsx scripts/orcaCheck.ts  # OrcaRouter 疎通: モデル一覧 / usage.cost_usd / tool calling
npx tsx scripts/smoke.ts 35.6588 139.9013   # 実データツール疎通(南行徳駅): 逆ジオ・ハザード・避難所・標高・経路
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
| POST | /api/me/register | プロフィール・FCM トークン・同意 |
| POST | /api/agent/run | アラートに対してエージェント起動(通知を開いた時) |
| POST | /api/agent/action | start(承認) / later / arrived / safe_zone / close |
| POST | /api/agent/reselect | 再選定(満員 / 別の場所へ) |
| POST | /api/agent/position | 誘導中の位置 → 到着ジオフェンス(100m) |
| POST | /api/shelters/nearby | 平時の周辺避難所 + 現在地ハザード |
| POST | /api/friends/accept, /share, /message | 招待コード / 自動共有 / 承認済み自由文送信 |
| GET | /api/watch/disasters?token= | 実データ監視(cron) |
| POST | /api/demo/fire, /crowd, /friends, /reset | デモ操作 |

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
bash tool/setup.sh                 # flutter create(android/ios 生成)→ pub get → 権限パッチ → アイコン生成
dart pub global activate flutterfire_cli
flutterfire configure --project=<project-id>   # lib/firebase_options.dart と各 OS の設定ファイルを生成
flutter analyze && flutter test
flutter run -d <android> --dart-define=API_BASE=https://<project>.vercel.app
```
- API の向き先は設定画面からも変更可(LAN 開発時 `http://<MacのIP>:3000`)
- 設定 → **DEMO モード** ON → 発火パネル(地震 / 豪雨 / 津波 / 満員 / 移動シミュレーション / LLM 障害注入 / モックフレンド)
- 設定 → **Widget ギャラリー** で全部品を全状態で確認(デザイン書と並べて見比べる)
- セナヴィの画像は `app/assets/README.md` の通り差し替えるだけ(今はプレースホルダー)

### 端末の役割
- **Android = 本人端末(主デモ機)**: プッシュあり
- **iPhone = 見守り端末**: Friends 画面は Firestore 購読なのでプッシュ不要。無料署名は 7 日で切れるので前日に入れ直す

---

## 4. デモの流れ(発表 4 分)
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
