# Haxeの`Array`と`haxe.ds.Vector`

`Vector`は長さ固定の配列。静的ターゲット（C++・HashLink・JVM）ではネイティブの固定長配列になって速いが、JSターゲットではただのJSの`Array`になる。Nodeで動かすこのプロジェクトでは、速さで選ぶ理由はほとんど無い。

## なぜ気になるか

Green木からRed木を作るときなど、「長さが分かっている配列を、要素ごとに変換して別の配列にする」処理がよく出てくる。作り方は次の3通りある。

- 空の`Array`に`push`していく
- `arr.map(f)`
- `new Vector(arr.length)`を作ってインデックスで代入する

## どういう仕組みか（Haxe 4.3.7、JSターゲット）

標準ライブラリ（`std/haxe/ds/Vector.hx`・`std/js/_std/Array.hx`）を読むと、出力されるJSは次のようになる。

| 書き方 | 出力されるJS |
|---|---|
| `[]`＋`push` | `[]`に`push`。足りなくなるたびに内部の領域を広げる |
| `arr.map(f)` | `new Array(n)`を作り、`result[i] = f(this[i])`で埋める（`inline`で展開される） |
| `new Vector(n)` | `new Array(n)` |
| `vector.toArray()` | `slice(0)`（**コピーが起きる**） |

つまりJSでは、`map`と`Vector`は**同じコード**になる。違いがあるのは`push`の方式だけ。

V8（Nodeのエンジン）での一般的な傾向は次のとおり。ただし、どちらが速いかは配列の長さやエンジンの版で変わるので、気になったらベンチマークで確かめる。

- `new Array(n)`は、穴あき（holey）の配列として作られる。全部埋めても穴あきの扱いのままで、要素を読むときにわずかな検査が増える
- `push`は穴の無い（packed）配列のまま育つ。その代わり、長くなると途中で領域の確保とコピーが起きる
- 子が数個のノードではどちらでも差は測れないほど小さい。差が出得るのは、子が数千個ある`Document`直下のような場合だけ

## 選び方

1. **そもそも配列を作らずに済まないか**を先に考える。たとえば詳細設計5章の`children()`は`Iterator`を返すので、変換した配列を持たなくても、Greenの子を1つずつRedに包んで返せばよい（遅延生成）
2. 配列が要るなら、`map`か`push`の`Array`にする。プロジェクトの他の場所が`Array`と`ReadOnlyArray`で統一されているため、型をそろえられる。`Vector`にすると、`ReadOnlyArray`を受ける所へ渡すのに`toArray()`のコピーが要る
3. 速さが問題になるかどうかは、勘ではなくベンチマークで決める（統括設計5章の性能予算、ベンチマークはNodeターゲットで計測）

## 具体例

Greenノードの子3つ（`<<`・`DictEntry`・`>>`）をRedに変換するなら、どの方式でも長さ3の配列が1つできるだけで、差は誤差の範囲。`children()`を`Iterator`にすれば配列は1つも作らない。

## このプロジェクトでの使われ方

- 型の読み替え（`readonly T[]`→`ReadOnlyArray<T>`、`IterableIterator<T>`→`Iterator<T>`）: パーサ詳細設計0章
- Red層の`children()`: パーサ詳細設計5章
- 性能予算とベンチマーク: 統括設計4章・5章

## 参考

- Haxe標準ライブラリ `std/haxe/ds/Vector.hx`（`new`・`toArray`のターゲット別の実装）、`std/js/_std/Array.hx`（`map`）
- V8ブログ「Elements kinds in V8」（packedとholeyの区別）

## 関連ノート

- [Green/Red木](green-red-tree.md)
- [Haxeの`inline`](haxe-inline.md)
