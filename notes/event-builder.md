# イベント型ビルダー

パーサが木のオブジェクトを直接組み立てる代わりに、「ノード開始」「トークン」「ノード終了」という**イベント**を順に送り、ビルダーがスタックを使ってGreen木に組み上げる方式。rowanの`GreenNodeBuilder`が代表例。

## なぜ必要か

再帰下降パーサ（文法規則1つにつき関数1つを書き、関数同士が呼び合うパーサ）で素直に木を作ると、各関数が「子を集めた配列を作り、最後にノードを`new`して返す」形になる。

```
parseDictionary():
  children = []
  children.push(expect("<<"))
  while (...) children.push(parseDictEntry())
  children.push(expect(">>"))
  return new GreenNode(Dictionary, children)
```

これは正しい入力だけなら困らないが、エラー回復が入ると苦しくなる。

- **途中で抜ける経路が増える**: 同期トークンで外側に巻き戻るとき（基本5.3節）、未クローズのノードを全部閉じて返さないといけない。各関数が自分の`children`をどこに返すかを例外経路ごとに書くことになる
- **関数の返り値の型がばらける**: 「ノードを返す」「トークンを返す」「何も返さない（missing）」が混ざる
- **「どのノードの子か」をパーサが管理する**: ErrorNodeで包む・missing tokenを差し込む、といった操作のたびに配列を受け渡す

イベント型にすると、パーサは**「今どこにいるか」を宣言するだけ**になる。子をどこに積むかはビルダーが知っている。パーサ関数は`Void`を返せばよく、回復の経路でも「`missingToken`を送って`finishNode`する」だけで木が整う。

もう1つの利点は、**木の表現とパーサが分離**されること。Greenの型を変えても（例: 将来のSoA表現。統括設計の性能予算の節）、パーサはイベントを送るだけなので影響を受けない。

## どういう仕組みか

ビルダーは2本のスタックを持つ。

- `children`: 完成した要素（GreenNode／GreenToken）を平らに積んだ配列
- `parents`: 開いているノードの`(kind, そのノードの子がchildrenのどこから始まるか)`

各イベントでやることは次のとおり。

| イベント | 動作 |
|---|---|
| `startNode(kind)` | `parents`に`(kind, children.length)`を積む。まだ何も作らない |
| `token(...)` | GreenTokenを作って`children`に積む |
| `missingToken(kind)` | 幅0・`MISSING`フラグのGreenTokenを`children`に積む |
| `finishNode()` | `parents`から1つ降ろし、`children`の「開始位置〜末尾」を切り取って子にし、GreenNodeを作る（ここで`fullLength`を計算して凍結）。できたノードを`children`に積む |
| `finish()` | 開いているノードが残っておらず、`children`にrootが1つだけあることを確かめて返す |

ポイントは、**ノードは`finishNode`の時点で初めて作られる**こと。Green木は不変なので、子が全部そろうまでノードを作れない。だから「開いている間」は`parents`に開始位置だけ覚えておく。

### 「平らな1本の配列」でよい理由

`children`は開いているノードごとに配列を分けず、1本の配列に全部を積む。これでよいのは、ノードが**入れ子にしかならない**（交差しない）からである。いちばん内側で開いているノードの子は、必ず`children`の末尾にまとまって並ぶ。そのため`finishNode`は「末尾から何個か」を取り出すだけで済む。何個取り出すかを知るために、`parents`には`startNode`の時点の`children.length`（開始位置）を覚えておく。

```
children = [ <<, /A, 1 ]
                 ↑ Entryの開始位置=1
finishNode: children[1..]（/A と 1）を取り出してEntryにし、末尾に戻す
children = [ <<, Entry ]
```

配列の末尾から切り取って取り出す操作は、Haxeなら`Array.splice(pos, len)`（取り除いた要素を返す）1回で書ける。

### 呼び出し順の誤りは例外にする

次のような呼び出しは、壊れたPDFからは起こらず、パーサのバグでしか起こらない。そのため例外にする（統括設計4章 原則1「契約違反は例外で止めてよい」）。

- 開いているノードが無いのに`finishNode`を呼ぶ
- `finish`の時点で、開いたままのノードが残っている
- `finish`の時点で、`children`にノードが1つだけ残っていない（0個、2個以上、トークンだけ）

壊れたPDFで起こり得ること（`>>`が無い、など）は、パーサが`missingToken`を送って処理する。ビルダーのほうで黙って閉じて補正することはしない。

## 具体例

```
<< /A 1 >>
```

パーサが送るイベントと、そのときのスタック（`[...]`は`children`、`{...}`は`parents`）:

```
startNode(Dictionary)      children=[]                       parents={Dict@0}
token(LeftDoubleAngle)     children=[<<]                     parents={Dict@0}
startNode(DictEntry)       children=[<<]                     parents={Dict@0, Entry@1}
token(Name, ws1)           children=[<<, /A]                 parents={Dict@0, Entry@1}
token(Integer, ws1)        children=[<<, /A, 1]              parents={Dict@0, Entry@1}
finishNode()               children=[<<, Entry(/A 1)]        parents={Dict@0}
                             ↑ children[1..]を切り取ってEntryにした（fullLength=3+2=5）
token(RightDoubleAngle,ws1) children=[<<, Entry, >>]         parents={Dict@0}
finishNode()               children=[Dict(<< Entry >>)]      parents={}
                             ↑ fullLength=2+5+3=10
```

