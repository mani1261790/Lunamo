# SwiftTerm 比較試作（2026-11-11）

## 結論

SwiftTerm 1.99.3を独立したSwift Packageで評価した。端末としての機能は有望だが、
既存ターミナルの置換は保留。標準の `LocalProcess.terminate()` だけでは対話型zshと
その前景Pythonを2秒以内に終了できず、双方が残った。本体へ組み込む前に、
セッション単位の終了・猶予・強制終了と、PID再利用を考慮した所有権管理が必要。

これはSwiftTermの端末描画の否定ではなく、Lunamo側に追加実装が必要なライフサイクルの判定。
本体の依存関係、既存のターミナル画面は変更していない。

## 再現方法

プロジェクトルートから実行する。ユーザーのシェル初期化ファイルやノートブックは読み書きしない。

```sh
swift run --package-path Tools/TerminalEvaluation TerminalEvaluation "$PWD/.build/Sidecar/bin/python3"
```

固定依存: SwiftTerm 1.99.3、revision `282c3c3a932b55c129628876b70f37d993af1615`。
推移依存は同ディレクトリのPackage.resolvedに記録。アプリには同梱しない。
結果: `.build/terminal-evaluation.log`。

| 項目 | 既存方式 | SwiftTerm試作の実測 |
| --- | --- | --- |
| 接続 | stdin/stdoutパイプ、TERM=dumb | PTY、isatty=True |
| 対話入力 | 独自入力欄と履歴 | Python REPL、input()成功 |
| 日本語 | 文字列出力 | 日本語のUTF-8往復成功。描画・IMEの実画面評価は未実施 |
| 中断 | Ctrl+Cのシグナル変換なし | 0x03でKeyboardInterrupt、REPL継続 |
| サイズ | 端末サイズ通知なし | 33行101列への変更がsttyに反映 |
| Python環境 | venvのPATHを渡す。非venvとログインシェルのPATH上書きは残課題 | 初期化ファイルを読まないzshで選択Pythonと作業フォルダが一致 |
| 終了 | LSPProcessの終了処理 | terminateのみではshell/前景子とも残存。自動採用の条件を満たさない |

試作自身は捕捉した正確なPIDのみを終了し、プロセスが残っていないことも検証した。
出力のテスト結果を採用可否と混同しない。`probeCleanup=true` は試作の後片付けであり、
SwiftTerm標準終了APIの合格を意味しない。

## 統合を再開する条件

1. UIから独立したPTYセッションを作り、閉じる・フォルダ変更・環境変更・アプリ終了で同じ終了処理を使用する。
2. 前景ジョブと通常の背景ジョブを終了し、終了要求を無視する子も猶予後に回収する。所有していないプロセスを殺さない。
3. ノートブックで選んだPythonを非venvでも一致させる。シェル初期化によるPATH上書きの扱いを明示する。
4. 日本語IME、コピー／貼り付け、スクロール、選択、VoiceOver、パネルリサイズを実画面で確認する。
5. 出力経由のクリップボード／URL操作を、ユーザー操作と区別して扱う。

参照: [公式SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)、
[固定版の終了実装](https://github.com/migueldeicaza/SwiftTerm/blob/v1.99.3/Sources/SwiftTerm/LocalProcess.swift)。
