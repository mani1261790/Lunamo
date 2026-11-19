# Lunamo ライセンス監査 — 2026-11-19

> 以下は0.1.1に対する初回監査記録です。対応内容は [ThirdPartyLicenses.md](ThirdPartyLicenses.md)、配布検証は [Release-0.1.2.md](Release-0.1.2.md) を参照してください。

## 判定

初回監査の対象0.1.1には通知不足があった。対応作業の内容と適用範囲は ThirdPartyLicenses.md を参照。新しい配布物の検証・公証結果は別途記録する。以下は配布物と一次資料の技術的照合であり、個別契約や商標の法的判断を確定するものではない。

## 対象と証拠

- 公開タグ: v0.1.1。GitHub Release APIのasset digestと手元DMGのSHA-256を照合済み。
- DMG SHA-256: `eb2b030a92ee8598449480baf7b7abfab827ffdff68a39e514834262e1655147`
- DMGを読み取り専用でマウントし、実際のContents/ResourcesとSparkle.frameworkを検査。
- 公開ソース/LP: `21bbccb1a378d6a701f01f9348ac822581036b05`。開発中のHighlightKitは別枠。
- Python 3.13.15 / python-build-standalone 20260901。44 distributionsをファイルメタデータで棚卸し。
- 実行環境からOpenSSL 3.5.8、SQLite 3.53.1、libzmq 4.3.5を確認。
- 調査のみ。公開DMG、署名、appcast、LPデザイン、ライセンス方針は変更していない。

## 広告開始前に解消する項目

### A. Sparkle 2.10.1 のライセンス全文が配布物にない（確認済み）

SPM checkoutにはLICENSEがあるが、配布DMGのSparkle.framework/Resources、他のResources、Sidecar通知に全文がない。Headers内の著作権コメントだけでは全文の代わりにならない。`Tools/embed-sparkle.sh`はframeworkのみをコピーしている。MIT本文だけでなく、同じLICENSEに含まれるbsdiff、sais等の外部ライセンスを全文同梱する。署名する前に配置し、新しい版で公証・更新検証する。

根拠: https://github.com/sparkle-project/Sparkle/blob/2.10.1/LICENSE

### B. Pythonネイティブ依存の通知を網羅していない（確認済み）

build-sidecar.shはinstall_only archiveを使用し、CPythonのLICENSEだけを別取得する。上流full archiveのPYTHON.jsonにはlibffi、libedit、ncurses、OpenSSL、bzip2、mpdecimal、Tcl、expat等のlicense_pathsがあるが、そのライセンス一式は公開DMGにない。個々のソースコメントが残る場合もあるため全著作権表示の欠落を意味しないが、現状の生成手順では一式を保証できない。

同じ版・アーキテクチャのfull archiveからPYTHON.jsonとlicensesを取得した。14個の参照ファイル中、LICENSE.zlib-ng.txtはfull archive側にも見当たらず、上流メタデータと実リンク対象の突合が必要。readlineはこの配布のメタデータではGNU readlineではなくBSD系libedit。名前だけでGPL判定しない。

対応: 正確な配布版のネイティブ依存一覧・著作権・ライセンス本文を固定し、Sidecarに同梱。archiveはハッシュ固定。生成後、署名前の検証で欠落を失敗扱いにする。

根拠: https://github.com/astral-sh/python-build-standalone/blob/main/docs/distributions.rst

### C. MPL対象のソース入手案内（要補強）

pyzmq自体はBSD-3-Clauseだが、同梱libzmq 4.3.5のLICENSE.zeromq.txtはMPL-2.0。本文はTHIRD_PARTY_NOTICES.mdにも含まれている。pyzmqメタデータから上流リポジトリへのリンクは辿れるが、配布されたlibzmqの正確なソース/パッチの入手先を利用者に明示した案内は確認できない。wheelのビルド構成・パッチを照合して配布版対応のソースへリンクまたはアーカイブを提供する。

