# 学習ノート

実装を進めるなかで説明してもらった概念のメモ。1概念1ファイル。運用ルールは`CLAUDE.md`の「学習ノート」節を参照。

## 索引

- [Haxeのコンパイル対象とDCE](haxe-compilation-scope.md) — `--main`からたどれるモジュールしか型検査されない。ライブラリは全体を含める指定が要る
- [SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md) — 種類を`Int`の上の抽象型で表し、値の区間で分類する
- [Green/Red木](green-red-tree.md) — 長さだけを持つ不変・共有のGreen木と、親と絶対位置を後付けするRedビューの2層構成
- [Haxeの`inline`](haxe-inline.md) — 呼び出しをコンパイル時に展開する。小さな`abstract`のメソッドと定数に使い、大きい・再帰する関数には使わない
