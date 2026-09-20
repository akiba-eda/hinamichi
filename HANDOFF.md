# 引き継ぎメモ(2026-09-20 → Android Studio 作業へ)

## いまの状態
- **server/**: 型チェック OK・ユニットテスト 19 本 PASS。実 API(GSI/JMA/P2P/ORS)と OrcaRouter への**実疎通は未実施**(この環境からはネットワーク遮断)。
- **app/**: Flutter は**未コンパイル**(SDK が使えない環境で書いた)。静的レビューで 3 件修正済みだが、`flutter analyze` で残りが出る前提で。
- **docs/ヒナミチ_設計書_v1.md**: 設計の正。迷ったらここ(§6 エージェント / §17 UI / §18 OrcaRouter / §20 無課金構成)。

## 最初の 30 分でやること(順番どおり)
1. `git push -u origin main`
2. `cd server && npm install && npm test`(緑を確認)
3. `.env` を作る(`.env.example` をコピー)→ `npx tsx scripts/orcaCheck.ts`
   - モデル一覧から cheap/strong を選び `ORCA_FALLBACK_*` と、Named Router 未作成なら `ORCA_ROUTER_*` に直接モデル ID を入れる
4. `npx tsx scripts/smoke.ts 35.6588 139.9013`(南行徳で避難所・ハザード・標高・経路が引けるか)
5. Firebase(Spark)作成 → 匿名認証 ON → サービスアカウント JSON → `firebase/` で rules & indexes deploy
6. `cd app && bash tool/setup.sh` → `flutterfire configure` → `flutter analyze`
   - **エラーはそのまま Claude に貼る**(こちらで直す)

## 既知のリスク / 見るべき所
- `app/lib/firebase_options.dart` はプレースホルダー(flutterfire configure で上書きされる)
- pubspec のバージョンは「^」指定。`flutter pub get` で解決しなければ `flutter pub upgrade --major-versions` を試す。flutter_map は **v7 系 API** で書いてある(v8 でも大きくは変わらないが `TileLayer.tileBuilder` 等を確認)
- `google_fonts` の `notoSansJp` は初回起動時にフォントを取りに行く。オフライン会場に備え、余裕があれば `assets/fonts/` に同梱して `GoogleFonts.config.allowRuntimeFetching=false`
- `assets/senavi/*.png` は仮画像。本物に差し替えたら `dart run flutter_launcher_icons`
- Android: `tool/patch_platforms.py` が Manifest に位置情報・通知権限と minSdk 23 を入れる。Android 13+ は通知の実行時許可が必要(起動時に要求する実装済み)
- iOS: プッシュ不可(無料署名)。見守り端末として使う。Firestore の `alerts` 購読→ローカル通知の経路は実装済み
- Firestore 複合インデックス `incidents(uid asc, createdAt desc)` と `(uid, shelter.id, state)` は `firebase/firestore.indexes.json` にある。未作成だとクエリがエラーになり Home が空のまま → deploy を忘れずに
- 位置: 実 GPS → 10 分キャッシュ → 南行徳オーバーライド。屋内で GPS が取れない時は設定 → DEMO →「位置を南行徳に固定」

## API の向き先
- 本番: `--dart-define=API_BASE=https://<project>.vercel.app`
- ローカル: `cd server && npx vercel dev` → 実機からは `http://<MacのIP>:3000`(設定画面からも変更可)

## デモ手順は README §4、コンソール設定(Named Router / Prompts / Guardrail)は README §1.2
