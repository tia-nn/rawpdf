# Haxeのイテレータ

Haxeの`for (x in e)`は、`e`が`hasNext()`と`next()`を持つ`Iterator<T>`か、`iterator()`を持つ`Iterable<T>`なら回せる。JSやC#の`yield`（ジェネレータ）は無いので、遅延して値を出すイテレータは、状態を持つ小さなクラスとして手で書く。

## なぜ必要か

木の子を返すAPIは、「配列を返す」か「イテレータを返す」かを選ぶことになる。配列は作ってしまえば何度でも・何番目でも読めるが、要素を全部作ってから返す。イテレータは1つずつ作って返すので、途中で止めれば残りは作らない。どちらを返すかは、呼び出し側との約束（API）になる。

## どういう仕組みか

```haxe
typedef Iterator<T> = { function hasNext():Bool; function next():T; }
typedef Iterable<T> = { function iterator():Iterator<T>; }
```

どちらも構造型なので、この形のメソッドを持つ値なら何でも`for`で回せる。

- `Array<T>`は`Iterable<T>`（`iterator()`を持つ）。`arr.iterator()`で`Iterator<T>`も取れる
- `Iterator<T>`は**1回しか回せない**。もう一度回すには、作り直す
- `yield`が無いので、遅延するイテレータは「次にどこを返すか」をフィールドに持つクラスにする（擬似コード）:

```
class ChildIter:
  index, pos を持つ
  hasNext(): index < 子の数
  next():    今のindexの子を包んで返し、pos と index を進める
```

### 返り値の型と、中の作り方は分けられる

返り値の型を`Iterator<T>`にしておけば、中で配列を作って`arr.iterator()`を返してもよい。呼び出し側は`for`で回すことしかできないので、後から本当に遅延するクラスに差し替えても呼び出し側は壊れない。逆に返り値を`Array<T>`にすると、呼び出し側が`length`や`[i]`を使い始めるので、後から`Iterator`に変えると壊れる。**型は制約の強い方（`Iterator`）にしておくと、中身を後から変える自由が残る。**

## 具体例

`Document`の子が数千個あり、最初の`XrefSection`だけ欲しい場合:

- 配列を返す`children()`: 数千個のRedノードと配列を作ってから、先頭から探す
- 遅延する`children()`: 見つかった所で`for`を抜ければ、それより後ろのRedノードは作られない

子が数個のノードなら、どちらでも差は無い。

## このプロジェクトでの使われ方

- `IterableIterator<T>`→`Iterator<T>`の読み替え: パーサ詳細設計0章
- Red層の`children()`・`childNodes()`: パーサ詳細設計5章（WBS M1-7）

## 関連ノート

- [Green/Red木](green-red-tree.md)
- [Haxeの`Array`と`haxe.ds.Vector`](haxe-array-and-vector.md)
