# API 繋ぎ込みタスク

アプリ側の画面は `lib/mock/mock_backend.dart` の仮データで**全状態が動く状態**になっている。
ここから本物のサーバー・Firestore に差し替えるための作業を洗い出したもの。

## 前提: いま何がモックか

設定 → 開発者向け → **モックモード** を ON にすると、`providers.dart` の各プロバイダが
Firestore / Vercel API の代わりに `MockBackend` を見る。分岐は全部 `ref.watch(mockModeProvider)` の
1 行で、OFF にすれば即座に本物側へ戻る。**本番コードに `if (mock)` が散らばらないよう、分岐は
providers.dart と AgentController だけに閉じている。**

| 画面が使うもの | プロバイダ | モックの供給元 | 本物の供給元 |
|---|---|---|---|
| 周辺の避難所・ハザード | `nearbyProvider` | `MockBackend.sheltersAround()` (現在地からの相対座標で生成) | `POST /api/shelters/nearby` |
| インシデント状態 | `latestIncidentProvider` | `MockState.incident` | Firestore `incidents` (uid + createdAt desc) |
| AgentLog | `agentLogProvider` | `MockState.log` | Firestore `incidents/{id}/agentLog` |
| フレンド一覧 | `friendsProvider` | `MockBackend.friends` (5人固定) | Firestore `friends/{uid}/list` |
| フレンドの安否 | `friendStatusProvider` | `MockState.statuses` | Firestore `statuses/{friendUid}` |
| 自分の安否チップ | `myStatusProvider` | `MockState.myStatus` | Firestore `statuses/{uid}` |
| プロフィール・招待コード | `myProfileProvider` | 固定値 | Firestore `users/{uid}` |
| 承認・到着・再選定 | `AgentController` | `MockBackend` のメソッド | `POST /api/agent/*` |

---

## A. サーバーを動かす（ここが全ての前提）

| # | タスク | 完了条件 |
|---|---|---|
| A-1 | `server/.env` を埋める（`ORCA_API_KEY` / `ORS_API_KEY` / `FIREBASE_SERVICE_ACCOUNT_B64` / `CRON_TOKEN`） | `npx tsx scripts/orcaCheck.ts` がモデル一覧とコストを返す |
| A-2 | Vercel に Root Directory = `server` で Import し、同じ環境変数を登録 | デプロイ成功 |
| A-3 | 疎通確認 | `GET /api/health` が `{ok:true}` |
| A-4 | アプリの向き先を設定（設定 → API サーバー、または `--dart-define=API_BASE=`） | 設定画面に URL が出る |
| A-5 | **モックモードを OFF** にして以降を検証 | — |

> `FIREBASE_SERVICE_ACCOUNT_B64` は Firebase コンソール → プロジェクト設定 → サービスアカウント → 新しい秘密鍵。
> `.env` と鍵 JSON は**絶対にコミットしない**（`.gitignore` 済み）。

## B. 認証・登録

| # | タスク | 繋がる画面 | 完了条件 |
|---|---|---|---|
| B-1 | `POST /api/me/register` — FCM トークン・プラットフォーム・同意を登録 | 起動時 (`main.dart:_bootstrap`) | Firestore `users/{uid}` が作られ、設定に招待コードが出る |
| B-2 | 同意トグルの反映 | 設定 → 共有の同意 | トグル操作で `users/{uid}.consent` が変わる |

## C. 平時の地図

| # | タスク | 繋がる画面 | 完了条件 |
|---|---|---|---|
| C-1 | `POST /api/shelters/nearby` — 指定緊急避難場所データから半径内を返す | ホーム / マップ | 地図に避難所ピンが出る。マップタブのリストが件数付きで埋まる |
| C-2 | サーバー側のハザード判定（ハザードマップポータルの z16 タイルを `pngjs` で読む） | ホーム下部のセナヴィ一言 | 「この場所: 浸水 0.5〜3m」のような実測値が出る |
| C-3 | 標高取得（国土地理院 標高API） | 避難所詳細・マップのタグ | 標高タグが実値になる |
| C-4 | ~~`POST /api/weather/nowcast` — 直近60分の雨雲ナウキャスト~~ **済** | ホーム（平時のセナヴィの一言） | 気象庁 高解像度降水ナウキャストのタイルを読んで実装。`cloudPct` は府県予報の天気コードから |

### C-4 の提供元