pip内certifiもMPL対象。cacert.pemはソース形式で配布され、通知も保持されているため、libzmqバイナリと同じ欠落とは扱わない。MPLはファイル単位であり、Lunamo全体をMPLにすることを意味しない。

根拠: https://www.mozilla.org/en-US/MPL/2.0/FAQ/ （Q7–Q11）

### D. Apple素材を使うLP/広告の権利確認（未解消）

site/index.htmlには後付けの文字、Appleアプリアイコンを含むdock-apps.webp、CSSによるMacBook風描画がある。Appleの一般ガイドラインはロゴ/アイコンの使用や製品描画について制限し、互換性の広告用途では実物写真を条件としている。Developer Programの個別契約や広告素材の許諾が優先される可能性があり、それらの確認は未実施。加入済みというだけでこの素材の許諾済みとは扱わない。

推奨: 広告にはLunamo独自アイコン/ワードマークと実際のアプリウィンドウを使う。現LPの外側のMacモック、後付けロゴ、Dockは許諾根拠を確認するか差し替える。Appleの登録商標の適切な帰属表記も整える。現在のデザインをこの監査で無断変更はしていない。

根拠: https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html

### E. Lunamo自身のライセンス方針（決定が必要）

公開main/tagにルートLICENSE/COPYINGやLunamo自身の利用条件がない。READMEにもライセンス指定がない。GitHub publicはOSSライセンス付与と同義ではない。自作コードの利用・変更・再配布を許諾するのか、ソース閲覧可能な独自条件にするのかを決める。無料DMG利用条件とアイコン/名称の権利も区別する。監査者がMIT等を勝手に付与しない。

根拠: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository

## 確認できたもの

| 対象 | 状況 |
| --- | --- |
| SwiftSoup 2.13.5 | MIT全文が専用resource bundleに同梱。元ファイルとバイト一致。 |
| KeyboardShortcuts 3.1.0 | MIT全文が専用resource bundleに同梱。元ファイルとバイト一致。 |
| marimo-base 0.24.0 / marimo-lsp 0.1.0 | Apache-2.0本文をSidecar通知に確認。lsp wheel単独にはlicense fileがないが生成処理が上流LICENSEを補完。 |
| KaTeX 0.18.5 | MIT本文同梱。フォントも同梱される。ライセンスを一律OFLだと決めつけない。 |
| Vega 6.4.0 / Vega-Lite 6.4.3 / Vega-Embed 7.2.0 | 各本体のBSD本文あり。ただし下記のバンドル内依存の監査は残る。 |
| Manrope Webフォント | OFL 1.1本文をsite/assets/fonts/Manrope-OFL.txtに同梱。Google Fontsの本文と著作権表示を照合。 |
| 独自ブランドマーク | Design/LunamoIcon内に編集可能なSVG原画と書き出し手順がある。他社デザインの独立性・商標登録のクリアランスまでは証明しない。 |
| 開発中HighlightKit 0.2.0 | MITと派生元highlight.jsのBSD-3-Clause通知をソースに保持し、Package.swiftでresources指定。公開0.1.1の構成要素ではない。次回配布実物で再確認。 |
| SwiftTerm | Tools/TerminalEvaluation内の評価依存。公開アプリのSPM依存にはない。 |

## 追加で閉じる監査範囲

- uv 0.12.9バイナリ: uv本体のMIT全文はある。Rustの静的依存ライセンス/NOTICEはこれだけでは保証できず、正確なCargo.lockとビルドfeatureから追加確認する。
- Vega/KaTeX等のminified bundle: 本体LICENSEだけでは内包するD3等の推移依存通知まで保証できない。固定版の元バンドル/lock/source mapと照合して不足分をまとめる。
- Python packageのトップレベルmetadataは44件中43件にlicense関連ファイルあり。marimo-lspは生成処理で補完。Not declaredはmetadata不足であり、それだけでライセンス不明とは判定しない。
- docutilsのCOPYINGにはGPLの過去/別ファイルへの言及があるが、該当rst.elは配布物に見当たらず、主要対象のBSD再許諾を記載している。全文のGPL文字列だけでアプリ全体をGPLと判定しない。
- Manrope以外の実OSフォントはCSSのsystem font参照。フォントファイルをコピーしていることとは別。
- Lunamo名称の既存商標調査、権利者との個別契約、全素材制作履歴、Apple Developer契約本文は今回の確認範囲外。

