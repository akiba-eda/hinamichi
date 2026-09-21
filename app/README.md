# ヒナミチ — アプリ (Flutter)

iOS / Android のクライアント。画面・地図・通知・位置の取得を担当します。
エージェント本体とデータ取得は [`server/`](../server) 側にあります。

プロジェクト全体の説明は [ルートの README](../README.md)、
動かす手順は [docs/SETUP.md](../docs/SETUP.md) を見てください。

```
lib/
  app/        テーマ(デザイントークン)
  core/       API クライアント・位置・通知・設定
  domain/     モデル
  state/      Riverpod のプロバイダ
  features/   画面(home / map / friends / agent_log / shelter / settings …)
  ui/         atoms / molecules / organisms の共通部品
  mock/       サーバーに繋がなくても全画面を通せるモック
```

```bash
flutter pub get
flutter analyze && flutter test    # 39 件。鍵なしで通ります
flutter run -d <device> --dart-define=API_BASE=https://<project>.vercel.app
```

設定画面から **DEMO モード**（地震 / 豪雨 / 津波 / 満員 / LLM 障害注入）と
**Widget ギャラリー**（全部品を全状態で確認）を開けます。
