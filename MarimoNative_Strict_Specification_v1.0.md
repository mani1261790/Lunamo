# Marimo Native for macOS 厳格仕様書

文書ID: MN-SPEC-001  
仕様版: 1.0.0  
基準日: 2026-09-02  
対象リリース: 0.1.0 MVP  
状態: 実装基準  
製品識別名: MarimoNative  
対象プラットフォーム: macOS 26.0以降、Apple Silicon  
正本: 本ファイル

## 0. 規範

本仕様書における MUST は必須、MUST NOT は禁止、SHOULD は合理的な理由がない限り必須、MAY は任意を表す。

各要件には一意な要件IDを付与する。実装、テスト、レビュー、リリース判定は要件IDを単位として追跡する。要件IDを満たさない実装は、画面上で動作していても適合とは見なさない。

本仕様書と実装が衝突した場合は本仕様書を優先する。上流marimoの仕様変更と本仕様書が衝突した場合は、依存バージョンを勝手に更新せず、互換性試験と本仕様書の改訂を先に行う。

未記載の機能を推測して追加してはならない。MVP対象外の機能は、既存コードを複雑化させない拡張点だけを用意し、UIには露出しない。

## 1. 製品定義

### 1.1 定義

MN-PROD-001 MUST  
MarimoNativeは、marimo notebookをmacOS上で編集、実行、保存するネイティブクライアントでなければならない。

MN-PROD-002 MUST  
アプリケーションのwindow、toolbar、sidebar、inspector、notebook canvas、cell layout、cell selection、code editor、標準output rendererはSwiftUIまたはAppKitで実装しなければならない。

MN-PROD-003 MUST NOT  
Notebook全体をWKWebView、WebView、Electron、Chromium、React、JupyterLab、marimo Web UIの埋め込みで表示してはならない。

MN-PROD-004 MUST  
marimoのPythonソース解析、Pythonソース生成、依存グラフ、リアクティブ再実行、kernel lifecycle、UI element valueのPython側反映、標準出力、例外、session snapshot、exportは、可能な限りmarimo-lspおよびmarimo kernelへ委譲しなければならない。

MN-PROD-005 MUST NOT  
Swift側にPython parser、marimo dependency graph、Python evaluator、Jupyter kernel protocol、marimo source generatorを再実装してはならない。

MN-PROD-006 MUST  
正規の保存形式はmarimoネイティブの`.py`ファイルとする。`.ipynb`はexport形式としてのみ扱う。

MN-PROD-007 MUST  
Notebookの縦スクロールは一つのネイティブ`ScrollView`または`NSScrollView`が所有しなければならない。通常のcell、code editor、outputはNotebook全体のスクロール位置を奪ってはならない。

MN-PROD-008 MUST  
ファイルを開いただけではPythonコードを実行してはならない。

### 1.2 製品が解決する場面

ユーザーがFinderからmarimoの`.py`ファイルを開くと、ブラウザを起動せず、macOSの一つのwindowにcellが並ぶ。ユーザーがShift-Returnを押すと、選択されたPython環境でmarimo kernelが起動し、marimoが依存関係を解決し、対象cellと必要な下流cellを実行する。出力は該当cellの直下へネイティブViewとして追加され、Notebook canvas全体はmacOSの慣性スクロール、rubber band、keyboard navigation、accessibilityを維持する。

## 2. 固定する上流基準

### 2.1 ソース固定

MN-BASE-001 MUST  
MVPは次の上流基準へ固定する。

| 対象 | 固定値 |
|---|---|
| marimo-lsp repository | `marimo-team/marimo-lsp` |
| marimo-lsp commit | `3998b939c4e3bb09853817344ba9a976eeac8a66` |
| marimo-lsp package version | `0.1.0` |
| marimo-lsp runtime Python | CPython 3.13.x |
| marimo-lsp dependency | `marimo-base==0.24.0` |
| marimo kernel guaranteed version | `marimo==0.24.0` |
| marimo source reference commit | `8869b186a8c1c5bc9f5e123e7df7b6677ec06b8d` |
| private command method | `marimo/command` |
| kernel notification method | `marimo/kernelNotification` |
| document analysis method | `marimo/documentAnalysis` |
| session notification method | `marimo/sessionsChanged` |
| LSP transport | JSON-RPC 2.0 over stdio |
| LSP notebook type | `marimo-notebook` |
| owned document version | `"1"` |

MN-BASE-002 MUST NOT  
MVPのrelease buildは、PATH上にある任意の`marimo-lsp`を自動使用してはならない。

MN-BASE-003 MUST  
release buildは、上記commitから生成したmarimo-lsp wheelと、その依存関係を専用sidecar runtimeへ同梱しなければならない。

MN-BASE-004 MUST  
上流更新は、Protocol Lock更新、Swift Codable model再生成、contract fixture更新、integration test完走、仕様版更新を一つの変更として行わなければならない。

MN-BASE-005 MUST NOT  
`marimo-lsp`のprivate protocolにsemver互換性を仮定してはならない。

### 2.2 kernel互換性

MN-BASE-010 MUST  
MVPで実行を許可するuser kernelのmarimo versionは`0.24.0`だけとする。

MN-BASE-011 MUST  
`marimo-lsp`上流が`0.23.3`を最低kernel versionとしていても、MVPは検証範囲を広げてはならない。

MN-BASE-012 MUST  
0.24.0以外のmarimoが選択環境に存在する場合、Notebookを開くことは許可するが、実行ボタンを無効化し、検出したversionと必要なversionを表示しなければならない。

MN-BASE-013 MUST NOT  
互換性未確認のkernelから届いたunknown notificationを既知型へ強制castしてはならない。

MN-BASE-014 MUST  
MVPで実行を許可するuser kernelのPython versionは3.10、3.11、3.12、3.13、3.14のいずれかとする。3.9以下または3.15以上ではNotebookを開けるが、kernelを起動してはならない。

## 3. 対象範囲

### 3.1 MVPに含める機能

MN-SCOPE-001 MUST  
MVPは次の機能を含む。

| 区分 | 必須機能 |
|---|---|
| Document | New、Open、Open Recent、Save、Save As、Close、外部変更検出 |
| Cell | 追加、削除、複製、上下移動、選択、code編集、実行 |
| Execution | Run Cell、Run All、Interrupt、Restart Kernel |
| Environment | Python実行ファイル選択、preflight、projectごとの記憶 |
| Output | text、error、traceback、JSON、主要image、CSV、HTML fallback |
| Reactive | marimoによる依存cell再実行、stale表示 |
| UI Element | `marimo-slider`のネイティブ表示とvalue更新 |
| Inspector | session状態、Python環境、variables一覧 |
| Export | HTML、ipynb、Markdown |
| Distribution | Developer ID署名、notarization、Hardened Runtime |
| Recovery | sidecar crash、kernel crash、保存失敗、syntax errorの表示 |

MN-SCOPE-002 MUST  
MVPではすべての保存cellをPython sourceとして編集する。`mo.md(...)`と`mo.sql(...)`をMarkdownまたはSQLだけのsmart editorへ投影する機能はMVP対象外とする。

MN-SCOPE-003 MUST  
`mo.md(...)`および`mo.sql(...)`は通常のPython cellとして開き、編集し、実行できなければならない。

### 3.2 MVPに含めない機能

MN-SCOPE-010 MUST NOT  
次の機能をMVPへ追加してはならない。

- Jupyter kernelまたは`.ipynb`の直接編集
- remote marimo server
- multi-user collaboration
- Git UI
- terminal emulator
- debugger
- extension marketplace
- AI chat
- cloud execution
- iPhone、iPad、Windows、Linux版
- native Vega/Vega-Lite renderer
- native anywidget renderer
- native ipywidgets renderer
- smart Markdown cell editor
- smart SQL cell editor
- Mac App Store配布
- Notebookを安全なsandbox内で実行するという保証

MN-SCOPE-011 MUST  
対象外のMIME、widget、notificationは、crashさせず、対応外であることをcell内へ表示しなければならない。

## 4. システム構成

### 4.1 構成図

```text
┌──────────────────────────────────────────────────────────────┐
│ MarimoNative.app                                             │
│                                                              │
│  SwiftUI / AppKit Presentation                               │
│      │                                                       │
│  NotebookStore @MainActor                                    │
│      │                                                       │
│  Application Services                                        │
│      │                                                       │
│  MarimoBackend protocol                                      │
│      │                                                       │
│  MarimoLSPAdapter                                             │
│      │                                                       │
│  JSONRPCConnection actor ── LSPProcess actor                 │
└──────┼───────────────────────────────────────────────────────┘
       │ stdin/stdout: JSON-RPC 2.0
       ▼
┌──────────────────────────────────────────────────────────────┐
│ Bundled CPython 3.13 + pinned marimo-lsp                     │
│                                                              │
│ parse-notebook / print-notebook / session manager / adapter  │
└──────┼───────────────────────────────────────────────────────┘
       │ marimo IPC / ZeroMQ
       ▼
┌──────────────────────────────────────────────────────────────┐
│ User-selected Python executable                              │
│ marimo 0.24.0 kernel                                         │
│ dependency graph / reactive execution / outputs / UI state   │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 依存方向

MN-ARCH-001 MUST  
依存方向はPresentationからDomain、Application、Backend Port、LSP Adapter、Transportの一方向とする。

MN-ARCH-002 MUST NOT  
SwiftUI Viewから`Process`、Pipe、JSON-RPC、file write、marimo commandを直接呼び出してはならない。

MN-ARCH-003 MUST  
SwiftUI Viewは`NotebookStore`が公開するintentだけを呼び出す。

MN-ARCH-004 MUST  
`NotebookStore`は`@MainActor`に隔離し、UIへ公開するmutable stateを一箇所に集約する。

MN-ARCH-005 MUST  
process、JSON-RPC、session、output asset cacheは、それぞれ独立したactorで直列化する。

MN-ARCH-006 MUST NOT  
protocol decode後のdomain layerで`Any`、`NSDictionary`、`[String: Any]`を使用してはならない。可変JSONは`JSONValue` enumへ変換する。

```swift
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}
```

MN-ARCH-007 MUST  
private protocolの型は`MarimoProtocol` moduleへ隔離し、View layerへ露出してはならない。

### 4.3 process数

MN-ARCH-010 MUST  
アプリprocessは一つ、marimo-lsp sidecar processはアプリ全体で一つとする。

MN-ARCH-011 MUST  
実行を開始したNotebookごとにmarimo kernel processを最大一つ持つ。

MN-ARCH-012 MUST NOT  
Notebookを表示するためにHTTP server、browser process、Node.js processを起動してはならない。

MN-ARCH-013 MUST NOT  
`marimo edit`、`marimo run`、Jupyter serverを起動してはならない。

## 5. 配布とruntime同梱

### 5.1 配布方式

MN-DIST-001 MUST  
MVPはDeveloper ID Applicationで署名し、Apple Notary Serviceでnotarizeした直接配布アプリとする。

MN-DIST-002 MUST  
Hardened Runtimeを有効にする。

MN-DIST-003 MUST NOT  
App Sandboxを有効にしてはならない。任意のuser-selected Python executable、project directory、子process実行がMVPの中核機能であるためである。

MN-DIST-004 MUST NOT  
JIT、unsigned executable memory、disable library validation、DYLD environment variable許可のentitlementを追加してはならない。

MN-DIST-005 MUST  
アプリbundle内のMach-O executable、dynamic library、Python extension moduleは、外側のappを署名する前に内側から順に署名しなければならない。

MN-DIST-006 MUST  
release artifactはDMGまたはZIPとし、notarization ticketをstapleできる形式を優先する。

### 5.2 sidecar runtime

MN-DIST-010 MUST  
アプリは次のような自己完結runtimeを同梱する。

```text
MarimoNative.app/
  Contents/
    MacOS/
      MarimoNative
    Resources/
      Sidecar/
        bin/
          python3
        launch_marimo_lsp.py
        lib/
          python3.13/
            site-packages/
              marimo_lsp/
              marimo/
              ...
        protocol-lock.json
        THIRD_PARTY_NOTICES.md
