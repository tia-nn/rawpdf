# Green/Red木

構文木を2層に分ける設計。**Green木**は不変で、位置を持たず、部分木を共有できる「データ本体」。**Red木**はGreen木の上に、親へのポインタと絶対位置を後付けする「軽量なビュー」。Roslyn（C#）で生まれ、rust-analyzer（rowan）が広めた。

## なぜ必要か

エディタ向けのパーサの木には、次の要求が同時にかかる。

1. **キー入力のたびに作り直すので、変わっていない部分は使い回したい**（インクリメンタル再パース）
2. **木をたどるときは、親へのリンクや絶対位置が欲しい**（「カーソル位置のトークンはどれか」「このトークンを含む辞書はどれか」）

1つの木で両方を満たそうとすると、ぶつかる。

- ノードが**親へのポインタ**を持つと、部分木を別の親に付け替えられない（共有できない）
- ノードが**絶対オフセット**を持つと、ファイル先頭で1バイト挿入しただけで、後ろの全ノードの値が変わる。全部作り直し（O(n)）になる

そこで「共有したい情報」と「たどるときに欲しい情報」を別の層に分ける。

| | Green | Red |
|---|---|---|
| 持つもの | 種類（kind）、**長さ**、子 | Greenへの参照、**親**、**絶対位置** |
| 持たないもの | 親、絶対位置、テキスト（このプロジェクトでは） | — |
| 不変か | 不変（作ったら変えない） | 必要なときに作って捨てる |
| 共有 | 同じ部分木を新旧の木で共有できる | しない |

名前に意味はなく、Roslynチームがホワイトボードで使ったペンの色が由来である。

## どういう仕組みか

### Green: 長さだけを持つ不変の木

Greenのノードは、自分の子と長さ（`fullLength`＝子の長さの合計）だけを持つ。自分がファイルのどこにあるかは知らない。だから、同じGreenノードは「どの位置にあっても」そのまま使える。

編集したら、**変わった箇所から根までの経路だけ**新しいGreenノードを作る。兄弟の部分木は古いものを参照ごと再利用する（パスコピー。M5-5）。

### Red: 位置と親を後から計算するビュー

Redノードは「Greenノード＋親のRedノード＋自分の絶対開始位置」の組。根のRedは位置0から始まる。子のRedを作るときは、前にいる兄弟の`fullLength`を足して子の位置を出す。

Redは**たどったときに作る**（遅延生成）。誰も見ない部分のRedは作られない。

### トリビア

空白やコメント（トリビア）も、ロスレスな木（元のバイト列を完全に復元できる木）では捨てられない。このプロジェクトでは、トリビアを**直後のトークンの`leadingTrivia`**として持たせる（基本4.4節）。そのため、トークンには2つの開始位置がある。

- `fullStart`: トリビア込みの開始。幅の計算や再パースで使う
- `start`: トークン本体の開始。診断やエディタの表示で使う

## 具体例

```
<< /A 1 >>
```

（`<<`と`/A`の間、`/A`と`1`の間、`1`と`>>`の間に空白が1つずつ。合計10バイト）

Green木（長さだけ。`ws`は前のトリビア）:

```
Dictionary            fullLength=10
├─ LeftDoubleAngle    "<<"           text=2           full=2
├─ DictEntry          fullLength=6
│  ├─ Name            ws(1) "/A"     text=2  trivia=1 full=3
│  └─ Integer         ws(1) "1"      text=1  trivia=1 full=2
└─ RightDoubleAngle   ws(1) ">>"     text=2  trivia=1 full=3
```

これをRedでたどると、位置は累積で決まる。

```
Dictionary         fullStart=0
  LeftDoubleAngle  fullStart=0  start=0
  DictEntry        fullStart=2
    Name           fullStart=2  start=3   ← 0 + 2（<<の長さ）、本体はトリビア1つ分後ろ
    Integer        fullStart=5  start=6   ← 2 + 3（Nameのfull）
  RightDoubleAngle fullStart=7  start=8   ← 2 + 5（DictEntryのfull）
```

ここで先頭に1バイト挿入しても、`DictEntry`のGreenは長さも中身も変わらないので、新しい木でもそのまま使える。変わるのはRedが計算する位置だけで、Redは作り直すのが前提のビューなので問題にならない。

## このプロジェクトでの使われ方

- 方針と、rowanを使わない理由: パーサ基本設計5.1節。rowanはトークンのテキストをUTF-8文字列で持つため、PDFのバイナリを扱えない。このプロジェクトのGreenは**テキストを持たず長さだけ**を持ち、中身は元の`Bytes`から絶対位置で切り出す
- Green層の型（`GreenTrivia`/`GreenToken`/`GreenNode`）とイベント型ビルダー: 詳細設計4章（WBS M1-5）
- Red層のAPI（`fullStart`/`start`、`coveringElement`等）: 詳細設計5章（WBS M1-7）
- トリビアの付与規則と幅不変条件: 基本4.4節（WBS M1-6）
- 部分木の差し替え（パスコピー）: 基本5.5節、詳細8章（WBS M5-5）
- `SyntaxKind`はGreen・Redのどちらでも`kind`として使う: [SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md)

## 参考

- Eric Lippert「Persistence, Facades and Roslyn's Red-Green Trees」（ブログ Fabulous Adventures in Coding、2012年）: 名前の由来と、なぜ2層にするかの原典。短い
- Microsoft Learn「Work with syntax」（.NET Compiler Platform SDK）: Roslynのトークン・トリビア・`Span`と`FullSpan`の区別。このプロジェクトの`start`/`fullStart`と同じ考え方
- rust-analyzerの`syntax.md`（リポジトリのコントリビュータ向けドキュメント）: rowanの設計を、小さな例と擬似コードで説明している。このプロジェクトの設計にいちばん近い
- rowanのソース: `src/green/node.rs`・`src/green/builder.rs`（Green層とイベント型ビルダー）、`src/cursor.rs`（Red層。rowanでは「cursor」と呼ぶ）
- Aleksey Kladov「Resilient LL Parsing Tutorial」（2023年）: イベント型ビルダーとエラー回復を組み合わせて、小さな言語のパーサを書くチュートリアル。M2以降で役に立つ

## 関連ノート

- [SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md)
