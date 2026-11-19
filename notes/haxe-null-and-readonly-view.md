# Haxeのnull許容と読み取り専用ビュー（標準ライブラリだけで書く）

「省略できる値」は`Null<T>`と、Haxe 4.3の`?.`・`??`で書く。「書き換えさせないMap」は、`@:forward`で必要なメソッドだけを見せる小さな`abstract`で書くか、必要な操作を関数型で受け取る。どちらも外部ライブラリ（extypeの`Nullable`・`ReadOnlyMap`等）なしで書ける。

## なぜ必要か

パーサの`src/`は、Haxe標準ライブラリだけで書く方針である（パーサ詳細設計2章）。一方で、Lexerのオプション（詳細設計6.2節の`LexerOptions`）には次の2つの要求がある。

- `start`・`end`・`streamBodyHints`は省略でき、省略時は既定値を使う
- `streamBodyHints`はreparseが作って渡すもので、Lexerは読むだけ。Lexerが書き換えられないことを型で示したい

## どういう仕組みか

### `Null<T>`と、`?.`・`??`

- `Null<T>`: 「`T`かnull」を表す。`Int`などの基本型は、静的ターゲット（HashLink・C++）ではnullを持てないので、nullになり得るなら`Null<Int>`と書く必要がある。JSではどちらも同じに動くので、書き忘れに気づきにくい
- 匿名構造体の`?start:Int`（省略可能なフィールド）と、引数の`?opts:T`の型は、自動的に`Null<…>`になる
- `a ?? b`（Haxe 4.3〜）: `a`がnullなら`b`、そうでなければ`a`
- `a?.b`（Haxe 4.3〜）: `a`がnullならnull、そうでなければ`a.b`

2つを組み合わせると、「オプション自体の省略」と「フィールドの省略」を1つの式で扱える。

```haxe
// 形だけ。opts自体もopts.startも省略され得る
final start = opts?.start ?? 0;
```

### nullを調べた後に`Null`を外す

Haxeの型は、`if (x == null) return;`の後でも`Null<Int>`のまま変わらない（TSのような絞り込み（narrowing）は型には反映されない）。`Int`として扱いたいときは、**型注釈を書いた変数に代入する**（`final c:Int = x;`）。`Null<T>`から`T`への代入は、通常の設定では暗黙に許される。

この「暗黙に許される」が危うさでもある。nullを調べ忘れても代入できてしまい、静的ターゲットでは`0`などに化ける。`@:nullSafety(Strict)`をクラス（またはコンパイル全体の`--macro nullSafety("pkg")`）に付けると、コンパイラがnullの検査を追跡し、**調べた後の代入だけを許し、調べていない代入をエラーにする**（`Null safety: Cannot assign nullable value here.`）。

```haxe
// 形だけ
final x = peek();          // Null<Int>
if (x == null) return …;   // ここで抜ける
final c:Int = x;           // 検査済みなので、nullSafetyの下でも通る
```

### 検査済みでも、型推論には`Null`が残る

null safetyが「検査済み」と扱うのは、**null safetyの検査の中だけ**である。変数の型そのものは`Null<T>`のまま変わらない。そのため、型引数を推論する場面では`Null<T>`が使われる。

よく引っかかるのは、ジェネリックな`inline`関数に渡したときである。たとえばJSターゲットの`Std.downcast`は次の形をしている。

```haxe
// 標準ライブラリ（js/_std/Std.hx）。返り値がNull<S>ではなくS
static inline function downcast<T:{}, S:T>(value:T, c:Class<S>):S
	return if (...) cast value else null;
```

```haxe
// 形だけ
final node = children.pop();     // Null<NodeChild>
if (node == null) throw …;       // null safetyはここから先を「nullでない」と扱う
Std.downcast(node, GreenNode);   // それでも T = Null<NodeChild> と推論される
```

`inline`なので、本体が呼び出し箇所に展開されてからnull safetyが検査する。展開された`cast value`は「nullableな値（`T = Null<NodeChild>`）のキャスト」に見え、`Null safety: Cannot cast nullable value to not nullable type.`になる。受け取る変数に`Null<GreenNode>`と注釈を付けても、渡す側の`T`は変わらないので直らない。

直し方は、渡すところで**型チェック式**`(式 : 型)`を使い、nullでない型として渡すことである。

```haxe
// 形だけ
final root:Null<GreenNode> = Std.downcast((node : NodeChild), GreenNode);
```

`(node : NodeChild)`は「この式を`NodeChild`型として扱う」とコンパイラに伝える。nullの検査の後なので、null safetyはこれを許す。`T`は`NodeChild`と推論され、展開された`cast`も通る。`Std.downcast`の返り値はnullになり得る（失敗するとnull）ので、受け取る側は`Null<…>`にしてnullを調べる。