アプリ側は `RainNowcast`（`nowMmh` / `maxMmh` / `startsInMin` / `stopsInMin` / `cloudPct`）だけを知り、
提供元はサーバーが吸収する。**どれを選んでも `lib/` は変更不要。**

**この機能は 0〜60 分・地点単位の予想なので、レーダー実観測系を使う。**
雨雲レーダー（気象庁 高解像度降水ナウキャスト、Yahoo もこれが元）は、いま見えている
エコーの移動を外挿するもので、5 分ごと・250m 級。数値予報モデルは「この地域で何 mm 降るか」を
物理計算するもので、分単位・地点単位の当て込みには向かない（モデルが有利になるのは数時間先から）。

| 提供元 | 登録 | 元データ | 取れるもの | 実装コスト |
|---|---|---|---|---|
| **気象庁 ナウキャスト**（← 採用） | 不要 | **レーダー実観測** | 降水強度の**タイル(PNG)**。点の値はピクセルから読む | 中。ただし**ハザード判定 C-2 で同じ処理を書く**ので流用できる |
| Yahoo! 気象情報API (YOLP) | Client ID（無料・要登録） | 同上（気象庁レーダー由来） | 60分先までの降水強度を10分刻み、**JSON で点の値** | 小。タイル読みが要らない |
| Open-Meteo | 不要 | 数値予報モデル | `minutely_15.precipitation` / `cloud_cover` | 小。ただし**この時間帯の精度では上2つに劣る** |

**`cloudPct`（快晴／曇りの出し分け）について**: レーダー系は降水しか返さないので `cloudPct` は null になり、
`RainOutlook.calm`（「しばらく雨は降らなさそう」）に丸まる。「しばらく快晴みたい」まで言いたいなら、
気象庁の**予報 JSON**（`https://www.jma.go.jp/bosai/forecast/data/forecast/{areaCode}.json`、登録不要）の
天気コードを 2 本目の呼び出しで足して `cloudPct` 相当を埋める。地域単位・粗い更新だが、
「空がどうか」を一言添えるには十分。

> 解像度の具体値（250m / 30 分先まで）は気象庁のページで裏を取ってから資料に書くこと。

**実装後に分かったこと**（`server/lib/tools/weather.ts`）:
- `hrpns` タイルは **z=10 が上限**。z11 以上は 334 バイトの空タイルが 200 で返るので、ズームを上げても細かくならない
- 時刻は `targetTimes_N1.json`（実況・新しい順）と `targetTimes_N2.json`（予測・5分刻みで +60 分まで）の 2 本
- `cloudPct` 用の区域解決は素直にいかない。**市区町村コード + "00" では引けない場合が3通りある**
  - 政令市の区（札幌市中央区 `01101`）は区域表に無く、市（`0110000`）で載っている
  - 松本市のように山間部が別枠で細分され、`2020201` / `2020202` に割れている
  - 奄美（`460040`）は office なのに予報 JSON が無く、鹿児島（`460100`）の JSON に含まれる
  → 3 通りのキーを試し、それでも駄目なら県内の office を順に当たる。全部外したら `cloudPct` は null（「雨は降らなさそう」までは言える）

> タイルのオーバーレイ表示自体はアプリ側で完結しており（`hina_map.dart`）、サーバー不要。
> C-2 は「現在地がどの浸水深クラスか」の判定だけ。

## D. エージェント（デモの本体）

| # | タスク | 繋がる画面 | 完了条件 |
|---|---|---|---|
| D-1 | `POST /api/agent/run` — 通知タップ or デモ発火からエージェント起動 | ホーム 03 | 数秒で `assessing` → `proposing` に変わる |
| D-2 | Firestore `incidents` の購読 | ホーム全体 | **複合インデックスが要る**: `uid` asc + `createdAt` desc |
| D-3 | `agentLog` サブコレクション書き込み | AgentLog | 3 タブが埋まる。審査員向けに「LLM 入力に座標が無い」「却下」「コスト」が出る |
| D-4 | `POST /api/agent/action` — `start` / `later` / `arrived` / `safe_zone` / `close` | ホーム各状態のボタン | カウントダウン30秒で自動 `start` が飛ぶ |
| D-5 | `POST /api/agent/reselect` — 満員・ユーザー操作で選び直し | 「別の場所へ」/ 満員デモ | `reselecting` → 次点の避難所に変わり、トーストが出る |
| D-6 | `POST /api/agent/position` — 5秒ごとの位置報告と 100m ジオフェンス | 誘導中 | 到着すると自動で `arrived` |
| D-7 | OpenRouteService の徒歩経路 | ホームの地図 | Polyline が道なりになる（モックは直線を数回折っただけ） |