`>>`が来ないままEOFになった場合、パーサは`token(RightDoubleAngle)`の代わりに`missingToken(RightDoubleAngle)`を送って`finishNode()`するだけでよい。木の形は正しい入力と同じで、幅0のトークンが1つ入るので幅不変条件も崩れない（基本5.3節、詳細7.3節）。

## パイプラインのどこにいるか

ビルダーは`RawToken`を見ない。トークンは4段を通る（パーサ詳細設計6.2節・6.3節・7.1節）。

```
Lexer        → RawToken    {kind, flags, start, end}        絶対位置。トリビアも1トークンとして出る
TokenSource  → CookedToken {kind, flags, trivia, textLength} トリビアを次の実トークンに吸着し、長さに直す
Parser       → イベント    startNode / token / missingToken / finishNode   構造（どこからどこまでがDictか）を決める
GreenBuilder → GreenNode / GreenToken
```

- `GreenTrivia`はTokenSourceが作る。`GreenToken`は`token`イベントで、`GreenNode`は`finishNode`でビルダーが作る
- `GreenNode`はトークンから作られるのではない。パーサが「ここからここまでが1つのノード」と宣言したときに作られる
- ビルダーが受け取るのは長さだけで、`RawToken`の絶対位置（`start`/`end`）は受け取らない。Greenは位置を持たない（基本5.1節）。また`syntax/`は`lex/`に依存しない（詳細4.1節・2章の依存の向き）

## 設計上の判断ポイント

- **イベントの釣り合いが崩れたら**: `startNode`と`finishNode`の数が合わないのは、入力が壊れているせいではなく**パーサのバグ**である。壊れた入力で例外を投げない（error-tolerant）要件とは別の話なので、どう扱うか（例外・assert・黙って閉じる）を決めておく。rowanはpanicする
- **後から包む（checkpoint）**: rowanには`checkpoint()`と`start_node_at(checkpoint, kind)`があり、「すでに積んだ子を、後からノードで包む」ことができる（`1 0 R`を読んでから`Reference`だと気づく、など）。このプロジェクトでは`TokenSource.atReference()`等の先読みで先に判断するので（詳細7.1節）、設計のシグネチャには入っていない
- **イベント列を一度ためる方式**: Kladovのチュートリアルやrust-analyzer本体は、パーサが`Open/Close/Advance`のイベントを配列にためてから、別の段階で木にする。パーサとビルダーの間にもう1段挟む分、checkpointのような「後から包む」が配列の書き換えで書ける。このプロジェクトは直接ビルダーに送る（rowanの`GreenNodeBuilder`と同じ）

## 直接構築する方式との比較（Roslyn）

Green/Red木を始めたRoslyn（C#）は、イベント型ではない。各parse関数がGreenノードを**直接作って返す**（`ParseIfStatement`が`_syntaxFactory.IfStatement(ifKeyword, openParen, ...)`を返す、など）。それでも回るのは、木の性質がrowanと違うためである。

| | Roslyn | rowan・このプロジェクト |
|---|---|---|
| ノードの形 | **型付き**。種類ごとに決まったスロットを持つ（`IfStatementSyntax`なら`IfKeyword`・`OpenParenToken`…）。クラスは`Syntax.xml`から生成 | **一様**。どの種類も`kind`＋子の配列 |
| 欠けたトークン | スロットに幅0のmissing tokenを入れる（`EatToken`が作る） | `missingToken`イベント |
| 読み飛ばしたトークン | 隣のトークンの**トリビア**（`SkippedTokensTrivia`）にする。ノードの形は崩さない | `ErrorNode`で包む（基本5.3節） |
| インクリメンタル再パース | パーサが旧木のノードを丸ごと「子」として受け取れる（`Blender`） | オブジェクト単位で差し替え（基本5.5節） |

型付きの木では「どの位置に何が入るか」がノードの型で決まっているので、parse関数がスロットを順に埋めて返すのが自然である。読み飛ばしもトリビアに逃がすので、子の並びが予測できない状況が起きにくい。一方、一様な木で「何個の子がどう並ぶか」が入力次第で変わる（ErrorNodeが挟まる、回復で途中で閉じる）なら、イベント型のほうが書きやすい。

なお、TypeScriptコンパイラも直接構築だが、ノードは可変で絶対位置を持つ（`finishNode(node, pos)`）ので、Green木ではない。

## このプロジェクトでの使われ方

- シグネチャ: パーサ詳細設計4.2節（`startNode`/`finishNode`/`token`/`missingToken`/`finish`）。WBS M1-5
- パーサ側の使い方: 詳細7.1節（`Parser`が`builder`を持つ）、7.3節（missing tokenはすべて`builder.missingToken`を通す）
- 幅不変条件とトリビア: 基本4.4節

## 参考

- rowanのソース `src/green/builder.rs`: `GreenNodeBuilder`。`parents`と`children`の2本のスタックで、このノートの説明とほぼ同じ形。短い
- Aleksey Kladov「Resilient LL Parsing Tutorial」（2023年）: イベント列をためる方式と、エラー回復の組み合わせ
- rust-analyzer `crates/parser/src/event.rs`: イベント列方式の実例（`forward_parent`で後から包む仕組みを持つ）
- Roslyn `src/Compilers/CSharp/Portable/Parser/LanguageParser.cs`（直接構築。`EatToken`でmissing tokenを作るところ）、`SyntaxParser.cs`（読み飛ばしをトリビアにする`AddTrailingSkippedSyntax`）、`Blender.cs`（再パースで旧ノードを再利用する仕組み）

## 関連ノート

- [Green/Red木](green-red-tree.md)
- [SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md)