```

MN-DIST-011 MUST  
sidecar runtimeはユーザーのHomebrew、pyenv、conda、system Python、PATH、site-packagesへ依存してはならない。

MN-DIST-012 MUST  
sidecar起動時に`PYTHONNOUSERSITE=1`と`PYTHONUTF8=1`を設定する。

MN-DIST-013 MUST  
sidecarは`Resources/Sidecar/bin/python3 Resources/Sidecar/launch_marimo_lsp.py`として`Process`から直接起動する。`launch_marimo_lsp.py`は固定された`from marimo_lsp import main; main()`だけを実行し、引数や環境からPython codeを組み立ててはならない。

MN-DIST-014 MUST NOT  
sidecar起動に`/bin/sh -c`、`zsh -c`、shell scriptの文字列連結を使ってはならない。

MN-DIST-015 MUST  
clean installation後、network接続がない状態でもNotebookのopen、parse、saveが動作しなければならない。

MN-DIST-016 MUST  
同梱するPython、marimo、marimo-lsp、依存packageのlicense noticeを`THIRD_PARTY_NOTICES.md`へ収録する。

### 5.3 architecture

MN-DIST-020 MUST  
MVP releaseはarm64だけを対象とする。

MN-DIST-021 MUST  
deployment targetはmacOS 26.0とする。

MN-DIST-022 MUST  
Xcode 26 SDK以降でbuildし、Swift 6 strict concurrency checkingをCompleteにする。

## 6. Notebook document model

### 6.1 正規モデル

MN-DOC-001 MUST  
Swift側はmarimo-lspのOwned Notebook Document v1を正規のpersistent modelとして保持する。

```swift
struct OwnedNotebookDocumentV1: Codable, Sendable, Equatable {
    let version: String                 // 必ず "1"
    var metadata: [String: JSONValue]
    var cells: [OwnedNotebookCell]
    var appOptions: AppOptions
    var header: String?
}

struct OwnedNotebookCell: Codable, Sendable, Equatable {
    var id: String?
    var code: String?
    var codeHash: String?
    var name: String?
    var config: CellConfig
}

struct CellConfig: Codable, Sendable, Equatable {
    var column: Int?
    var disabled: Bool?
    var hideCode: Bool?
}
```

MN-DOC-002 MUST  
`version`が`"1"`以外ならdocumentを編集可能状態へ移してはならない。

MN-DOC-003 MUST  
`metadata`と`appOptions.passthrough`は、固定したprotocol revisionが返したkeyとvalueをlosslessに保持する。

MN-DOC-004 MUST NOT  
Swift側で`@app.cell` decorator、`marimo.App(...)`、header、cell functionを文字列操作で生成してはならない。

MN-DOC-005 MUST  
`OwnedNotebookCell.codeHash`はwire上の`code_hash`へ、`CellConfig.hideCode`はwire上の`hide_code`へ明示的な`CodingKeys`で対応させる。`JSONDecoder.keyDecodingStrategy`または`JSONEncoder.keyEncodingStrategy`による暗黙変換をprotocol境界で使用してはならない。

### 6.2 persistent stateとtransient state

MN-DOC-010 MUST  
保存対象と実行時状態を分離する。

```swift
struct NotebookDocumentState {
    var sourceURL: URL?
    var owned: OwnedNotebookDocumentV1
    var cells: [NotebookCellState]
    var sourceRevision: UInt64
    var dirty: Bool
    var lastSavedFileIdentity: FileIdentity?
}

struct NotebookCellState: Identifiable {
    let runtimeID: CellRuntimeID
    var sourceID: String?
    var code: String
    var name: String
    var config: CellConfig
    var editor: CellEditorState
    var runtime: CellRuntimeState
}

