# Lunamo 0.1.0（build 2）直接配布の受入検証

2026-11-16、Apple Siliconの開発用Macで確認。未使用の別のMacでの試験ではない。

- 本体: Developer ID署名、Hardened Runtime、同梱Mach-O 20個を検証。Apple公証ID 9deca77b-845f-4b97-8be6-99e6d90f7050（Accepted）。
- DMG: Apple公証ID 27eb3f49-1815-4459-9cb3-4b2daae9049a（Accepted）。本体とDMGにチケットを添付し、Gatekeeperの判定を確認。
- DMG SHA-256: 6a8ccc17cdbb76ea23675c378988d26e3b288102bc2c55cff13a69a649865937。

## Sparkleによる更新

非公開の署名済み0.1.0（build 1）を専用フォルダにコピーして起動。Sparkle 2.10.1のsparkle-cliで、署名済みローカルフィードの検出と実際の更新を別々に実行した。公開用と試験用のDMGは同一バイト列。フィードは配信URLが異なるため個別にEd25519署名している。

build 2のダウンロード、展開、置換、再起動を確認。インストール先の実行ファイルとInfo.plistは配布元と一致。更新後に公証チケットとGatekeeperを確認し、外部ネットワークを禁止してノートの編集・保存・Python実行（出力43）を検証した。実行後も厳格な署名検証は成功し、ユーザー側の検証用ノートのSHA-256は更新前と一致した。

build 1は再起動後にPythonのバイトコードキャッシュが署名対象を書き換えたため公開しなかった。build 2はキャッシュを配布物から除き、同梱ランタイムのディレクトリへの書き込みを無効にした。

## 0.1.1（build 3）と公開フィードでの更新

2026-11-16、Apple Siliconの開発用Macで検証。リリースコミットの[CI](https://github.com/mani1261790/Lunamo/actions/runs/43857924118)が通過。署名済みアプリを日英それぞれで起動し、Python実行の信頼確認、未保存のウィンドウを閉じる確認、終了時の保存確認を操作した。

- Appleの公証は本体・DMGともにAccepted。IDは本体が 1f366ac1-2ccf-4806-b7db-3a6a101c423a、DMGが e341dd75-eee0-4495-96bd-a7e5a5c5589e。
- [公開DMG](https://github.com/mani1261790/Lunamo/releases/tag/v0.1.1)のSHA-256は eb2b030a92ee8598449480baf7b7abfab827ffdff68a39e514834262e1655147。
- GitHubから取得した0.1.0（build 2）を専用フォルダにインストールし、そのアプリ自身のSUFeedURLを使ってSparkleで検出・更新。build 3への置換と再起動を確認した。公開フィードと署名時のフィード、更新後と配布元の実行ファイルおよびInfo.plistはそれぞれ一致した。
- 更新後のアプリでGatekeeper・公証チケット・厳格な署名検証を通過。オフラインでノートの編集・保存・Python実行（出力43）を確認し、更新前からのノートも実画面で開いてセルの内容とファイルのハッシュが保たれたことを確認した。

リリースはMacのキーチェーンで署名。GitHubのタグ用Release Candidateジョブは署名用シークレット未設定のため配布物を生成していない。
