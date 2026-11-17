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

## 関連

- [SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md) — `abstract`の`from`/`to`
- [stream境界キャッシュ（StreamBodyHint）](stream-boundary-cache.md) — `streamBodyHints`を作る側と使う側

## 参考

- Haxe Manual「Abstract」節の Forwarding abstract fields（`@:forward`）
- Haxe 4.3のリリースノート（null合体演算子`??`・安全なナビゲーション`?.`）
- 標準ライブラリ`haxe/ds/ReadOnlyArray.hx`（`Array`に対して同じことをしている）