struct CellRuntimeState {
    var status: ExecutionStatus
    var stale: Bool
    var output: MarimoOutput?
    var console: [MarimoOutput]
    var lastExecutedCode: String?
    var widgets: [WidgetInstanceID]
}
```

MN-DOC-011 MUST  
output、console、execution status、runtime ID、widget stateは`.py`へ保存してはならない。

MN-DOC-012 MUST  
parse結果のcell `id`が非nullなら`sourceID`として保持する。nullなら`sourceID`はnullのままとする。

MN-DOC-013 MUST  
すべてのopen cellにUUID v4の`runtimeID`を割り当てる。上流cell `id`が非nullであり、同一document内で一意なら、その値をruntime IDのseedとして使用してよい。

MN-DOC-014 MUST  
runtime IDはdocumentを開いている間、編集、移動、保存をまたいで変化してはならない。

MN-DOC-015 MUST  
新規cellのpersistent `id`と`codeHash`はnullとし、runtime IDだけを生成する。

MN-DOC-016 MUST  
保存用documentを組み立てる際、cellの`id`と`codeHash`はnullにする。MVPはtransient IDをPython sourceへ永続化しない。

MN-DOC-017 MUST  
cell nameがnullまたは空なら`"_"`として扱う。

MN-DOC-018 MUST  
cell codeがnullなら空文字列として扱う。

### 6.3 dirty判定

MN-DOC-020 MUST  
次の操作でdirtyをtrueにする。

- cell codeの変更
- cell追加、削除、複製、移動
- cell nameの変更
- cell configの変更
- appOptions、header、metadataの変更

MN-DOC-021 MUST NOT  
実行、output更新、stale更新、kernel再起動、variable更新、sidebar開閉でdirtyにしてはならない。

MN-DOC-022 MUST  
保存成功時だけdirtyをfalseへ戻す。

## 7. File lifecycle

### 7.1 New

MN-FILE-001 MUST  
新規Notebookは、Owned Notebook Document v1、空のheader、空のmetadata、一つの空Python cellを持つ。

MN-FILE-002 MUST  
新規NotebookのPython sourceはSwiftで組み立てず、最初のSave時に`print-notebook`で生成する。

### 7.2 Open

MN-FILE-010 MUST  
`.py`ファイルをbinaryで読み込み、UTF-8としてstrict decodeする。lossy decodeは禁止する。

MN-FILE-011 MUST  
UTF-8 BOMは受理し、parseへ渡す前に除去してよい。

MN-FILE-012 MUST  
20 MiBを超えるsource fileはMVPで開いてはならない。read-only raw previewを提示してよい。

MN-FILE-013 MUST  
sourceを`marimo/command`の`parse-notebook`へ渡す。

```json
{
  "jsonrpc": "2.0",
  "id": 12,
  "method": "marimo/command",
  "params": {
    "kind": "parse-notebook",
    "source": "import marimo\n..."
  }
}
```

MN-FILE-014 MUST  
`parse-notebook`の結果を次のように処理する。

| result.kind | 動作 |
|---|---|
| `success` | documentを作成して編集画面を開く |
| `invalid-syntax` | 実行不可のrecovery画面を開き、lineとcolumnを表示する |
| `convertible` | 通常のPython fileであることを表示し、Notebookとして勝手に上書きしない |

MN-FILE-015 MUST NOT  
`convertible`なfileを自動変換して元fileへ保存してはならない。

MN-FILE-016 MAY  
`convertible`に対して「変換したcopyを保存」を提供してよい。この操作は別URLへだけ書き込む。

MN-FILE-017 MUST  
parse timeoutは120秒とする。timeout後も元sourceを失ってはならない。

### 7.3 Save

MN-FILE-020 MUST  
Save時は現在のpersistent stateからOwned Notebook Document v1を作り、`print-notebook`へ渡す。

```json
{
  "jsonrpc": "2.0",
  "id": 27,
  "method": "marimo/command",
  "params": {
    "kind": "print-notebook",
    "document": {
      "version": "1",
      "metadata": {},
      "cells": [],
      "appOptions": {
        "managed": {"autoDownload": []},
        "passthrough": {}
      },
      "header": null
    }
  }
}
```

MN-FILE-021 MUST  
Swift側は`print-notebook`が返した`source`を変更せず保存する。改行変換、formatter、末尾空白除去を追加してはならない。

MN-FILE-022 MUST  
保存は同一directory内のtemporary fileへ書き、`fsync`相当を実行してからatomic replaceする。

MN-FILE-023 MUST  
既存fileのPOSIX permissionを可能な限り保持する。

MN-FILE-024 MUST  
保存前にdisk上のfile identityとmtimeを確認する。最後のreadまたはsave後に外部変更がある場合、自動上書きしてはならない。

MN-FILE-025 MUST  
外部変更とlocal dirtyが衝突した場合、次の三つだけを提示する。

- Reload from Disk
- Save Local Copy
- Cancel

MN-FILE-026 MUST NOT  
MVPで自動mergeを行ってはならない。

MN-FILE-027 MUST  
Save成功後に`notebookDocument/didSave`を送る。

MN-FILE-028 MUST  
変更がない状態でCommand-Sが押された場合、`print-notebook`とdisk writeを省略する。

MN-FILE-029 MUST  
MVPでは自動保存を行わない。window close時にdirtyなら保存確認を出す。

### 7.4 Close

MN-FILE-030 MUST  
documentを閉じる前にLSPへ`notebookDocument/didClose`を送り、live sessionが存在する場合は`close-session`も送る。

MN-FILE-031 MUST  
app終了時は`shutdown-all-sessions`、LSP `shutdown` request、LSP `exit` notificationの順で終了処理を試みる。

MN-FILE-032 MUST  
graceful shutdown全体を5秒で打ち切り、残存sidecarと子kernelをterminateする。

MN-FILE-033 MUST  
通常終了後にMarimoNativeが起動したkernel processを残してはならない。

### 7.5 Save As

MN-FILE-034 MUST  
Save Asは新しいtarget URLへ`print-notebook`の結果をatomic writeし、write成功前にdocumentの`sourceURL`を変更してはならない。

MN-FILE-035 MUST  
Save As先が現在のURLと同一なら通常のSaveとして処理する。

MN-FILE-036 MUST  
live sessionが存在するSave Asでは、disk write成功後、旧Notebook URIを`notebookUri`、新Notebook URIを`newNotebookUri`とする`move-session`を、旧URIのdidCloseより先に送る。

MN-FILE-037 MUST  
`move-session`成功後、旧URIのdidClose、新URIのdidOpenの順でLSP documentを付け替え、current session IDとtransient outputを維持する。

MN-FILE-038 MUST  
`move-session`が失敗した場合、新しいfileは削除せず、新URLをdocument URLとして採用し、旧URIのsessionをcloseして新documentを`notStarted`へ移す。旧sessionのoutputとwidget stateはclearし、失敗をbannerで通知する。

MN-FILE-039 MUST NOT  
Save Asで元fileを変更または削除してはならない。

### 7.6 External change

MN-FILE-040 MUST  
保存済みdocumentごとに`NSFilePresenter`または同等のcoordinated file monitorを登録し、変更、移動、削除を検出する。

MN-FILE-041 MUST  
自身のatomic saveによる通知は、保存済みfile identity、mtime、size、content hashで識別し、外部変更として二重処理してはならない。

MN-FILE-042 MUST  
local stateがcleanな状態で外部内容変更を検出した場合、自動でeditor bufferを置換せず、Reload from DiskとIgnore Until Next Saveを持つbannerを表示する。

MN-FILE-043 MUST  
local stateがdirtyな状態で外部内容変更を検出した場合、documentをconflictedへ移し、通常Saveを無効化する。許可する操作はReload from Disk、Save Local Copy、Cancelだけとする。

MN-FILE-044 MUST  
Reload from Diskは旧live sessionをcloseし、disk sourceを再度`parse-notebook`へ渡し、成功時だけpersistent stateを置換する。runtime output、console、widget、variable stateはclearする。

MN-FILE-045 MUST  
Reload成功後は同一Notebook URIについてdidClose、didOpenを順に送り直し、session状態を`notStarted`とする。

MN-FILE-046 MUST  
外部変更後のsourceが`invalid-syntax`または`convertible`なら、現在のeditor bufferを保持したままrecovery viewを表示し、破損sourceを別bufferとして閲覧できるようにする。

MN-FILE-047 MUST  
file移動を検出して新URLを特定できる場合、document URLを更新し、live sessionには`move-session`を適用する。

MN-FILE-048 MUST  
file削除を検出した場合、editor bufferを保持し、Save As、Close、Recreate at Original Locationを提示する。

## 8. Python environment

### 8.1 選択

MN-ENV-001 MUST  
Notebookごとに一つのPython executableを選択する。

MN-ENV-002 MUST  
選択UIには実行ファイルのreal path、Python version、marimo version、環境種別を表示する。

MN-ENV-003 MUST  
候補探索は次の順で行う。

1. Notebookと同じdirectoryの`.venv/bin/python`
2. 親workspaceの`.venv/bin/python`
3. 前回そのworkspaceで選択した実行ファイル
4. ユーザーがOpen Panelで選択した実行ファイル

MN-ENV-004 MAY  
uv、pyenv、condaから候補を追加取得してよい。ただしshellを介さず、各実行ファイルへ明示的なargumentsを渡す。

MN-ENV-005 MUST  
選択結果はworkspace rootのcanonical pathをkeyとしてApplication Supportへ保存する。

MN-ENV-006 MUST  
保存した実行ファイルが消失または変更された場合、再選択を要求する。

### 8.2 preflight

MN-ENV-010 MUST  
実行前に次の情報を子processからJSONで取得する。

- `sys.executable`
- Python major、minor、patch
- `platform.machine()`
- `marimo.__version__`
- `marimo.__file__`

MN-ENV-011 MUST  
preflightは選択されたexecutableを直接起動し、`-c`で固定scriptを渡す。

MN-ENV-012 MUST  
preflight timeoutは5秒、stdout上限は64 KiB、stderr上限は64 KiBとする。

MN-ENV-013 MUST  
終了codeが0でない、JSONが不正、Python versionが3.10から3.14の範囲外、実行ファイルがarm64で動作しない、marimo importが失敗する、marimo versionが0.24.0でない場合はkernelを起動してはならない。

MN-ENV-014 MUST NOT  
選択環境へpackageを暗黙にinstall、upgrade、removeしてはならない。

MN-ENV-015 MAY  
明示的な「Install marimo 0.24.0」操作を提供してよい。その場合、対象executableと実行commandを表示し、ユーザーが確認した後だけ`uv pip install --python <executable> marimo==0.24.0`を実行する。

MN-ENV-016 MUST  
install操作をCancelした場合、環境を変更してはならない。

### 8.3 working directory

MN-ENV-020 MUST  
kernel working directoryのdefaultはNotebook fileの親directoryとする。

MN-ENV-021 MUST  
working directoryはabsolute path、存在するdirectoryでなければならない。

MN-ENV-022 MUST  
untitled documentでは、最初の実行前にworking directoryを選択させる。

## 9. LSP transport

### 9.1 framing

MN-LSP-001 MUST  
marimo-lspとはstdin/stdoutを使うJSON-RPC 2.0で通信する。

MN-LSP-002 MUST  
message framingは次の形式とする。

```text
Content-Length: <UTF-8 byte count>\r\n
\r\n
<JSON payload>
```

MN-LSP-003 MUST  
headerはASCII、payloadはUTF-8としてdecodeする。

MN-LSP-004 MUST  
pipeからheaderまたはpayloadが任意のbyte位置で分割されることを前提にbufferingする。

MN-LSP-005 MUST  
一回のreadに複数messageが連結されることを前提に繰り返しparseする。

MN-LSP-006 MUST  
`Content-Length`が負、数字でない、64 MiBを超える場合はprotocol errorとしてconnectionを閉じる。

MN-LSP-007 MUST NOT  
stdoutへ出たprotocol外文字列を無視して継続してはならない。stream desynchronizationとしてsidecarを再起動する。

### 9.2 request管理

MN-LSP-010 MUST  
request IDはprocess lifetime内で単調増加するUInt64とする。

MN-LSP-011 MUST  
pending requestをIDでactor内に保持し、response、timeout、connection closeのいずれかで必ず解放する。

MN-LSP-012 MUST  
unknown response IDはdebug logへ記録し、UI stateへ適用しない。

MN-LSP-013 MUST  
timeout値は次の通りとする。

| request | timeout |
|---|---:|
| `initialize` | 10秒 |
| `parse-notebook` | 120秒 |
| `print-notebook` | 120秒 |
| 通常の`marimo/command` | 10秒 |
| LSP `shutdown` | 5秒 |
| kernel session start待機 | 15秒 |

MN-LSP-014 MUST  
execution自体の完了に通常command timeoutを適用してはならない。`execute` requestの受理と、`completed-run` notificationの完了を分離する。

MN-LSP-015 MUST  
serverからの`workspace/configuration` requestへ、要求数と同じ長さのresponse arrayを返す。未対応sectionはnullとする。

MN-LSP-016 MUST  
`client/registerCapability`と`client/unregisterCapability`へ正常応答する。

MN-LSP-017 MUST  
未対応server requestにはJSON-RPC MethodNotFoundを返し、connectionを落としてはならない。

### 9.3 initialize

MN-LSP-020 MUST  
sidecar起動後、`initialize` request、`initialized` notificationの順で送る。

MN-LSP-021 MUST  
`initialize`にはprocessId、clientInfo、rootUri、workspaceFolders、notebook document synchronization capabilityを含める。

MN-LSP-022 MUST  
serverInfoとserver capabilitiesをlogへ保存する。

MN-LSP-023 MUST  
initialize完了前にNotebook open、parse、execute commandを送ってはならない。

### 9.4 sidecar fault

MN-LSP-030 MUST  
sidecarのstderrはring bufferへ最大200行保存する。

MN-LSP-031 MUST  
sidecarがunexpected exitした場合、開いているdocumentを保持し、全sessionをdisconnectedへ移す。

MN-LSP-032 MUST  
自動再起動は60秒間に最大3回とする。

MN-LSP-033 MUST  
再起動後はinitializeをやり直し、開いているNotebookをすべてdidOpenし直す。

MN-LSP-034 MUST  
4回目の失敗では自動再起動を停止し、Open LogsとRestart Backendを表示する。

## 10. LSP Notebook synchronization

### 10.1 Notebook projection

MN-SYNC-001 MUST  
open中のOwned Notebook DocumentをLSP Notebook Documentへ投影する。

MN-SYNC-002 MUST  
Notebook URIはcanonical file URLとする。untitledの場合はprocess内で一意な`untitled:MarimoNative-<UUID>`を使う。

MN-SYNC-003 MUST  
`notebookType`は`marimo-notebook`とする。

MN-SYNC-004 MUST  
Notebook versionは1から開始し、persistent内容またはcell構造が変化するたびに1増やす。

MN-SYNC-005 MUST  
MVPのcellはすべてLSP `NotebookCellKind.Code`、languageId `python`として送る。

MN-SYNC-006 MUST  
cell text document URIは次の形式で生成する。

```text
marimo-native-notebook-cell://<document-uuid>/<cell-runtime-uuid>
```

MN-SYNC-007 MUST  
cell URIはdocumentを開いている間変化してはならない。

### 10.2 metadata envelope

MN-SYNC-010 MUST  
Notebook metadataを次の形で送る。

```json
{
  "marimo": {
    "appOptions": {
      "managed": {"autoDownload": []},
      "passthrough": {}
    },
    "header": null,
    "notebookMetadata": {}
  }
}
```

MN-SYNC-011 MUST  
cell metadataを次の形で送る。

```json
{
  "marimo": {
    "name": "_",
    "options": {
      "column": null,
      "disabled": false,
      "hide_code": false
    },
    "sourceProjections": {
      "markdown": null,
      "sql": null
    }
  },
  "marimoRuntime": {
    "stableId": "cell-runtime-id",
    "state": null
  }
}
```

MN-SYNC-012 MUST  
wire field名は上流schemaに従う。`options`内の`hide_code`はsnake_caseであり、Swift property名から自動推測してはならない。

MN-SYNC-013 MUST  
unknown metadata fieldを受け取った場合は保存し、再送時に落としてはならない。

### 10.3 didOpen

MN-SYNC-020 MUST  
新規documentの作成後または`parse-notebook`成功後、LSP projectionが完成した時点で`notebookDocument/didOpen`を一回送る。

MN-SYNC-021 MUST  
didOpenにはNotebook document、ordered cell references、すべてのcell text documentの全文を含める。

MN-SYNC-022 MUST  
didOpen送信前に同一URIがopen済みなら、先にdidCloseを送る。

### 10.4 text change

MN-SYNC-030 MUST  
code editorの変更を`notebookDocument/didChange`の`cells.textContent`として送る。

MN-SYNC-031 MUST  
text document versionはcellごとに単調増加する。

MN-SYNC-032 MUST  
LSP positionはUTF-16 code unitで計算する。Swift Character数をそのままcharacter fieldへ使ってはならない。

MN-SYNC-033 SHOULD  
通常編集はincremental range changeを送る。

MN-SYNC-034 MUST  
IME marked text中は未確定compositionをkernelへ同期してはならない。composition確定時に一つのchangeとして送る。

MN-SYNC-035 MUST  
Run commandを送る前に、そのcellの確定済み編集をLSP pipeへwriteし終える。

MN-SYNC-036 MUST  
notificationとrequestは同一JSON-RPC connectionへ順序通りwriteし、executeがdidChangeを追い越さないようにする。

### 10.5 structural change

MN-SYNC-040 MUST  
cell追加、削除、複製、移動は`notebookDocument/didChange`の`change.cells.structure`として送る。構造変更のためにNotebook document自体をdidCloseしてはならない。

MN-SYNC-041 MUST  
structure changeには旧配列に対する`start`、`deleteCount`、挿入後のordered cell referenceを含める。新規cellのtext documentだけを`didOpen`へ、削除cellのtext documentだけを`didClose`へ含める。

MN-SYNC-042 MUST  
live kernelからcellを削除する場合、structural didChangeに加えて、削除前のcurrent session IDを持つ`delete-cell` commandを送る。

MN-SYNC-043 MUST  
cell nameまたはconfigの変更は`notebookDocument/didChange`のcell data更新として送る。metadata変更だけを理由にNotebook documentをdidCloseしてはならない。

MN-SYNC-044 MUST  
structural change後の最初のexecuteでは、現在の全document stateを表すdidChangeのpipe writeが完了し、同一connection上でexecuteより前に並んでいることを保証する。

MN-SYNC-045 MUST  
untitled documentでcell追加、削除、移動を行っても、live kernel session IDが変化しないことをintegration testで保証する。

### 10.6 didSaveとdidClose

MN-SYNC-050 MUST  
disk write成功後だけdidSaveを送る。

MN-SYNC-051 MUST  
document close時に、Notebook URIと全cell text document URIを含むdidCloseを送る。

## 11. marimo private command contract

### 11.1 共通規則

MN-CMD-001 MUST  
すべてのprivate commandはJSON-RPC request method `marimo/command`で送る。

MN-CMD-002 MUST  
`params.kind`をdiscriminatorとするstrict tagged unionでencodeする。

MN-CMD-003 MUST  
wire keyはcamelCaseとする。

MN-CMD-004 MUST  
unknown fieldを既知commandへ送ってはならない。

MN-CMD-005 MUST  
protocol modelは手書きのdictionaryではなくCodable typeとして定義する。

### 11.2 MVP必須command

| kind | 用途 | MVP |
|---|---|---|
| `parse-notebook` | Python sourceからOwned Documentを得る | 必須 |
| `print-notebook` | Owned DocumentからPython sourceを得る | 必須 |
| `execute` | cell batchを実行し、必要ならsessionを開始 | 必須 |
| `update-ui-element` | native widgetの値をkernelへ送る | 必須 |
| `interrupt` | kernelを中断 | 必須 |
| `delete-cell` | live graphからcellを削除 | 必須 |
| `send-stdin` | `input()`へ応答 | 必須 |
| `close-session` | 一つのkernel sessionを終了 | 必須 |
| `restart-session` | kernelを再起動 | 必須 |
| `move-session` | Save Asまたはfile移動後にlive sessionのURIを変更 | 必須 |
| `list-sessions` | session snapshot取得 | 必須 |
| `shutdown-all-sessions` | app終了時の一括終了 | 必須 |
| `read-notebook-outputs` | reattach時のoutput復元 | 必須 |
| `set-display-theme` | kernel側output theme同期 | 必須 |
| `export-html` | HTML export | 必須 |
| `export-ipynb` | ipynb export | 必須 |
| `export-markdown` | Markdown export | 必須 |

### 11.3 execute

MN-CMD-010 MUST  
cell実行は次の形で送る。

```json
{
  "jsonrpc": "2.0",
  "id": 41,
  "method": "marimo/command",
  "params": {
    "kind": "execute",
    "notebookUri": "file:///Users/user/project/notebook.py",
    "executable": "/Users/user/project/.venv/bin/python",
    "workingDirectory": "/Users/user/project",
    "cells": [
      {
        "cellId": "3EF9EEC0-4B5E-4D17-9C24-D5DA64B12C83",
        "code": "x = 2"
      }
    ]
  }
}
```

MN-CMD-011 MUST  
Run Cellでは選択cellだけを`cells`へ入れる。下流cellの選択と再実行はmarimoへ委譲する。

MN-CMD-012 MUST  
Run Allでは現在のordered cellすべてを`cells`へ入れる。

MN-CMD-013 MUST NOT  
Swift側で依存cell集合を計算してexecuteへ追加してはならない。

### 11.4 update-ui-element

MN-CMD-020 MUST  
UI element更新は次の形で送る。

```json
{
  "jsonrpc": "2.0",
  "id": 52,
  "method": "marimo/command",
  "params": {
    "kind": "update-ui-element",
    "notebookUri": "file:///Users/user/project/notebook.py",
    "kernelSessionId": "session-id",
    "objectIds": ["AbCd-0"],
    "values": [7],
    "request": null,
    "token": "E205AB20-9CF0-4459-BD0F-5B333B41DD80"
  }
}
```

MN-CMD-021 MUST  
`objectIds.count`と`values.count`は一致しなければならない。

MN-CMD-022 MUST  
tokenは送信ごとに新しいUUID v4とする。

MN-CMD-023 MUST  
古いkernel session IDへwidget updateを送ってはならない。

### 11.5 session-bound command

MN-CMD-030 MUST  
`update-ui-element`、通常kernelを対象とする`interrupt`、`delete-cell`、`send-stdin`には、現在の`kernelSessionId`を使う。

MN-CMD-031 MUST  
session IDが未確定の間、前項のsession-bound UI操作を無効化する。

MN-CMD-032 MUST  
kernel再起動後、旧session IDを即時無効化する。

MN-CMD-033 MUST  
`restart-session`には`notebookUri`、選択中の`executable`、`workingDirectory`、`createIfMissing`を送り、`kernelSessionId`を含めてはならない。

MN-CMD-034 MUST  
`close-session`は`notebookUri`だけで対象sessionを閉じる。旧session IDを推測してpayloadへ追加してはならない。

## 12. Session lifecycle

### 12.1 state machine

```text
notStarted
    │ execute
    ▼
