# 展示用ポスター(A4)

`index.html` を Chrome のヘッドレスで A4 に印刷したもの。画像はリポジトリ内の
スクリーンショットとブランド素材を参照している。QR は GitHub と Qiita の記事。

```bash
cd docs/poster
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu \
  --no-pdf-header-footer --print-to-pdf="$PWD/hinamichi_poster_A4.pdf" "file://$PWD/index.html"
```

`logo_cut.png` はスプラッシュ画像からロゴを切り出して空を抜いたもの
(`app/assets/brand/logo_h.png` は中身が透明の空ファイルで使えない)。

## チラシ 2 種(2026-09-22 追加)

- `flyer_screens.html` → `flyer_screens.pdf` — **A4 横**。画面 6 つを番号付きで並べた「画面でわかる」版
- `flyer_promo.html` → `flyer_promo.pdf` — **A4 縦**。キャッチと 3 つの柱、平時／災害の 2 画面の「宣伝」版
- 共通スタイルは `_common.css`。スクリーンショットは枠線を付けず、スマホ型の枠(`.phone`)に収める。
  カードは白・角丸 4mm・薄い影で統一(以前の枠線＋個別の影が「つぎはぎ」に見えていた)
- 画面素材は `shots/`(README のスクショに近隣情報・合流を足したもの)
