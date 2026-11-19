<p align="center">
  <img src="MarimoNative/Resources/AppIcon-1024.png" alt="Lunamo のアプリアイコン" width="128" height="128">
</p>

<h1 align="center">Lunamo</h1>

<p align="center">
  <strong>ひらめきを、Python とひとつのノートに。</strong><br>
  Mac のための marimo ノートブックアプリ。
</p>

<p align="center">
  macOS 26+ · Apple Silicon · 日本語 / English
</p>

**Lunamo（ルナモ）** は、Python のコードと実行結果、Markdown の文章を一緒に扱える macOS ネイティブの marimo クライアントです。手元のノートブックを開き、編集・実行しながら、分析の過程や気づきを残せます。

[公式サイト・ダウンロード](https://mani1261790.github.io/Lunamo/) · [使い方・インストール](https://mani1261790.github.io/Lunamo/guide.html)

### marimo とは

[marimo](https://marimo.io/) は、**Jupyter Notebook のように、コードをセルごとに実行しながら結果や説明文をまとめられる**、オープンソースの Python ノートブックです。保存されるファイルは **通常の Python ファイル（`.py`）** なので、Git で変更を追ったり、Python スクリプトとして実行したりできます。

セル同士の依存関係を把握し、あるセルを実行すると、その結果に依存するセルも自動で再計算できるのも特長です。Lunamo は、この marimo のノートブックを Mac のネイティブ UI で使うためのアプリです。

## 主な機能



- **ノートブックの編集・実行** — Python のコード補完、Markdown の編集、セルごとの実行結果の表示。
- **既存ファイルの取り込み** — marimo の `.py` に対応。Jupyter の `.ipynb` や通常の Python スクリプトも、元のファイルを残して marimo 形式に変換できます。
- **Python 環境の管理** — 実行環境を同梱し、設定画面からパッケージの追加やプロジェクトごとの環境管理ができます。
- **内蔵ターミナルとファイル一覧** — ノートブックと同じウィンドウで、作業フォルダやコマンドを扱えます。
- **オンデバイスのアシスタント** — コードの説明や修正案を相談し、提案を確認してから適用できます。Apple Intelligence が利用可能な環境で使えます。

## 対応環境

| 項目 | 要件 |
| --- | --- |
| OS | macOS 26 以降 |
| Mac | Apple Silicon 搭載モデル |
| UI の言語 | 日本語・英語 |
| アシスタント | Apple Intelligence が有効で、システムモデルが利用可能なこと |

Python や marimo をあらかじめ個別にインストールする必要はありません。分析に使う追加パッケージは、アプリの設定画面からインストールできます。アシスタントを利用できない環境でも、ノートブックの編集・実行は使えます。

## インストール

[Lunamo 0.1.2（DMG）](https://github.com/mani1261790/Lunamo/releases/download/v0.1.2/Lunamo-0.1.2.dmg) を開き、LunamoをApplicationsフォルダにドラッグしてください。更新はLunamoメニューの「アップデートを確認」から確認できます。

### ソースからビルドする

公開ソースのビルドには、**Swift 6.2 以降を含む Xcode** とインターネット接続が必要です。Xcode の初回セットアップを済ませてから、ターミナルで実行します。

```sh
git clone https://github.com/mani1261790/Lunamo.git
cd Lunamo
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./Tools/build-sidecar.sh
./Tools/build-debug-app.sh
open .build/Lunamo.app
```

Xcode を別の場所に置いている場合は、`DEVELOPER_DIR` を変更してください。初回に Python などの必要なファイルを取得し、アプリに同梱します。`build-sidecar.sh` は初回のみ実行します。



## 最初のノートを動かす



1. 新しいノートブックを作るか、手元の marimo `.py` ファイルを開きます。`.ipynb` や通常の Python スクリプトを開いた場合は、変換後の `.py` の保存先を選びます。
2. コードセルに `print("Hello, Lunamo!")` と入力し、セルの実行ボタンを押します。
3. 結果が表示されたら、ノートに名前を付けて保存します。保存形式は marimo の `.py` です。

必要なパッケージが見つからないときは、設定画面でノートブックの環境を確認し、追加してください。取り込んだ Jupyter ノートブックのパッケージも、自動ではインストールされません。

## フィードバック

不具合や機能のリクエストは [Issues](https://github.com/mani1261790/Lunamo/issues) へ。不具合の場合は、macOS のバージョンと再現手順を添えてください。

## ライセンス

Lunamoの自作コードは[MIT License](LICENSE)です。同梱するmarimoなどの第三者コンポーネントは、それぞれのライセンスが適用されます。アプリの「Lunamo → ライセンス…」から全文とソース入手先を確認できます。名称・アイコンの扱いは[ブランド方針](BRAND.md)を参照してください。