starting
    │ first valid session notification
    ▼
idle ── execute ──▶ running ── completed-run ──▶ idle
 │                    │
 │ restart            ├── interrupt ──▶ interrupting ──▶ idle
 ▼                    │
restarting            └── crash ─────▶ failed
 │
 └────────────────────────────────────▶ idle

any state ── close ──▶ closed
```

MN-SES-001 MUST  
各Notebook sessionは`notStarted`、`starting`、`idle`、`running`、`interrupting`、`restarting`、`failed`、`closed`のいずれか一つの状態を持つ。

MN-SES-002 MUST  
最初のRunまでkernelを起動しない。

MN-SES-003 MUST  
`execute`送信後、最初の`marimo/kernelNotification`または`marimo/sessionsChanged`からsession IDを確定する。

MN-SES-004 MUST  
15秒以内にsession IDを確定できない場合、`list-sessions`を一回呼び、Notebook URIが一致するsessionを探索する。

MN-SES-005 MUST  
それでも見つからない場合は`failed`へ移し、Runを成功扱いしてはならない。

MN-SES-006 MUST  
notification envelopeの`notebookUri`がdocument URIと一致しない場合、そのdocumentへ適用してはならない。

MN-SES-007 MUST  
notification envelopeの`sessionId`がcurrent session IDと一致しない場合、旧sessionのmessageとして破棄する。

MN-SES-008 MUST  
new session IDを受理した時点で、旧session由来のwidget registry、pending function call、stdin prompt、running indicatorをclearする。

MN-SES-009 MUST  
reattach時は`read-notebook-outputs`を呼び、live memoryまたはcompatible sidecarからoutputを復元する。

### 12.2 execution completion

MN-SES-010 MUST  
`cell-op`のstatusが`queued`または`running`ならsessionをrunningとする。

MN-SES-011 MUST  
`completed-run`を受け取った時点でsessionをidleへ戻す。

MN-SES-012 MUST  
`completed-run`より前にHTTP的なcommand responseが返っても、実行完了と表示してはならない。

MN-SES-013 MUST  
`kernel-startup-error`を受信した場合、error本文を保存してfailedへ移す。

MN-SES-014 MUST  
Interrupt操作は一回だけ送信し、完了またはtimeoutまでbuttonを連打可能にしてはならない。

MN-SES-015 MUST  
interruptingが10秒を超えた場合、「Force Restart Kernel」を表示する。

## 13. Kernel notification handling

### 13.1 envelope

MN-NOTIF-001 MUST  
`marimo/kernelNotification`を次のenvelopeとしてdecodeする。

```json
{
  "notebookUri": "file:///Users/user/project/notebook.py",
  "sessionId": "session-id",
  "notification": {
    "op": "cell-op",
    "cell_id": "cell-id"
  }
}
```

MN-NOTIF-002 MUST  
outer fieldはcamelCase、inner marimo notification fieldは上流schemaの命名を保持する。inner fieldを一律camelCaseへ変換してはならない。

### 13.2 必須notification

MN-NOTIF-010 MUST  
MVPは次のnotificationをdecodeし、状態へ反映する。

- `kernel-ready`
- `cell-op`
- `completed-run`
- `interrupted`
- `kernel-startup-error`
- `variables`
- `variable-values`
- `remove-ui-elements`
- `send-ui-element-message`
- `model-lifecycle`
- `function-call-result`
- `alert`
- `banner`
- `missing-package-alert`
- `installing-package-alert`
- `startup-logs`
- `focus-cell`
- `active-line`
- `consumer-capabilities`

MN-NOTIF-011 MUST  
上記以外のunknown opはraw JSONとop名をdebug logへ残し、UI threadを停止させず無視する。

MN-NOTIF-012 MUST  
同一unknown opが1 session内で100回を超えた場合、それ以降の個別logを抑制し、件数だけを集計する。

### 13.3 cell-op partial update

MN-NOTIF-020 MUST  
`cell-op`はpartial updateとして扱う。fieldがwire上に存在しない場合、現在値を維持する。

MN-NOTIF-021 MUST  
`output`が存在する場合、main outputを置換する。

MN-NOTIF-022 MUST  
`console`が一件ならappendし、arrayなら順にappendし、空arrayならconsoleをclearする。

MN-NOTIF-023 MUST  
`status`は`idle`、`queued`、`running`、`disabled-transitively`を受理する。

MN-NOTIF-024 MUST  
`stale_inputs`がtrueならcell outputをstale表示にする。

MN-NOTIF-025 MUST  
cell IDが現在のNotebookに存在しないnotificationは破棄し、debug logへ一件記録する。

MN-NOTIF-026 MUST  
UI state更新はMainActor上で、一つのnotificationにつき一つのtransactionとして適用する。

## 14. Execution semantics

### 14.1 Run Cell

MN-EXEC-001 MUST  
Shift-Returnまたはcell Run buttonでRun Cellを実行する。

MN-EXEC-002 MUST  
Run前にenvironment preflightが成功済みでなければならない。

MN-EXEC-003 MUST  
Run前に未送信の確定済みtext changeをLSPへflushする。

MN-EXEC-004 MUST  
現在のeditor文字列をexecute payloadへ入れる。最後に保存したsourceを使ってはならない。

MN-EXEC-005 MUST  
marimoが返すqueued、running、stale、outputをそのまま表示状態へ反映する。

MN-EXEC-006 MUST NOT  
cellを実行する前にNotebookを自動保存してはならない。

### 14.2 Run All

MN-EXEC-010 MUST  
Run Allはcurrent orderの全cellを一つのexecute commandへ入れる。

MN-EXEC-011 MUST  
disabled cellもsource同期のためpayloadへ含めてよい。実行可否はmarimoへ委譲する。

### 14.3 stdin

MN-EXEC-020 MUST  
stdin requestを受けたcell直下へnative input fieldを表示する。

MN-EXEC-021 MUST  
password inputは`NSSecureTextField`相当で表示し、入力値をlog、crash report、state restorationへ保存してはならない。

MN-EXEC-022 MUST  
Returnで`send-stdin`を送った後、入力fieldをdisableする。

### 14.4 trust

MN-EXEC-030 MUST  
Notebook openだけではtrust promptを出さない。

MN-EXEC-031 MUST  
初回実行直前に、このNotebookが任意のPythonコードを実行できることを示すsheetを出す。

MN-EXEC-032 MUST  
選択肢はRun Once、Trust This Folder、Cancelとする。

MN-EXEC-033 MUST  
Trust This Folderはcanonical folder path、volume identifier、file resource identifierをApplication Supportへ保存し、path文字列だけで同一folderと判定してはならない。

MN-EXEC-034 MUST  
remote volume、download quarantine付きfile、外部変更後の未知folderでは、保存済みtrustを再評価する。

MN-EXEC-035 MUST  
UI element操作による依存cell実行もPython実行である。未trusted documentではinteractive widgetをdisableする。

## 15. Native macOS UI

### 15.1 Window

MN-UI-001 MUST  
一つのNotebookを一つのnative windowとして開く。

MN-UI-002 MAY  
macOS標準window tabbingを許可する。

MN-UI-003 MUST  
minimum window sizeは960×640 ptとする。

MN-UI-004 MUST  
window restorationではfile URLとUI layoutだけを保存し、kernel、output、Python objectをencodeしてはならない。

### 15.2 Layout

```text
┌──────────────────────────────────────────────────────────────────┐
│ Toolbar: sidebar | file | environment | Run All | Interrupt      │
├──────────────┬─────────────────────────────────────┬─────────────┤
│ Sidebar      │ Native Notebook ScrollView          │ Inspector   │
│  Files       │                                     │ Session     │
│  Cells       │  Cell                               │ Variables   │
│              │   Code Editor                       │             │
│              │   Console                           │             │
│              │   Output                            │             │
│              │                                     │             │
└──────────────┴─────────────────────────────────────┴─────────────┘
```

MN-UI-010 MUST  
rootは`NavigationSplitView`または同等のnative split viewで構成する。

MN-UI-011 MUST  
sidebar default幅は240 pt、minimum 180 pt、maximum 360 ptとする。

MN-UI-012 MUST  
inspector default幅は300 pt、minimum 260 pt、maximum 440 ptとする。

MN-UI-013 MUST  
Notebook content columnのmaximum幅は1100 ptとし、広いwindowでは中央へ配置する。

MN-UI-014 MUST  
Notebook canvasは一つのvertical `ScrollView`と`LazyVStack`を使う。cellごとに独立したouter scroll viewを作ってはならない。

MN-UI-015 MUST  
sidebarとinspectorはkeyboard shortcutで完全に閉じられる。

### 15.3 Toolbar

MN-UI-020 MUST  
toolbarは次のcontrolを持つ。

- Sidebar toggle
- document title
- Python environment selector
- kernel status indicator
- Run All
- InterruptまたはRestart
- Inspector toggle

MN-UI-021 MUST  
Interruptはrunningまたはinterrupting以外ではdisableする。

MN-UI-022 MUST  
Run Allはenvironment invalid、document invalid syntax、backend unavailableのいずれかでdisableする。

MN-UI-023 MUST  
toolbarにGit、terminal、extension、AI controlを追加してはならない。

### 15.4 Cell appearance

MN-UI-030 MUST  
cellはglass cardにしない。Notebook contentと同じopaque canvas上に配置する。

MN-UI-031 MUST  
cell間隔は16 pt、cell内horizontal paddingは16 pt、vertical paddingは12 ptを基準とする。

MN-UI-032 MUST  
選択cellだけにaccent borderまたはleading indicatorを表示する。

MN-UI-033 MUST  
queuedは小さなclock indicator、runningはprogress indicator、staleは`Stale` label、errorはerror indicatorで区別する。

MN-UI-034 MUST  
stateは色だけで表してはならない。icon、label、accessibility valueを併用する。

MN-UI-035 MUST  
cell Run controlは選択中またはpointer hover中に表示し、常時大きなbuttonを並べない。

### 15.5 Liquid Glass

MN-UI-040 MUST  
Liquid Glassはsystem toolbar、sidebar、inspector、必要なfloating control groupにだけ使用する。

MN-UI-041 MUST  
標準SwiftUI toolbar、NavigationSplitView、search fieldが提供するsystem glassを優先する。

MN-UI-042 MUST NOT  
code editor、console、table、image、cell backgroundへ`.glassEffect`を適用してはならない。

MN-UI-043 MUST NOT  
Notebook内に多数の独立glass surfaceを並べてはならない。

MN-UI-044 MUST  
custom floating controlsを使う場合、一つの`GlassEffectContainer`へ機能単位でまとめる。

MN-UI-045 MUST  
glass tintは実行中、errorなど意味を持つ状態にだけ使い、装飾目的の固定tintを付けない。

MN-UI-046 MUST  
reduced transparency設定時にcontrolの可読性を維持する。

## 16. Code editor

### 16.1 実装

MN-EDIT-001 MUST  
code editorは`NSTextView`を`NSViewRepresentable`で包み、TextKit 2を使う。

MN-EDIT-002 MUST NOT  
SwiftUI `TextEditor`だけで本番editorを実装してはならない。

MN-EDIT-003 MUST NOT  
Monaco、CodeMirror、Ace、WKWebViewをcode editorに使ってはならない。

MN-EDIT-004 MUST  
editorはUTF-8 sourceを保持し、表示内部ではNSString/UTF-16 rangeとSwift String indexの変換を一箇所へ集約する。

MN-EDIT-005 MUST  
IME、marked text、undo、redo、selection、drag selection、copy、paste、findをmacOS標準動作に合わせる。

MN-EDIT-006 MUST  
Tabは選択行へindent、Shift-Tabはdedentとして動作する。

MN-EDIT-007 MUST  
default indentは4 spacesとし、Tab文字をinsertしない。

MN-EDIT-008 MUST  
括弧、引用符の自動補完はmarked text中に作動してはならない。

### 16.2 sizing

MN-EDIT-010 MUST  
editor minimum高は72 ptとする。

MN-EDIT-011 MUST  
content高に追従して最大1600 ptまで伸長する。

MN-EDIT-012 MUST  
1600 ptを超えるcellだけ内部vertical scrollを許可する。

MN-EDIT-013 MUST  
内部scroll可能なcellには明確なedge indicatorを表示し、Notebook scrollと混同しないようにする。

### 16.3 highlighting

MN-EDIT-020 MUST  
Python syntax highlightingはincremental parserで行う。

MN-EDIT-021 SHOULD  
tree-sitter-pythonをpinしたsourceとして同梱する。

MN-EDIT-022 MUST  
highlight計算をMainActorで行ってはならない。

MN-EDIT-023 MUST  
500行以下のcellでは入力後35 ms以内にvisible rangeのhighlightを更新する。

MN-EDIT-024 MUST  
highlight結果の適用でselection、marked text、undo stackを変化させてはならない。

### 16.4 keyboard

| shortcut | 動作 |
|---|---|
| Shift-Return | Run Cell、次のcellを選択。末尾なら新規cellを追加 |
| Command-Return | Run Cell、現在cellに留まる |
| Option-Return | Run Cell、直下に新規cellを追加 |
| Command-Shift-Return | Run All |
| Command-. | Interrupt |
| Command-S | Save |
| Command-Shift-S | Save As |
| Command-Option-Up | cellを上へ移動 |
| Command-Option-Down | cellを下へ移動 |
| Command-Shift-Backspace | 選択cellを削除 |
| Escape | editor focusを抜きcell selectionへ移動 |
| Return | 選択cellのeditorへfocus |

MN-EDIT-030 MUST  
上記shortcutはmenu commandにも登録し、discoverabilityとaccessibilityを確保する。

MN-EDIT-031 MUST  
削除shortcutはtext selectionがないcommand modeでだけcell削除として扱う。

## 17. Output model

### 17.1 wire model

MN-OUT-001 MUST  
marimo outputを次の型へdecodeする。

```swift
struct MarimoOutput: Sendable, Equatable {
    let channel: OutputChannel
    let mimeType: String
    let data: JSONValue
    let timestamp: Double?
}