もう1つの注意点: null safetyは**配列の長さを追わない**。`if (a.length != 1) throw …;`の後でも、`a.pop()`は`Null<T>`のままである。実行時には通らない分岐でも、nullの検査は省けない。

### 「無いかもしれない値」の実行時コスト: `Option`・`Null<Int>`・番兵値

ホットループ（レキサーの「次のバイトを覗く」など、全バイトに対して呼ばれる処理）では、「無い」の表し方で速さが大きく変わる。

| 表し方 | JS | 静的ターゲット（HashLink・C++） |
|---|---|---|
| `haxe.ds.Option<Int>` | `Some(v)`のたびにオブジェクトを作る | 同じくオブジェクトを作る |
| `Null<Int>` | 数値かnullのまま。オブジェクトは作らない | `Int`をnull可能にするため箱詰め（boxing）が起きる |
| `Int`＋番兵値（`-1`） | 数値のまま | 数値のまま |

50MBを1バイトずつ覗いて合計するだけのループをNodeで測った結果（2026-11-18、`-D analyzer-optimize`付き）: `Option` 532ms、`Null<Int>` 67ms、`Int(-1)` 56ms。JSでは`Option`だけが桁違いに遅く、`Null<Int>`と番兵値の差は小さい。静的ターゲットは測っていない（表は仕組みからの予想）。

型の安全性は`Option` > `Null<Int>` > 番兵値の順。ホットループの外では`Option`や`Null`を使い、ホットループの中だけ番兵値にする、という使い分けが現実的である。番兵値を使うときは、比較を1か所の関数に閉じ込め、番兵値が外に漏れないようにする（パーサ詳細設計6.1節: `ByteClass.of`に`-1`を渡さない）。

### 読み取り専用ビュー: `@:forward`付きの`abstract`

`abstract X(Map<K, V>)`は、中身は`Map`のまま、外から見える操作を選び直した別の型になる（[SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md)の「型だけ別物、中身は同じ」）。

- `@:forward(get, exists)`: 中身の`get`・`exists`だけを、そのまま外に見せる。`set`・`remove`は見えないので、呼ぶとコンパイルエラー（`… has no field set`）
- `from Map<K, V>`: 普通の`Map`を、そのまま渡せるようにする（作る側は普通の`Map`で組み立て、渡すときにビューになる）
- `to`は付けない。付けると`Map`に戻して書き換えられる

実行時は`Map`そのものなので、余分なオブジェクトも、呼び出しの間接化も無い。

限界: 型で禁止しているだけなので、`cast`すれば書き換えられる。また、渡した側が後から元の`Map`を書き換えれば、ビューからもその変更が見える（コピーではない）。

### もう1つの選択肢: 必要な操作を関数で受け取る

読む側が使う操作が1つだけなら、Mapの代わりに関数型（例: `Int -> Null<V>`）を受け取ってもよい。関数には「書き換える」操作がそもそも無いので、型で縛る必要がない。データの持ち方（Map・配列・旧木から都度計算する、など）を渡す側が自由に選べる。テストでは、呼ばれた回数を数える関数を渡せる。

代償は、呼び出しが関数を経由すること（`inline`にできない）と、「`exists`も欲しい」といった操作が増えたときに引数の型を変えることになる点。

## 具体例

`streamBodyHints`を受け取るLexerの場合:

| 方法 | Lexer側の型 | 書き換えの禁止 |
|---|---|---|
| そのまま | `Map<Int, StreamBodyHint>` | 約束だけ |
| ビュー | `@:forward(get)`の`abstract`で包んだMap | 型で禁止 |
| 関数 | `Int -> Null<StreamBodyHint>` | そもそも書き換える操作が無い |

## このプロジェクトでの使われ方

- パーサ詳細設計0章: `T | null`・`x?: T`を`Null<T>`・`?x:T`に読み替える。`ReadonlyMap`もこの節の方法で表す
- パーサ詳細設計2章: `src/`は標準ライブラリのみ
- 詳細設計6.2節: `LexerOptions`と`streamBodyHints`
- `GreenBuilder.finish`: `children.pop()`の結果を`GreenNode`に変換するところで、上の「型推論には`Null`が残る」に当たった

## 関連

- [SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md) — `abstract`の`from`/`to`
- [stream境界キャッシュ（StreamBodyHint）](stream-boundary-cache.md) — `streamBodyHints`を作る側と使う側

## 参考

- Haxe Manual「Abstract」節の Forwarding abstract fields（`@:forward`）
- Haxe 4.3のリリースノート（null合体演算子`??`・安全なナビゲーション`?.`）
- 標準ライブラリ`haxe/ds/ReadOnlyArray.hx`（`Array`に対して同じことをしている）