## 推奨する修正順

1. Sparkle・Pythonネイティブ・MPLの配布通知/入手案内と残る推移依存調査を完了する。
2. Licenses画面またはメニューから通知を開けるようにし、配布検証に必須ファイル検査を追加する。UIの新設自体が全ライセンスの必須条件という意味ではない。
3. Lunamo自身のライセンスを決め、コードとブランド素材の扱いを明示する。
4. Apple素材の許諾を確認するか広告/LPの該当表現を差し替える。
5. 新バージョンの署名・公証・Sparkle更新を確認して配布。現0.1.1の署名済みDMGは直接書き換えない。

## Python配布一覧

| 名前 | バージョン | metadataのlicense |
| --- | --- | --- |
| anyio | 4.14.2 | MIT |
| attrs | 26.1.0 | MIT |
| cattrs | 26.1.0 | MIT |
| click | 8.4.2 | BSD-3-Clause |
| docutils | 0.23 | 未宣言（本文を個別確認） |
| fastjsonschema | 2.21.2 | BSD |
| h11 | 0.16.0 | MIT |
| idna | 3.18 | BSD-3-Clause |
| itsdangerous | 2.2.0 | 未宣言（本文を個別確認） |
| jedi | 0.19.2 | MIT |
| jsonschema | 4.26.0 | MIT |
| jsonschema-specifications | 2025.9.1 | MIT |
| jupyter_core | 5.9.1 | BSD-3-Clause |
| jupytext | 1.19.5 | MIT License |
| loro | 1.13.2 | MIT |
| lsprotocol | 2025.0.0 | 未宣言（本文を個別確認） |
| marimo-base | 0.24.0 | Apache-2.0 |
| marimo-lsp | 0.1.0 | 未宣言（本文を個別確認） |
| Markdown | 3.10.2 | BSD-3-Clause |
| markdown-it-py | 4.2.0 | 未宣言（本文を個別確認） |
| mdit-py-plugins | 0.6.1 | 未宣言（本文を個別確認） |
| mdurl | 0.1.2 | 未宣言（本文を個別確認） |
| msgspec | 0.21.1 | BSD-3-Clause |
| narwhals | 2.24.0 | MIT |
| nbformat | 5.10.4 | BSD 3-Clause License |
| packaging | 26.2 | Apache-2.0 OR BSD-2-Clause |
| parso | 0.8.7 | MIT |
| pip | 26.2.1 | MIT |
| platformdirs | 4.11.0 | MIT |
| psutil | 7.2.2 | BSD-3-Clause |
| pygls | 2.1.1 | Apache-2.0 |
| Pygments | 2.20.0 | BSD-2-Clause |
| pymdown-extensions | 10.21.3 | MIT |
| python-multipart | 0.0.32 | Apache-2.0 |
| PyYAML | 6.0.3 | MIT |
| pyzmq | 27.1.0 | BSD 3-Clause License |
| referencing | 0.37.0 | MIT |
| rpds-py | 2026.6.3 | MIT |
| starlette | 1.3.1 | BSD-3-Clause |
| tomlkit | 0.15.1 | MIT |
| traitlets | 5.15.1 | BSD 3-Clause License |
| typing_extensions | 4.16.0 | PSF-2.0 |
| uvicorn | 0.51.0 | BSD-3-Clause |
| websockets | 16.1.1 | BSD-3-Clause |