enum OutputChannel: String, Codable, Sendable {
    case stdout
    case stderr
    case stdin
    case pdb
    case output
    case marimoError = "marimo-error"
    case media
}
```

MN-OUT-002 MUST  
dataはstring、error array、objectのいずれも受理できる。

MN-OUT-003 MUST  
imageやvideoのdecode、CSV parse、HTML preparationをMainActorで行ってはならない。

MN-OUT-004 MUST  
outputを`.py`へ保存してはならない。

### 17.2 renderer registry

MN-OUT-010 MUST  
rendererは`OutputRendererRegistry`でMIME typeから選択する。

MN-OUT-011 MUST  
rendererが見つからない場合、MIME type、data size、Copy Raw Data controlを持つUnsupportedOutputViewを表示する。

MN-OUT-012 MUST  
一つのrendererのfailureでNotebook windowをcrashさせてはならない。

### 17.3 MIME対応

| MIME | MVP renderer | 実装方式 |
|---|---|---|
| `text/plain` | Native | selectable monospace Text |
| `text/password` | Native | masked textまたはsecure stdin field |
| `application/json` | Native | lazy outline |
| `application/vnd.marimo+error` | Native | structured error view |
| `application/vnd.marimo+traceback` | Native | selectable traceback、file/line link |
| `image/png` | Native | ImageIO/NSImage |
| `image/jpeg` | Native | ImageIO/NSImage |
| `image/gif` | Native | ImageIO animationまたはfirst-frame fallback |
| `image/tiff` | Native | ImageIO/NSImage |
| `image/bmp` | Native | ImageIO/NSImage |
| `image/avif` | Native if system decodes | ImageIO、失敗時unsupported |
| `image/svg+xml` | Isolated fallback | cell-local WKWebView |
| `text/csv` | Native | streaming parser + NSTableView |
| `text/markdown` | Native subset + fallback | safe HTML subsetをnative化、残りはisolated fallback |
| `text/latex` | Isolated fallback | local bundled math renderer |
| `text/html` | Native common subset + isolated fallback | strict DOM decoder、未対応nodeだけcell-local WKWebView |
| Vega/Vega-Lite v5/v6 | Isolated fallback | local bundled renderer、network禁止 |
| `video/mp4` | Native | AVPlayerView |
| `video/mpeg` | Native | AVPlayerView if supported |
| `application/vnd.marimo+mimebundle` | Native dispatcher | precedence処理後に上記へ委譲 |
| `application/vnd.jupyter.widget-view+json` | Unsupported | marimoと同様に移行案を表示 |

MN-OUT-013 MUST  
stdoutとstderrは到着順を維持する。

MN-OUT-014 MUST  
一つのcellのconsoleが10 MiBまたは100,000行を超えた場合、古い部分からmemory上でtruncateし、先頭にtruncate noticeを表示する。

MN-OUT-015 MUST  
一つのoutput payloadが128 MiBを超える場合、decodeせずsize errorを表示する。

### 17.4 MIME bundle

MN-OUT-020 MUST  
`application/vnd.marimo+mimebundle`の`__metadata__`をoutput dataと分離する。

MN-OUT-021 MUST  
default precedenceは次の順とする。

1. `text/html`
2. Vega-Lite v6
3. Vega-Lite v5
4. Vega v6
5. Vega v5
6. `image/svg+xml`
7. `image/png`
8. `image/jpeg`
9. `image/gif`
10. `text/markdown`
11. `text/latex`
12. `text/csv`
13. `application/json`
14. `text/plain`
15. `video/mp4`
16. `video/mpeg`

MN-OUT-022 MUST  
`text/html`が存在する場合、PNG、JPEG、GIF、AVIF、BMP、TIFF fallbackをdefault表示から隠す。

MN-OUT-023 MUST  
VegaまたはVega-Liteが存在する場合、PNG、JPEG、GIF fallbackをdefault表示から隠す。

MN-OUT-024 MUST  
複数のvisible representationが残る場合、第一候補を表示し、native format selectorで切り替え可能にする。

MN-OUT-025 MUST  
MIME metadataのwidthとheightが妥当な正数なら表示sizeへ反映し、0、負数、100,000 ptを超える値は無視する。

MN-OUT-026 MUST  
`text/html`をWebViewへ渡す前にstandards-compliant DOM parserで解析し、text node、`pre`、`code`、`span`、`br`だけから成る文書はnative selectable textとして表示する。`script`、`style`、event handler、unknown elementが一つでも存在する場合、このnative pathを使用してはならない。

MN-OUT-027 MUST  
整数、浮動小数、文字列、list、dictの標準repr fixtureはWKWebViewを生成せずnative Viewだけで表示できなければならない。

### 17.5 stale output

MN-OUT-030 MUST  
stale outputは内容を残し、opacityを下げるだけでなく`Stale` labelを表示する。

MN-OUT-031 MUST  
再実行中も最後のoutputを残し、上にrunning indicatorを重ねる。

MN-OUT-032 MUST  
新しいoutputが到着した時点で旧main outputを置換する。consoleは別管理とする。

## 18. Native marimo UI element

### 18.1 decoder boundary

MN-WIDGET-001 MUST  
MVPでnative化するmarimo UI elementは`marimo-slider`だけとする。

MN-WIDGET-002 MUST  
native decoderは、outputのrootが一つの`marimo-ui-element`で、そのfirst childが一つの`marimo-slider`である場合だけ有効化する。

MN-WIDGET-003 MUST NOT  
HTMLをregular expressionだけでparseしてはならない。standards-compliant HTML parserを使用する。

MN-WIDGET-004 MUST  
outer elementから`object-id`と`random-id`を取得する。

MN-WIDGET-005 MUST  
child elementの`data-*`はHTML entity decode後、各値をJSONとしてdecodeする。

MN-WIDGET-006 MUST  
未知attributeは保持してよいが、native controlの動作へ推測で適用してはならない。

### 18.2 slider schema

MN-WIDGET-010 MUST  
`marimo-slider`は次のfieldをdecodeする。

```swift
struct MarimoSliderDescriptor: Sendable, Equatable {
    let objectID: String
    let randomID: String
    let initialValue: Double
    let labelHTML: String?
    let start: Double
    let stop: Double
    let step: Double?
    let steps: [Double]?
    let debounce: Bool
    let orientation: SliderOrientation
    let showValue: Bool
    let fullWidth: Bool
    let includeInput: Bool
    let disabled: Bool
}
```

MN-WIDGET-011 MUST  
`start > stop`、initialValueが非有限、stepが0以下、stepsに非有限値がある場合、native化を中止しfallbackへ移す。

MN-WIDGET-012 MUST  
stepsがnullまたは空なら、SwiftUI Sliderの値をそのままkernelへ送る。

MN-WIDGET-013 MUST  
stepsが非空なら、Sliderは0から`steps.count - 1`のindex空間で動作し、kernelへindexを送る。画面上の数値は`steps[index]`を表示する。

MN-WIDGET-014 MUST  
orientationがhorizontalなら水平、verticalなら垂直controlを表示する。system Sliderで垂直表示を正しく実装できない場合はAppKit controlを使用する。

MN-WIDGET-015 MUST  
showValueがtrueなら現在値を表示する。

MN-WIDGET-016 MUST  
includeInputがtrueなら数値入力fieldを併設する。

MN-WIDGET-017 MUST  
disabledがtrueならpointer、keyboard、accessibility actionをすべて無効化する。

### 18.3 value synchronization

MN-WIDGET-020 MUST  
同じobject IDを持つ複数Viewは一つの`WidgetValueStore`を共有する。

MN-WIDGET-021 MUST  
一つのViewで値が変化したら、同一object IDの全Viewを即時更新する。

MN-WIDGET-022 MUST  
debounceがfalseならdrag中の更新を最大30 Hzで送信し、drag終了時の最終値を必ず送る。

MN-WIDGET-023 MUST  
debounceがtrueならdrag終了、keyboard commit、数値field commit時だけ送る。

MN-WIDGET-024 MUST  
random IDが変化したら、同じobject IDでもcontrol instanceを再生成し、initialValueへresetする。

MN-WIDGET-025 MUST  
`remove-ui-elements`を受けたcellのwidget instanceをregistryから削除する。

MN-WIDGET-026 MUST  
session変更時に全widget registryをclearする。

### 18.4 vertical slice fixture

MN-WIDGET-030 MUST  
受け入れfixtureは次の意味を持つ二cell Notebookとする。

```python
@app.cell
def _(mo):
    slider = mo.ui.slider(0, 10, value=2, label="Value")
    slider
    return (slider,)

