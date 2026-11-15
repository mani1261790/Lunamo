# Lunamo 0.1.0: 直接配布とSparkleの受入検証

検証対象はarm64・macOS 26以降、0.1.0 (build 1)。成果物と生ログは
`.build/notary-release-01/`。App Storeへの申請や一般公開は行わない。

## 公証

- アプリ: Developer ID署名、Hardened Runtime、同梱Mach-O 20個を検証。
  Apple公証ID `3446d1f3-b7bb-442a-879c-060d2bb3cd60`、結果Accepted。
  公証チケットをアプリに添付。提出前の署名済みアプリでオフラインの編集・保存・実行を検証した。
- アプリとDMGは別々にAppleへ提出する。Sparkleの署名は最終DMGの公証チケット添付後に行う。

## 更新試験の構成

以前のreleaseビルドを専用ディレクトリにコピーし、テスト用バージョンを
0.0.9 (build 0)として同じDeveloper IDで再署名。これは一般公開された旧版ではない。
旧版と新版の実行ファイルは異なる。旧版だけにローカル配信URLを設定し、
Sparkleの署名済みフィード必須・展開前署名検証は有効のまま。

ローカル配信は127.0.0.1に限定し、配布対象と同一バイトのDMGに対応する
テスト専用appcastを同じEd25519鍵で生成する。公開用appcastとはURLと署名が異なる。
Sparkle 2.10.1の公式sparkle-cliと同バージョンのフレームワークを使用。
`--probe` と `--check-immediately` は別に実行し、更新検出だけを成功条件としない。

## 配布物の検証結果

DMG公証ID: `2d3a841c-f9c3-473f-9c5c-8eef9982fd34`（Accepted）。
stapler validate成功、GatekeeperはアプリとDMGともにNotarized Developer ID。
最終DMGのSHA-256は
`e84fd17900a7f4b823311111c4006ff4f0e7d8e9510cd8ac2bd40f017180960f`。
