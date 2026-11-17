# SyntaxKindと`enum abstract`

構文木の要素の種類（`SyntaxKind`）を、Haxeの`enum abstract SyntaxKind(Int)`で表す。実行時はただの`Int`なので軽く、値の割り当てを工夫すれば「トリビアか」「ノードか」を範囲比較だけで判定できる。

## なぜ必要か

CST（具象構文木）では、トリビア・トークン・ノードのすべてが「種類」を1つ持つ。Green木（[M1-5]で作る、不変で共有される木）は、種類ごとにクラスを分けず、**1つのノード型＋`kind`フィールド**で表す（rowan・Roslynと同じ方式）。そのため次の2つが必要になる。

- 種類を表す値が**小さく比較が速い**こと。トークン1個ごとに持つので、数が多い
- 「このkindはトリビアか」「キーワードか」といった**分類を一か所で答える**関数があること。レキサー・TokenSource・パーサ・ダンプがみな使う

## どういう仕組みか

### Haxeの`enum`と`enum abstract`の違い

| | `enum`（代数的データ型） | `enum abstract X(Int)` |
|---|---|---|
| 実行時の姿 | オブジェクト（JSでは配列や専用オブジェクト） | 中身の型（ここでは`Int`）そのもの |
| 値にデータを持たせる | できる（`Ref(num:Int, gen:Int)`など） | できない。定数だけ |
| 値の大小比較・範囲判定 | できない | 中身が`Int`なので抽象型の内側で`this < 10`のように書ける |
| `switch`の網羅性検査 | される | される（Haxe 4以降。手元で確かめておくとよい） |

`SyntaxKind`は「データを持たない定数の集まり」で、しかも範囲判定をしたいので`enum abstract`が合う。値ごとにデータを持つもの（意味解析の`PdfValue`など）は`enum`が合う。

### `abstract`は「型だけ別物、中身は同じ」

`abstract X(Int)`は、コンパイル時には`Int`と別の型として扱われるが、出力されるコードでは`Int`に消える。この「別の型」であることを、どこまで緩めるかを`from`/`to`で選ぶ。

- `from Int`: 任意の`Int`を暗黙に`SyntaxKind`として渡せる。便利だが、`isTrivia(7)`のように**存在しない種類**が紛れ込む
- `to Int`: `SyntaxKind`を暗黙に`Int`として使える。外から`kind < 10`と書けてしまい、分類ロジックが散らばる
- どちらも付けない: 変換は`cast`で明示するしかない。間違いがコンパイルエラーになる（`var k:SyntaxKind = 3;`は`Int should be SyntaxKind`）

`from`/`to`を付けなくても、型検査をすり抜ける抜け道は残る。`cast`、`untyped`、そして**`Dynamic`**（`var d:Dynamic = 3; var k:SyntaxKind = d;`はエラーにならない）。純Haxe層ではこの3つを使わない、という運用で守る。

抽象型の**内側**（メソッドの本体）では`this`が中身の`Int`なので、`from`/`to`が無くても範囲比較を書ける。分類ロジックを内側に閉じ込めて、外には`isTrivia()`などだけを見せる、という形にできる。

```haxe
// 形だけ。値の一覧と判定の境界は設計（詳細3章）を見て自分で決める
enum abstract SyntaxKind(Int) {
	var Whitespace = 0;
	// ...
	public inline function isTrivia():Bool return /* thisの範囲で判定 */;
}
```

### 内側で値どうしを比べる: `this`と`abstract`

内側の`this`は中身の型（`Int`）なので、定義済みの値（型は抽象型）と比べるには`this == cast Foo`と`cast`が要る。**等しいかどうかだけを見るなら、`abstract`キーワード**（`this`を抽象型として見たもの）を使えば`cast`なしで書ける。

```haxe
public inline function isFoo() return abstract == Foo; // 抽象型どうしの比較
```

大小比較（区間判定）は抽象型どうしでは書けない（`Int`への`to`が無いため）ので、そちらは`this`と`cast`を使う。

### 値を「区間ごと」に割り当てる

詳細設計3章は、トリビア0〜、トークン10〜、キーワード30〜42、ノード100〜と、**グループごとに区間を分け、間を空けて**割り当てている。こうすると分類は区間の比較2回で済み、種類を後から足すときも空きに入れられる。

注意点は**区間の隙間**。たとえば「トリビアは`this < 10`」と書くと、存在しない値`5`もトリビアと判定される。`from Int`を付けず、`cast`でしか作れないようにしておけば普段は問題にならないが、どう振る舞うかは決めてテストに書いておくとよい。

## 具体例

```
1 0 obj << /Type /Page >> endobj
```

をレキサーが切り出すと（トリビアは種類だけ示す）:

| バイト列 | kind | グループ |
|---|---|---|
| `1` | Integer | トークン |
| ` ` | Whitespace | トリビア |
| `0` | Integer | トークン |
| ` ` | Whitespace | トリビア |
| `obj` | KwObj | トークン（キーワード） |
| ` ` | Whitespace | トリビア |
| `<<` | LeftDoubleAngle | トークン |
| ` ` | Whitespace | トリビア |
| `/Type` | Name | トークン |
| … | | |
| `endobj` | KwEndobj | トークン（キーワード） |
| （長さ0） | EndOfFile | トークン（番兵） |

パーサはこれを`IndirectObject`（ノード）・`Dictionary`（ノード）・`DictEntry`（ノード）でくくる。トークンとノードの`kind`は同じ`SyntaxKind`型に入る。

## このプロジェクトでの使われ方

- 値の割り当てと分類ヘルパの一覧: パーサ詳細設計3章。Haxeへの読み替えは同0章
- 種類の一覧と、それぞれの意味: パーサ基本設計4.5節、詳細設計1章（`HeaderMarker`・`StreamBody`・`LeftBrace`/`RightBrace`の追補）
- 統括設計3.1節: Haxeを選んだ理由の1つが`enum abstract`

## 参考

- rowan: `SyntaxKind(u16)`という薄い数値型だけを持ち、具体的な種類の一覧は利用側（rust-analyzer）が定義する
- rust-analyzer: `crates/parser/src/syntax_kind/generated.rs`。`is_keyword`・`is_punct`・`is_literal`などの分類関数がある（コード生成で作っている）
- TypeScriptコンパイラ: `src/compiler/types.ts`の`enum SyntaxKind`の末尾にある`FirstKeyword`/`LastKeyword`などの区間マーカー。分類は区間比較で行っている
- Roslyn: `src/Compilers/CSharp/Portable/Syntax/SyntaxKindFacts.cs`（`IsKeywordKind`など）
- Haxe Manual: 「Abstract」章の「Enum abstracts」「Implicit Casts」

## 関連ノート

- [Haxeのコンパイル対象とDCE](haxe-compilation-scope.md) — `SyntaxKind.hx`をどこからも参照しないうちは、`build.hxml`の`include`がないと型検査されない