@app.cell
def _(slider):
    slider.value * 2
    return
```

MN-WIDGET-031 MUST  
最初の実行後、native Sliderは2を表示し、下流outputは4を表示する。

MN-WIDGET-032 MUST  
Sliderを7へ変更すると、Swift側で式を再計算せず、marimoへvalue 7を送り、marimoが下流cellを再実行し、outputが14へ変化しなければならない。

## 19. Cell-local Web fallback

### 19.1 適用範囲

MN-WEB-001 MUST  
WKWebViewは一つのoutputのcontent rendererとしてだけ使用できる。

MN-WEB-002 MUST NOT  
WKWebViewにNotebook sidebar、toolbar、cell editor、cell ordering、Notebook scrollingを実装してはならない。

MN-WEB-003 MUST  
WKWebViewの内部scrollを無効化し、content高をnative hostへ通知して外側Notebook scrollへ統合する。

MN-WEB-004 MUST  
一つのWeb outputが1600 ptを超える場合だけ、明示的なExpand操作後に内部scrollを許可する。

### 19.2 isolation

MN-WEB-010 MUST  
`WKWebsiteDataStore.nonPersistent()`を使う。

MN-WEB-011 MUST  
file URLへのread accessは、そのoutput用temporary directoryだけに限定する。

MN-WEB-012 MUST  
navigation responseとnew window requestをblockする。ユーザーがlinkをclickした場合は確認後に`NSWorkspace`で外部browserへ渡す。

MN-WEB-013 MUST  
network requestはdefaultでblockする。

MN-WEB-014 MUST  
native message handlerはcontent height、explicit widget event、explicit function resultの最小集合だけとする。

MN-WEB-015 MUST NOT  
任意のJavaScriptからfile system、Process、clipboard、NotebookStoreへ直接accessできるbridgeを公開してはならない。

MN-WEB-016 MUST  
WebView process crashは該当outputだけをerror stateへ移し、Notebookとkernelを維持する。

### 19.3 sanitization

MN-WEB-020 MUST  
`text/markdown`とraw SVGはsanitizeしてからfallbackへ渡す。

MN-WEB-021 MUST  
`text/html`はPython code由来の任意contentであることを前提とし、native bridge privilegeを与えない。

MN-WEB-022 MUST  
script実行を必要としないoutputではJavaScriptを無効化する。

MN-WEB-023 MUST  
Vega、LaTeXなどのrenderer assetはapp bundleからloadし、CDNへ依存しない。

## 20. Sidebar and Inspector

### 20.1 Sidebar

MN-PANEL-001 MUST  
sidebarはFilesとCellsの二つのsectionを持つ。

MN-PANEL-002 MUST  
FilesはNotebook directoryをrootとし、directory、`.py`、`.csv`、`.json`、imageを表示する。

MN-PANEL-003 MUST  
FilesからNotebook `.py`を開ける。

MN-PANEL-004 MUST NOT  
MVPでfile delete、rename、Git statusを提供してはならない。

MN-PANEL-005 MUST  
Cellsはcell order、name、first non-empty line、runtime statusを表示し、選択で該当cellへnative scrollする。

### 20.2 Inspector

MN-PANEL-010 MUST  
InspectorはSessionとVariablesを持つ。

MN-PANEL-011 MUST  
SessionにはPython executable、Python version、marimo version、working directory、session ID、kernel statusを表示する。

MN-PANEL-012 MUST  
Variablesは`variables` notificationからname、declared-by、used-byを表示する。

MN-PANEL-013 MUST  
`variable-values`が利用可能ならdatatypeと短いpreviewを表示する。

MN-PANEL-014 MUST  
variable previewは最大4 KiBとし、任意objectへ追加のPython評価を自動実行してはならない。

## 21. Error model

### 21.1 error code

MN-ERR-001 MUST  
user-facing errorは次のcode体系を持つ。

| code | 意味 |
|---|---|
| `MN-LSP-START-001` | sidecarを起動できない |
| `MN-LSP-PROTOCOL-002` | JSON-RPC framingまたはdecode失敗 |
| `MN-LSP-TIMEOUT-003` | backend request timeout |
| `MN-DOC-UTF8-101` | sourceがUTF-8ではない |
| `MN-DOC-SYNTAX-102` | Python syntax error |
| `MN-DOC-CONVERT-103` | marimoではないPython source |
| `MN-DOC-SAVE-104` | atomic save失敗 |
| `MN-DOC-CONFLICT-105` | disk外部変更との衝突 |
| `MN-ENV-NOTFOUND-201` | Python executableが存在しない |
| `MN-ENV-PREFLIGHT-202` | Python preflight失敗 |
| `MN-ENV-MARIMO-203` | marimoがない、またはversion不一致 |
| `MN-KERNEL-START-301` | kernel起動失敗 |
| `MN-KERNEL-CRASH-302` | kernel unexpected exit |
| `MN-KERNEL-INTERRUPT-303` | interrupt timeout |
| `MN-OUTPUT-DECODE-401` | output decode失敗 |
| `MN-OUTPUT-SIZE-402` | output size上限超過 |
| `MN-WIDGET-DECODE-501` | native widget schema不一致 |
| `MN-WEB-CRASH-601` | Web content process crash |

MN-ERR-002 MUST  
error UIはcode、具体的原因、対象pathまたはsession、可能な回復操作を表示する。

MN-ERR-003 MUST NOT  
user-facing UIにPython tracebackやsidecar stderrを全文自動表示してはならない。Detailsで開く。

MN-ERR-004 MUST  
保存失敗、backend crash、kernel crashでeditor bufferを失ってはならない。

### 21.2 recovery

MN-ERR-010 MUST  
sidecar restart後、未保存documentをmemory stateからdidOpenし直す。

MN-ERR-011 MUST  
kernel restartではsource、selection、scroll位置を維持し、outputとwidget stateをclearする。

MN-ERR-012 MUST  
renderer errorではraw dataをCopyまたはSaveできるようにする。

## 22. Security and privacy

MN-SEC-001 MUST  
Notebookは任意Pythonコードを実行できるため、安全なdocument viewerとして表現してはならない。

MN-SEC-002 MUST  
file openとcode executionを分離する。

MN-SEC-003 MUST  
Process実行はexecutable pathとarguments arrayで行い、ユーザー文字列をshell commandへ連結してはならない。

MN-SEC-004 MUST  
API key、environment variable value、password stdin、Notebook output本文をdefault logへ書いてはならない。

MN-SEC-005 MUST  
logへpathを出す場合、release buildではhome directory prefixを`~`へredactする。

MN-SEC-006 MUST  
telemetryをMVPへ実装してはならない。

MN-SEC-007 MUST  
crash reportへNotebook sourceとoutput本文を添付してはならない。

MN-SEC-008 MUST  
recent file一覧はlocal Application Supportにだけ保存する。

MN-SEC-009 MUST  
Web fallbackからnetworkを許可する機能を後から追加する場合、Notebook単位ではなくoutput単位の明示操作にする。

MN-SEC-010 MUST  
temporary output fileはsession終了時に削除し、app crash後は次回起動時に24時間以上古いdirectoryをcleanupする。

## 23. Logging

MN-LOG-001 MUST  
`OSLog`を使い、categoryを`app`、`document`、`lsp`、`kernel`、`output`、`widget`、`web`に分ける。

MN-LOG-002 MUST  
release default levelはinfo以上とし、protocol payload全文を出さない。

MN-LOG-003 MUST  
debug modeではmessage method、request ID、op、payload byte size、durationを記録してよい。

MN-LOG-004 MUST NOT  
debug modeでもsource code、stdout、stderr、HTML、JSON value本文をdefaultで記録してはならない。

MN-LOG-005 MUST  
sidecar stderr ring bufferはOpen Logsから閲覧できる。

MN-LOG-006 MUST  
log export時にuserが内容を確認してからfileへ保存する。

## 24. Performance requirements

MN-PERF-001 MUST  
M2 16 GB級のMac、100 cell、source 1 MiBのfixtureで、sidecar warm時のopenからcell表示までを1.0秒以内のp95とする。

MN-PERF-002 MUST  
cold app launchから空Notebook window表示までを2.0秒以内のp95とする。kernel起動時間は含めない。

MN-PERF-003 MUST  
500行以下のcellでtyping eventからglyph更新までを16 ms以内のp95とする。

MN-PERF-004 MUST  
100 cell、各cell平均10行、画像output合計50 MiBのfixtureで、通常scroll中にMain Thread hang 100 ms超を発生させてはならない。

MN-PERF-005 MUST  
image decode、CSV parse、JSON tree constructionをbackground taskで行い、visible resultだけMainActorへ渡す。

MN-PERF-006 MUST  
Run button押下からexecute requestのwrite完了までを100 ms以内のp95とする。kernel処理時間は含めない。

MN-PERF-007 MUST  
kernel未起動、100 cell、outputなしのNotebook一件で、appとsidecar合計resident memory 350 MiB以下を目標とする。

MN-PERF-008 MUST  
offscreen WebViewを無制限に保持してはならない。Web output poolは同時visible数+2を上限とする。

MN-PERF-009 MUST  
cell Viewは`LazyVStack`で遅延生成し、output assetはLRU cacheで管理する。

## 25. Accessibility and localization

MN-A11Y-001 MUST  
toolbar、cell Run、status、environment selector、widgetにaccessibility labelとvalueを付ける。

MN-A11Y-002 MUST  
VoiceOverでcell index、cell name、status、code editor、outputの順に移動できる。

MN-A11Y-003 MUST  
Full Keyboard Accessだけでopen、編集、実行、中断、保存、cell移動、sidebar操作ができる。

MN-A11Y-004 MUST  
Reduce Motion時にglass morphingや非必須animationを停止する。

MN-A11Y-005 MUST  
Increase ContrastとReduce Transparencyで文字contrastを失わない。

MN-A11Y-006 MUST  
MVPのUI文字列は英語を正本とし、日本語localizationを同梱する。

MN-A11Y-007 MUST  
error codeとtechnical detailはlocalizationによって変化させない。

## 26. Swift実装規約

MN-SWIFT-001 MUST  
Swift 6 strict concurrency warningを0件にする。

MN-SWIFT-002 MUST  
UI state mutationはMainActorに限定する。

MN-SWIFT-003 MUST  
blocking file I/O、Process wait、JSON decode、image decodeをMainActorで行ってはならない。

MN-SWIFT-004 MUST NOT  
production codeでforce unwrap、`try!`、`fatalError`を使用してはならない。ただし到達不能をcompilerへ示すgenerated codeはreview対象として例外を許可する。

MN-SWIFT-005 MUST  
public protocol modelは`Codable`、`Sendable`、可能なら`Equatable`へ適合させる。

MN-SWIFT-006 MUST  
JSON key strategyへ全面依存せず、snake_caseとcamelCaseが混在するfieldへ明示的CodingKeysを定義する。

MN-SWIFT-007 MUST  
LSP process ownership、pipe ownership、pending continuation ownershipを一つのactorに重複させてはならない。

MN-SWIFT-008 MUST  
cancellation時にpending continuationを必ずresumeし、leakさせない。

MN-SWIFT-009 MUST  
View fileはbackend protocol typeをimportしてはならない。

MN-SWIFT-010 MUST  
一つのsource fileは原則500行以下とし、generated protocol modelは例外とする。

## 27. Repository structure

MN-REPO-001 MUST  
repositoryは次の責務分割を持つ。

```text
MarimoNative/
  App/
    MarimoNativeApp.swift
    AppCommands.swift
    WindowCoordinator.swift

  Domain/
    NotebookDocumentState.swift
    NotebookCellState.swift
    ExecutionState.swift
    JSONValue.swift

  Application/
    NotebookStore.swift
    NotebookIntents.swift
    DocumentService.swift
    EnvironmentService.swift
    ExportService.swift

  Backend/
    MarimoBackend.swift
    MarimoLSPAdapter.swift
    SessionCoordinator.swift

  Protocol/
    LSP/
      JSONRPCMessage.swift
      LSPNotebookModels.swift
      JSONRPCConnection.swift
    Marimo/
      MarimoCommand.swift
      MarimoNotification.swift
      OwnedNotebookDocument.swift
      ProtocolLock.swift

  Process/
    LSPProcess.swift
    ProcessTermination.swift
    BoundedStderrBuffer.swift

  Document/
    AtomicFileWriter.swift
    ExternalChangeMonitor.swift
    RecentDocuments.swift

  UI/
    Notebook/
    Cell/
    Toolbar/
    Sidebar/
    Inspector/

  Editor/
    NativeCodeEditor.swift
    TextKitCoordinator.swift
    PythonHighlighter.swift
    LSPRangeConverter.swift

  Output/
    OutputRendererRegistry.swift
    TextOutputView.swift
    JSONOutputView.swift
    ImageOutputView.swift
    CSVOutputView.swift
    ErrorOutputView.swift
    MimeBundleResolver.swift

  Widgets/
    MarimoComponentDecoder.swift
    WidgetValueStore.swift
    NativeSliderView.swift

  WebFallback/
    IsolatedOutputWebView.swift
    OutputWebPolicy.swift
    BundledRenderAssets/

  Environment/
    PythonDiscovery.swift
    PythonPreflight.swift
    EnvironmentRecord.swift

  Resources/
    Sidecar/
    Fixtures/
    Localizable.xcstrings
    THIRD_PARTY_NOTICES.md

  Tests/
    Unit/
    Contract/
    Integration/
    UI/

  Tools/
    build-sidecar.sh
    generate-protocol-models.py
    verify-bundle-signatures.sh
    notarize.sh
