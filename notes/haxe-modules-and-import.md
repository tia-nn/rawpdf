# Haxeのモジュールとimport

Haxeでは1ファイルが1**モジュール**で、1モジュールに複数の型を書ける。モジュールを`import`すると中の型がすべて見える。同じパッケージで`import`なしに見えるのは、各モジュールの**主型だけ**で、サブタイプは見えない。

## なぜ必要か

関係の深い小さな型（Green木の`GreenTrivia`/`GreenToken`/`GreenNode`など）を、ファイルに分けるか1ファイルにまとめるかを決めるとき、「使う側で`import`が何行になるか」が判断材料になる。その数はHaxeの名前解決の規則で決まる。

## どういう仕組みか

- **モジュール**: ファイル`Green.hx`がモジュール`rawpdf.cst.syntax.Green`になる。ファイル名と同じ名前の型を**主型**、それ以外を**サブタイプ**と呼ぶ
- **モジュールのimport**: `import rawpdf.cst.syntax.GreenNode;`と書くと、主型`GreenNode`だけでなく、同じファイルのサブタイプ（`GreenToken`等）も修飾なしで使える。`GreenNode.GreenToken`のように修飾して書くこともできる
- **同じパッケージで`import`不要なのは主型だけ**: `rawpdf.cst.syntax`の中のファイルどうしでも、`import`なしで見えるのは別モジュールの主型（`GreenNode`）だけ。サブタイプ（`GreenToken`）は「Type not found」になり、`import rawpdf.cst.syntax.GreenNode;`か、`GreenNode.GreenToken`という修飾が要る。ただし同じパッケージからの`import`は、checkstyleの`UnusedImport`が「不要なimport」と誤検出してCIを落とす
- **ワイルドカード**: `import rawpdf.cst.syntax.*;`でパッケージ内の全モジュールが見える。このプロジェクトではcheckstyleの`AvoidStarImport`で禁止している
- **`import.hx`**: ディレクトリに置くと、そのディレクトリ以下の全ファイルの先頭に書いたのと同じになる。何がどこから来たのかが見えにくくなるので、使うなら範囲を絞る
- **名前の衝突**: `import`したenumのコンストラクタは、式の中で同名の型より優先される。`enum Child { Token(t:Token); }`が見えていると、`Token.make()`は「コンストラクタ`Token`に`make`は無い」というエラーになる

## 具体例

```
syntax/GreenNode.hx   … GreenNode（主型）＋ GreenToken, GreenTrivia（サブタイプ）
syntax/Red.hx         … GreenNodeは見える。GreenTokenは見えない（同じパッケージでもサブタイプ）
parse/Parser.hx       … import rawpdf.cst.syntax.GreenNode;  の1行で3つとも見える
```

型ごとにファイルを分けた場合は、どれも主型になるので`syntax/`の中ではimport不要になり、`parse/`などの外から使う側だけが、使う型の数だけ`import`を書く。1ファイルにまとめた場合は、外からは1行で済むが、同じパッケージの中では修飾（またはcheckstyleに掛かるimport）が要る。

## このプロジェクトでの使われ方

- ファイル構成: パーサ詳細設計2章。Green木は型ごとにファイルを分けた（`GreenTrivia.hx`・`GreenToken.hx`・`GreenNode.hx`）。上の具体例の1ファイルにまとめる形は採っていない。ノードの子の型`GreenNodeChild`だけは、`GreenNode.hx`のサブタイプとして置いている（`GreenToken.hx`からは`GreenNode.GreenNodeChild`と書いて参照する）
- checkstyleの`FileNameCase`は「ファイル名と同じ名前の型（主型）があること」を求める。`Green.hx`に`Green`という型が無いとCIで落ちる
- 依存方向（parser ← semantics ← lsp-editor）は`.hxml`のクラスパスで強制する（CLAUDE.md「技術スタック」）。importの書き方とは別の仕組み

## 参考

- Haxe Manual「Modules and Paths」「Import」「import defaults (import.hx)」

## 関連ノート

- [Haxeのコンパイル対象とDCE](haxe-compilation-scope.md)
- [Green/Red木](green-red-tree.md)