## E'. 位置共有（フレンド）

**この機能は設計書の前提を 2 つ書き換えている**（承知の上での判断）:
- §161「生座標はどのコレクションにも保存しない」→ **撤回**。`locations/{uid}` に保存する
- §812「使用中のみで足りる／バックグラウンド追跡は Phase2」→ **変更**。常時許可 + `UIBackgroundModes: location`

LLM 側のデータ最小化（§6.3・審査基準①）は**そのまま**。「AI には座標を渡さない／人には、許可した相手にだけ渡す」という
目的ごとの線引きに変わる。ピッチもこの形で言い直すこと。

| # | タスク | 繋がる画面 | 完了条件 |
|---|---|---|---|
| E'-1 | ~~`POST /api/me/location` — 位置を受けて `locations/{uid}` に upsert~~ **済** | 友だち詳細 | `locations/{uid}` に upsert。`at` が古ければ捨てる（`applied:false` を返す） |
| E'-2 | ~~逆ジオで `areaName` を付与（国土地理院 逆ジオコーダ、キー不要）~~ **済** | 友だち詳細「最後にいた場所」 | 地理院の市区町村表（`maps.gsi.go.jp/js/muni.js`）で「東京都足立区」まで。逆ジオの `lv01Nm` は町丁目まで細かいので使わない |
| E'-3 | ~~`POST /api/friends/share` に `shareLocation` を追加~~ **済** | 友だち詳細のトグル | `autoShare` と `shareLocation` を個別に更新。渡した方だけ書く |
| E'-4 | ~~`friends/{uid}/list` に相手の `displayName` / `avatarImage` / `avatarMood` を写す~~ **済** | 友だち一覧のアイコン | `lib/profile.ts` の `fanOutProfile`。register でプロフィールが変わったら配り直す |
| E'-5 | ~~`POST /api/me/status` — メモ更新~~ **済** | プロフィール → メモ | `statuses/{uid}.note`。**エージェントは note を書かなくなった**（セナヴィの案内文で本人のメモが消えていた） |
| E'-6 | ~~`POST /api/me/register` に `avatarImage` / `avatarMood` を追加~~ **済** | プロフィール → アイコン | `users/{uid}.avatarImage` / `avatarMood`。画像と表情はどちらか一方だけ持つ |
| E'-7 | ~~`statuses/{uid}` に `shelterLat` / `shelterLng` を追加~~ **済** | 友だち詳細「向かっている避難場所」 | `publishStatus` が `shelterLat` / `shelterLng` も書く。`shareShelterName` が false なら名前ごと出さない |

アプリ側は実装済み（`lib/core/location_uploader.dart` / `pending_locations.dart`）:
- 50m 動いたときだけ送る（一定間隔のポーリングはしない＝電池を削らない）
- 送れなければ端末に積み、繋がったら**古い順**に流す。途中で失敗したらそこで止めて持ち越す
- 送るのは**観測時刻**。送信時刻ではないので、まとめて届いても順序が壊れない

## E''. 日常のコミュニティ機能（2026-09-20 追加）

平時に開かれないアプリは、災害時にも開かれない。**インストールされ続ける理由**を作るための層。
審査の主軸（自律エージェント）ではないが、「なぜ平時から入れてもらえるか」の答えになる。

| # | タスク | 繋がる画面 | 完了条件 |
|---|---|---|---|
| E''-1 | `POST /api/friends/send` — 本人が打つメッセージ／スタンプ | チャット | 相手に届き、`messages` に残る。**承認ゲートは通さない**（ゲートは AI の代筆用） |
| E''-2 | `messages/{threadId}/list` の購読とルール | チャット | 当事者2人だけ read/write |
| E''-3 | `POST /api/me/places` — よく行く場所の登録・削除 | 場所の設定 | `places/{uid}/list` に入る |
| E''-4 | **到着/出発の判定をサーバーで行う** | 友だち「できごと」 | 位置を受けた時に登録場所と突き合わせ、出入りが変わった時だけイベントを作る。**端末が寝ていても動く必要がある**ので、クライアント判定にはしない |
| E''-5 | 到着イベントを FCM で相手に通知 | 通知 | 「お母さんが自宅に着きました」が届く |
| E''-6 | `POST /api/meetup/start` / `end` | 合流バナー・地図の旗 | `meetups/{id}` に入り、メンバー全員に見える |