```

MN-REPO-002 MUST  
sidecar buildとprotocol model generationは再現可能なscriptにする。

MN-REPO-003 MUST  
`protocol-lock.json`へcommit、package version、schema hash、生成日時を保存する。

```json
{
  "marimoLspCommit": "3998b939c4e3bb09853817344ba9a976eeac8a66",
  "marimoLspVersion": "0.1.0",
  "marimoBaseVersion": "0.24.0",
  "kernelMarimoVersion": "0.24.0",
  "ownedDocumentVersion": "1",
  "commandMethod": "marimo/command",
  "notificationMethod": "marimo/kernelNotification"
}
```

## 28. Test strategy

### 28.1 Unit test

MN-TEST-001 MUST  
JSON-RPC parserは、1 byteずつ分割したinput、header途中分割、payload途中分割、複数message連結、invalid length、invalid UTF-8、64 MiB超過をtestする。

MN-TEST-002 MUST  
Owned Documentはsuccess、null field、unknown metadata、invalid versionをtestする。

MN-TEST-003 MUST  
UTF-16 range converterはASCII、日本語、emoji、結合文字、改行をtestする。

MN-TEST-004 MUST  
`cell-op` partial updateはfield omission、output replace、console append、console clear、stale、unknown cellをtestする。

MN-TEST-005 MUST  
MIME bundle resolverはprecedenceとhiding ruleをgolden testする。

MN-TEST-006 MUST  
slider decoderはHTML entity、JSON attribute、steps、debounce、invalid schema、random ID changeをtestする。

MN-TEST-007 MUST  
atomic writerはsuccess、permission failure、disk conflict、temporary file cleanupをtestする。

### 28.2 Contract test

MN-TEST-010 MUST  
pinしたmarimo-lspからcommand schemaとnotification schemaのfixtureを生成し、Swift decoderで全fixtureをdecodeする。

MN-TEST-011 MUST  
Swift encoderが生成したMVP commandをPython側msgspec modelへ戻し、unknown fieldなしでdecodeできることをtestする。

MN-TEST-012 MUST  
protocol-lockのhashが変化した場合、CIをfailさせる。

MN-TEST-013 MUST  
marimo-lspまたはmarimo versionを更新するpull requestは、fixture差分を必須review対象にする。

### 28.3 Integration test

MN-TEST-020 MUST  
実際のbundled sidecarをstdioで起動し、initialize、parse、didOpen、execute、notification、print、shutdownを通す。

MN-TEST-021 MUST  
次のNotebook fixtureを用意する。

- two-cell dependency
- slider reactive
- stdout and stderr
- Python exception
- syntax error
- infinite loop for interrupt
- PNG plot
- JSON output
- CSV table
- HTML output
- external file conflict
- missing marimo environment
- wrong marimo version
- kernel crash

MN-TEST-022 MUST  
two-cell dependencyでは、上流cellの値変更後にmarimoが下流cellを再実行し、Swiftが依存関係を計算していないことをspyで確認する。

MN-TEST-023 MUST  
slider fixtureでは2から7へ変更してoutputが4から14へ変化することを確認する。

MN-TEST-024 MUST  
infinite loopへInterruptを送り、10秒以内にUIが操作可能状態へ戻ることを確認する。

MN-TEST-025 MUST  
Saveした`.py`を公式marimo 0.24.0でparseできることを確認する。

MN-TEST-026 MUST  
公式marimoで作成したfixtureをMarimoNativeで開き、編集、保存し、再び公式marimoで開けることを確認する。

MN-TEST-027 MUST  
app終了後、起動したsidecarとkernel PIDが残っていないことを確認する。

MN-TEST-028 MUST  
live sessionを持つuntitled NotebookをSave Asした場合、`move-session`後も同じsession IDで実行を継続でき、以後のnotificationが新URIへ届くことを確認する。

MN-TEST-029 MUST  
untitled Notebookでcell追加、削除、並べ替えを行い、structural didChange後もsession IDと既存outputが維持されることを確認する。

### 28.4 UI test

MN-TEST-030 MUST  
Notebook root hierarchyにWKWebViewが存在しないことをtestする。WKWebViewはoutput subtree内だけを許可する。

MN-TEST-031 MUST  
100 cell fixtureをscrollして、cell selectionとfocusがずれないことを確認する。

MN-TEST-032 MUST  
Japanese IME composition中に未確定文字列がkernelへ送られないことを確認する。

MN-TEST-033 MUST  
VoiceOver label、keyboard shortcut、Reduce Transparencyをtestする。

## 29. Continuous integration and release gate

MN-CI-001 MUST  
pull requestごとにSwift build、unit test、contract test、integration test、format、lintを実行する。

MN-CI-002 MUST  
release candidateではclean macOS 26 arm64 VMまたは専用machineでnotarized artifactを検証する。

MN-CI-003 MUST  
release pipelineは次を検証する。

- appと全nested executableのcodesign
- Hardened Runtime
- notarization success
- stapled ticket
- sidecar offline startup
- Python environment selection
- sample Notebook execution
- process cleanup

MN-CI-004 MUST  
debug buildではsystemまたはcheckout上のmarimo-lspを明示的設定で使用してよい。release buildでは禁止する。

MN-CI-005 MUST  
protocol pinが一致しないrelease artifactを生成してはならない。

## 30. 実装ゲート

### Gate A: Backend handshake

完了条件:

- bundled sidecarが起動する
- initializeとinitializedが成功する
- parse-notebookで二つのcellを取得できる
- app終了時にsidecarが終了する
- UIはまだ静的cell表示でよい

### Gate B: Native document

完了条件:

- `.py`をFinderまたはOpen Panelから開ける
- cellをnative ScrollViewへ表示できる
- NSTextViewで編集できる
- print-notebook経由でatomic saveできる
- open直後のCommand-Sはfileを書き換えない

### Gate C: Kernel execution

完了条件:

- Python executableを選択できる
- preflightが成功する
- didOpen、didChange、executeの順序が保証される
- cell statusとtext outputが表示される
- Run All、Interrupt、Restartが動作する

### Gate D: Native output

完了条件:

- text、error、traceback、JSON、PNG、CSVがnative Viewで表示される
- unsupported MIMEがcrashせず表示される
- Notebook scrollがWebViewに置き換わっていない

### Gate E: Native slider

完了条件:

- `marimo-ui-element`と`marimo-slider`をstrict decodeできる
- Slider 2でoutput 4、Slider 7でoutput 14になる
- random ID changeでresetする
- same object IDの複数instanceが同期する

### Gate F: Product release

完了条件:

- Liquid Glassはtoolbar、sidebar、inspectorだけに適用される
- external change recoveryが動く
- trust promptが動く
- Developer ID署名、notarization、offline testが通る
- 全MVP testと要件traceabilityが通る

MN-GATE-001 MUST  
前Gateの完了条件がCIで固定されるまで次Gateの機能をmain branchへ混在させてはならない。

MN-GATE-002 MUST  
各Gate完了時に該当要件IDとtest名の対応表を更新する。

## 31. 要件traceability

MN-TRACE-001 MUST  
`Tests/Requirements.yml`へ要件IDとtest caseを記録する。

```yaml
MN-LSP-004:
  - JSONRPCFramingTests/testHeaderSplitAtEveryByte
  - JSONRPCFramingTests/testPayloadSplitAtEveryByte

