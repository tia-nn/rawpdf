# Haxeでビットフラグを表す

「複数の性質を同時に持てる」値（`TokenFlags`など）は、「1つを選ぶ」値（`SyntaxKind`など）とは別の型の形にする。Haxeでは`abstract X(Int)`に演算子と判定メソッドを付ける方法、`enum abstract`を使う方法、標準ライブラリの`haxe.EnumFlags`を使う方法の3つがあり、それぞれの違いは「値が集合であることを型でどう表すか」にある。

## なぜ必要か

トークンには「EOFで打ち切られた（`Unterminated`）」「幅ゼロの合成トークン（`Missing`）」といった属性が付く。これらは**同時に立ち得る**（理屈の上では両方立つ組み合わせもある）。そのため値は「どれか1つ」ではなく「立っているものの集合」になり、1ビットに1フラグを割り当てて`Int`に詰める。

TSの擬似表記では、合成値を表せる型がないので`type TokenFlags = number`と型を緩めていた（パーサ詳細設計4章）。Haxeの抽象型を使えば、型を緩めずに表せる。

## どういう仕組みか

### 「1つを選ぶ」と「集合」の違い

| | 1つを選ぶ（`SyntaxKind`・`ByteClass`） | 集合（`TokenFlags`） |
|---|---|---|
| 取り得る値 | 列挙した値のどれか1つ | 列挙した値の任意の組み合わせ（2^n通り） |
| 主な操作 | `==`、`switch` | 合成（`|`）、含むかの判定（`&`） |
| `switch`の網羅性 | 意味がある | 意味がない（`3`のような合成値に一致する`case`が無い） |

`enum abstract`は「列挙した値のどれか」を表すための機能で、`switch`の網羅性検査もその前提で働く。集合を`enum abstract`で表すと、合成値（例: `1 | 2 = 3`）が「列挙に無い値」になり、この前提が崩れる。

### 3つの書き方

**A. `abstract TokenFlags(Int)` ＋ 定数 ＋ 演算子**

- 定数は`public static inline var`で並べる（値は`1 << 0`、`1 << 1`のように明示する）
- `@:op(A | B)`で合成を定義し、戻り値の型を`TokenFlags`にする。これで合成値も同じ型のまま扱える
- 「含むか」は`has(flag)`のような`inline`メソッドにして、ビット演算を型の内側に閉じ込める（`SyntaxKind`の`isTrivia`と同じ考え方。[SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md)）
- `enum`ではないので、網羅性の前提を持ち込まない

**B. `enum abstract TokenFlags(Int)` ＋ 演算子**

- 書き方はAとほぼ同じで、定数宣言が`var X = 1;`と短く書ける
- 合成値が列挙に無い値になるので、`switch`を書くと誤解を招く（`default`を付けないと合成値はどの`case`にも一致しない）
- 「1つを選ぶ型」という見た目と中身がずれる

**C. `haxe.EnumFlags<T>`（標準ライブラリ）**

- フラグ1個は普通の`enum TokenFlag { Unterminated; Missing; }`、集合は`EnumFlags<TokenFlag>`と、**要素と集合が別の型になる**
- `has`・`set`・`unset`が最初からある。中身は`Int`の`abstract`なので、集合そのものはオブジェクトを作らない
- ビット位置は`enum`の宣言順（`enumIndex`）で決まる。並びを入れ替えるとビットが変わる
- `set`は値を書き換えるので、`final`のフィールドとは相性がよくない（合成してから渡す形になる）

### `has`の意味を決めておく

`has(Unterminated | Missing)`が「どれか1つでも立っているか」なのか「全部立っているか」なのかは、ビット演算の書き方で変わる（`(this & f) != 0`か`(this & f) == f`か）。Aで作るなら、引数に1フラグだけを渡す前提にするのか、どちらの意味にするのかを決めてテストに書く。

1フラグを渡す限り、2つの意味は同じ結果になる。違いが出るのは、合成値と`NONE`（=0）を渡したとき。

| 引数 | 「全部」（`(this & f) == f`） | 「どれか」（`(this & f) != 0`） |
|---|---|---|
| `UNTERMINATED`（1フラグ） | 同じ | 同じ |
| `UNTERMINATED \| MISSING` | 両方立っていれば真 | 片方でも立っていれば真 |
| `NONE` | **常に真**（空集合はどの集合にも含まれる） | **常に偽** |

既存の慣習:

- Rustの`bitflags`クレート: `contains`が「全部」、`intersects`が「どれか」。名前で意味を分けている
- C#の`Enum.HasFlag`: 「全部」。`HasFlag(None)`は常に`true`
- TypeScriptコンパイラ: メソッドを作らず、`(flags & NodeFlags.X) !== 0`（「どれか」）を各所に直接書く

「フラグが1つも立っていないか」は、`has(NONE)`ではなく`== NONE`や専用のメソッドで書くほうが誤読されない。

## 具体例

`(abc`で終わるファイルでは、literal stringが閉じないままEOFに達する。

```
LiteralString  flags = Unterminated   (= 0b01)
EndOfFile      flags = None           (= 0b00)
```

パーサが`)`を補えずに合成トークンを入れる場合は`Missing`（`0b10`）を立てる。ダンプやテストでは、数値ではなくフラグ名で出すと読みやすい（`toString`を用意する）。

## このプロジェクトでの使われ方

- パーサ詳細設計4章: `TokenFlags`の定義（`None`・`Unterminated`・`Missing`）
- 6.2節: Lexerは、サブスキャンが範囲末尾に達したら`Unterminated`を立てる（reparseの安定性判定が依存。基本設計5.5.1節）
- 4章`GreenBuilder.missingToken`: `Missing`を立てる
- Haxeへの読み替え（0章の表）には、ビットフラグの行を足して書き方を記録する

## 関連

- [SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md)
- [Haxeの`inline`](haxe-inline.md)

## 参考

- Haxe Manual「Abstract」節の Operator Overloading（`@:op`）
- Haxe標準ライブラリ `haxe/EnumFlags.hx`（短いので全体を読める）
- Roslyn `NodeFlags`、TypeScriptコンパイラ `src/compiler/types.ts`の`NodeFlags`（TSの`enum`を集合として使う例）