**Phase 2 送り**:
- **既読表示** ── `messages/{threadId}/list/{msgId}.readBy` と、スレッドを開いた時の書き戻し。
  Phase1 では「読まれたか」より「無事か」(安否・メモ・最終ログイン)を優先する。
  いま `ChatMessage` に既読の持ち場は無いので、追加時はモデルから触ることになる

**設計上の約束**（実装済み。サーバー側もこれに合わせる）:
- 到着判定は**平時と災害時で同じ仕組み**。「自宅に着いた」と「避難場所に着いた」を分けない ── 災害時だけの機能は、いざという時に誰も設定していない
- 合流地点は、相手に `shelterPoint` があれば**そちらを優先**する。災害時に落ち合う先は「いま居る場所」ではなく「向かっている避難所」
- ETA は徒歩 80m/分。避難経路の見積もりと同じ係数を使う（画面ごとに違うと混乱する）

## E. フレンド（見守り）

| # | タスク | 繋がる画面 | 完了条件 |
|---|---|---|---|
| E-1 | `POST /api/friends/accept` — 招待コードで追加 | 友だち | 一覧に増える |
| E-2 | `POST /api/friends/share` — 自動共有トグル | 友だち | `friends/{uid}/list/{friendUid}.autoShare` が変わる |
| E-3 | `POST /api/friends/message` — 承認ゲート付きの自由文送信 | 承認シート | PII Guardrail で電話番号が `[PHONE]` になる |
| E-4 | `statuses/{uid}` の購読 | 友だち・自分のチップ | 5状態が色分けで出る |

## F. 通知

| # | タスク | 完了条件 |
|---|---|---|
| F-1 | FCM 送信（Android） | 通知タップで `_handleAlert` → エージェント起動 |
| F-2 | iOS は APNs 無しのまま、Firestore `alerts` のミラーで代替（実装済み `main.dart:_bootstrap`） | iOS でもローカル通知が出る |

> iOS で本物のプッシュが要るなら Apple Developer Program (年額) と APNs キーが必要。
> 現状の設計は「iPhone = 見守り端末」なので**不要**。

## G. 災害監視（自律性の根拠）

| # | タスク | 完了条件 |
|---|---|---|
| G-1 | `GET /api/watch/disasters?token=` の実装確認 | 手で叩くとアラートが作られる |
| G-2 | cron-job.org に 2 分間隔で登録 | 放置していてもアラートが入る |

## H. OrcaRouter（スポンサー要件）

| # | タスク | 完了条件 |
|---|---|---|
| H-1 | Named Router 2本（`hina-triage` = cheapest / `hina-decide` = quality）、Frontier Escalation = Manual | `ORCA_ROUTER_*` がルーター名で通る |
| H-2 | Prompts に `hina-triage-system` / `hina-decide-system` を label `production` で登録 → `ORCA_USE_PROMPT_REF=true` | AgentLog に `prompt=...@production` が出る |
| H-3 | Guardrail（PII: email/phone mask, credit_card block）をデモ用キーにアタッチ | E-3 の確認と同じ |

---

## 進め方の順番

1. **A**（サーバー）→ ここが通らないと何も検証できない
2. **B → C** → 平時のホームとマップが本物のデータで埋まる
3. **D-1〜D-3** → 発火して AgentLog が出れば審査の主要素は揃う
4. **D-4〜D-7** → デモの流れが最後まで通る
5. **E** → 見守りデモ
6. **G → H** → 自律性とスポンサー要件の仕上げ
7. **F** → Android 実機が用意できたら

各ステップの検証は、**モックモードを ON/OFF して見比べる**のがいちばん速い。
ON のときの挙動が「期待値」なので、OFF にして同じ絵にならなければサーバー側の実装漏れ。

## モックを消すとき

繋ぎ込みが全部終わったら:

- `lib/mock/` を削除
- `providers.dart` の `ref.watch(mockModeProvider)` 分岐（8 箇所）と `AgentController._mock` 分岐を削除
- `settings_page.dart` のモックモード トグルを削除
- `demo_panel.dart` の `_friends` / `_reset` / `_fire` / `_crowdFull` の分岐を削除

デモ直前まで残しておくと、サーバー障害時の保険になる（オフラインでも全画面を通せる）。
