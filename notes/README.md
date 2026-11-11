# 学習ノート

実装を進めるなかで説明してもらった概念のメモ。1概念1ファイル。運用ルールは`CLAUDE.md`の「学習ノート」節を参照。

## 索引

（まだノートはありません）
- [VS Code拡張の実行環境](vscode-extension-runtime.md) — 入口だけはJS必須。JS以外の言語は別プロセス（LSP）かWASMで動かす
- [HaxeとTSの相互運用](haxe-ts-interop.md) — ESM出力・`.d.ts`・クラス重複の3課題。窓口を狭くし、中身をターゲット非依存に保つ
