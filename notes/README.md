# 学習ノート

実装を進めるなかで説明してもらった概念のメモ。1概念1ファイル。運用ルールは`CLAUDE.md`の「学習ノート」節を参照。

## 索引

- [Haxeのコンパイル対象とDCE](haxe-compilation-scope.md) — `--main`からたどれるモジュールしか型検査されない。ライブラリは全体を含める指定が要る（エディタ用の設定には入れない）
- [SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md) — 種類を`Int`の上の抽象型で表し、値の区間で分類する
- [Green/Red木](green-red-tree.md) — 長さだけを持つ不変・共有のGreen木と、親と絶対位置を後付けするRedビューの2層構成
- [Haxeの`inline`](haxe-inline.md) — 呼び出しをコンパイル時に展開する。小さな`abstract`のメソッドと定数に使い、大きい・再帰する関数には使わない
- [バイト分類（ByteClass）](byte-class.md) — 256バイトをWhitespace/Delimiter/Regularに分ける表。トークンの切れ目を決める
- [Haxeでビットフラグを表す](haxe-bit-flags.md) — 「集合」の値は`abstract(Int)`＋`@:op`＋`has`、`enum abstract`、`haxe.EnumFlags`の3通り。網羅性の前提が違う
- [stream境界キャッシュ（StreamBodyHint）](stream-boundary-cache.md) — 再パースでstream本体の境界を前回の結果から再利用し、巨大な本体の再走査を避ける
- [Haxeのnull許容と読み取り専用ビュー](haxe-null-and-readonly-view.md) — `Null<T>`＋`?.`・`??`で省略可能な値、`@:forward`の`abstract`か関数型で書き換えさせないMap。標準ライブラリだけで書く
- [手書きレキサーと最長一致](hand-written-lexer.md) — カーソルと先頭バイトの分岐で1トークンずつ切り出す。終わりは読めるだけ長く読んで決め、必ず1バイト以上進める
- [イベント型ビルダー](event-builder.md) — パーサは「開始・トークン・終了」を送るだけにし、ビルダーが2本のスタックでGreen木に組む。エラー回復の経路でも木が崩れない
- [Haxeのモジュールとimport](haxe-modules-and-import.md) — 1ファイル1モジュールに複数の型。モジュールをimportすればサブタイプも見え、同じパッケージはimport不要
