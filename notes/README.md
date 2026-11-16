# 学習ノート

実装を進めるなかで説明してもらった概念のメモ。1概念1ファイル。運用ルールは`CLAUDE.md`の「学習ノート」節を参照。

## 索引

（まだノートはありません）
- [VS Code拡張の実行環境](vscode-extension-runtime.md) — 入口だけはJS必須。JS以外の言語は別プロセス（LSP）かWASMで動かす
- [HaxeとTSの相互運用](haxe-ts-interop.md) — ESM出力・`.d.ts`・クラス重複の3課題。窓口を狭くし、中身をターゲット非依存に保つ
- [lix](lix.md) — Haxeの版とライブラリをプロジェクトごとに固定する。`.haxerc`と`haxe_libraries/*.hxml`がlockfile役
- [Haxeのコンパイル対象とDCE](haxe-compilation-scope.md) — `--main`からたどれるモジュールしか型検査されない。ライブラリは全体を含める指定が要る
- [Taskfileと終了コード](taskfile-exit-code.md) — 0以外で即停止。`task`自身は既定で201、`-x`で素通し。`ignore_error`は失敗を握りつぶす
