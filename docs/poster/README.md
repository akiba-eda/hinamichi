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