MN-WIDGET-032:
  - ReactiveSliderIntegrationTests/testSliderSevenProducesFourteen

MN-PROD-003:
  - NativeHierarchyUITests/testNoNotebookLevelWebView
```

MN-TRACE-002 MUST  
MUST要件にtestまたはmanual verificationが一つも紐付かない場合、releaseを禁止する。

MN-TRACE-003 MUST  
manual verificationだけの要件は、release checklistへ実施者、日時、artifact hashを記録する。

## 32. MVP受け入れ判定

MVPは次のすべてを満たした場合だけ完成とする。

MN-ACCEPT-001 MUST  
marimo 0.24.0で作成した`.py`を開き、cellをSwiftUI/AppKitのnative hierarchyとして表示できる。

MN-ACCEPT-002 MUST  
Notebook全体のscroll、cell選択、code editing、toolbar、sidebar、inspectorがWeb技術に依存しない。

MN-ACCEPT-003 MUST  
選択したlocal Python環境でcodeを実行し、textとimage outputをcell直下へ表示できる。

MN-ACCEPT-004 MUST  
marimoがdependency graphとreactive rerunを担当し、Swift側にdependency graph実装が存在しない。

MN-ACCEPT-005 MUST  
native sliderを2から7へ動かすと、dependent outputが4から14へ変わる。

MN-ACCEPT-006 MUST  
Command-Sでmarimo互換`.py`を保存し、公式marimo 0.24.0で再度開ける。

MN-ACCEPT-007 MUST  
Colab型のbrowser page scroll、Notebook-level WebView、Electron windowが存在しない。

MN-ACCEPT-008 MUST  
app終了後にsidecarとkernelが残らない。

MN-ACCEPT-009 MUST  
ユーザーのPython環境を確認なしに変更しない。

MN-ACCEPT-010 MUST  
notarized artifactをnetworkなしのclean macOS 26環境へinstallし、open、edit、save、executeできる。

## 33. R1後の拡張境界

次の機能はMVP完了後に別仕様として追加する。現在の型とmodule boundaryは拡張可能にするが、MVP実装へ未完成機能を混ぜない。

- native checkbox、switch、number、text、textarea、dropdown、multiselect、radio、date、range slider
- smart Markdown projection
- smart SQL projection
- native DataFrame viewer
- native Vega renderer
- anywidget bridge
- package manager UI
- Python language server completion、hover、rename、diagnostics
- multiple workspace roots
- remote kernel
- session persistence
- automatic update

MN-EXT-001 MUST  
smart MarkdownまたはSQLを追加する際、Swiftの文字列置換で`mo.md`、`mo.sql`を変換してはならない。上流marimo-lspへ変換commandを追加するか、上流smart-cellsと同一fixtureに対して完全一致するparserを独立moduleとして実装する。

MN-EXT-002 MUST  
native widget追加はtagごとにtyped descriptor、validation、value mapping、contract fixtureを追加する。

MN-EXT-003 MUST  
上流React rendererをNotebook画面として再利用してはならない。必要なfallback assetはoutput単位に隔離する。

## 34. 参照固定点

実装時に参照する上流fileと仕様を次へ固定する。

### marimo-lsp

- Repository: https://github.com/marimo-team/marimo-lsp
- Commit: https://github.com/marimo-team/marimo-lsp/commit/3998b939c4e3bb09853817344ba9a976eeac8a66
- Private protocol: https://github.com/marimo-team/marimo-lsp/blob/3998b939c4e3bb09853817344ba9a976eeac8a66/src/marimo_lsp/protocol.py
- Command adapter: https://github.com/marimo-team/marimo-lsp/blob/3998b939c4e3bb09853817344ba9a976eeac8a66/src/marimo_lsp/api.py
- Session forwarding: https://github.com/marimo-team/marimo-lsp/blob/3998b939c4e3bb09853817344ba9a976eeac8a66/src/marimo_lsp/sessions.py
- Source parse/print: https://github.com/marimo-team/marimo-lsp/blob/3998b939c4e3bb09853817344ba9a976eeac8a66/src/marimo_lsp/notebook_source.py
- Kernel launch: https://github.com/marimo-team/marimo-lsp/blob/3998b939c4e3bb09853817344ba9a976eeac8a66/src/marimo_lsp/kernels/manager.py
- Package pin: https://github.com/marimo-team/marimo-lsp/blob/3998b939c4e3bb09853817344ba9a976eeac8a66/pyproject.toml

### marimo

- Repository: https://github.com/marimo-team/marimo
- Reference commit: https://github.com/marimo-team/marimo/commit/8869b186a8c1c5bc9f5e123e7df7b6677ec06b8d
- Cell output model: https://github.com/marimo-team/marimo/blob/8869b186a8c1c5bc9f5e123e7df7b6677ec06b8d/marimo/_messaging/cell_output.py
- MIME types: https://github.com/marimo-team/marimo/blob/8869b186a8c1c5bc9f5e123e7df7b6677ec06b8d/marimo/_messaging/mimetypes.py
- MIME precedence: https://github.com/marimo-team/marimo/blob/8869b186a8c1c5bc9f5e123e7df7b6677ec06b8d/frontend/src/utils/mime-types.ts
- UI element HTML: https://github.com/marimo-team/marimo/blob/8869b186a8c1c5bc9f5e123e7df7b6677ec06b8d/marimo/_plugins/ui/_core/ui_element.py
- UI component attributes: https://github.com/marimo-team/marimo/blob/8869b186a8c1c5bc9f5e123e7df7b6677ec06b8d/marimo/_plugins/core/web_component.py
- Slider schema: https://github.com/marimo-team/marimo/blob/8869b186a8c1c5bc9f5e123e7df7b6677ec06b8d/frontend/src/plugins/impl/SliderPlugin.tsx

### Platform

- Language Server Protocol: https://microsoft.github.io/language-server-protocol/
- Apple Liquid Glass: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- AppKit design and scroll edge behavior: https://developer.apple.com/videos/play/wwdc2025/310/
- Developer ID: https://developer.apple.com/developer-id/
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Hardened Runtime: https://developer.apple.com/documentation/security/hardened-runtime

## 35. 最終禁止事項

MN-FINAL-001 MUST NOT  
marimo Web UIを隠してnative appと呼んではならない。

MN-FINAL-002 MUST NOT  
Swift側でmarimo dependency graphを模倣してはならない。

MN-FINAL-003 MUST NOT  
Python sourceを独自parserでcell分割してはならない。

MN-FINAL-004 MUST NOT  
保存sourceをSwiftのtemplateで生成してはならない。

MN-FINAL-005 MUST NOT  
user environmentへ確認なしでpackageをinstallしてはならない。

MN-FINAL-006 MUST NOT  
shell injection可能なProcess起動を行ってはならない。

MN-FINAL-007 MUST NOT  
Notebook source、output、password、secretをtelemetryまたはdefault logへ送ってはならない。

MN-FINAL-008 MUST NOT  
Liquid GlassをNotebook contentの装飾として乱用してはならない。

MN-FINAL-009 MUST NOT  
未対応MIMEまたはnotificationでappをcrashさせてはならない。

MN-FINAL-010 MUST NOT  
protocol pin、contract test、process cleanup testを通さずreleaseしてはならない。
