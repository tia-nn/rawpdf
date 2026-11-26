package rawpdf.cst.syntax;

import haxe.ds.ReadOnlyArray;
import haxe.io.Bytes;
import rawpdf.cst.syntax.GreenNode.GreenNodeChild;
import rawpdf.cst.syntax.SyntaxNode.SyntaxNodeChild;
import rawpdf.cst.syntax.SyntaxToken.SyntaxTrivia;
import utest.Assert;

/** 期待するトークン1つ。`flags`を省略すると`NONE`を期待する。`parents`は、直接の親から根までの`kind`。 */
private typedef ExpectedToken = {
	final kind:SyntaxKind;
	final fullStart:Int;
	final ?flags:TokenFlags;
	final parents:Array<SyntaxKind>;
}

/** 木の中の要素を指す。`path`は、根から`children()`をたどるときの添字の列（空なら根）。 */
private typedef Target = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final tree:SyntaxTree;
	final path:Array<Int>;
}

/** ノードの位置を確かめるケース。 */
private typedef NodePosCase = Target & {
	final fullStart:Int;
	final start:Int;
	final end:Int;
}

/** トークンの位置を確かめるケース。 */
private typedef TokenPosCase = Target & {
	final fullStart:Int;
	final start:Int;
	final end:Int;
}

/** `leadingTrivia()`の結果を確かめるケース。`trivia`は期待する列で、`Assert.same`で比べる。 */
private typedef TriviaCase = Target & {
	final trivia:Array<SyntaxTrivia>;
}

/** `children()`・`childNodes()`が返す列を確かめるケース。要素は`n`・`t`で作る要約の文字列で比べる。 */
private typedef ChildrenCase = Target & {
	final children:Array<String>;
}

/** `firstToken()`・`lastToken()`の結果を確かめるケース。`expected`が`null`なら`null`を期待する。 */
private typedef TokenSearchCase = Target & {
	final expected:Null<ExpectedToken>;
}

/** `coveringElement()`で期待する結果。 */
private enum Covering {
	IsToken(token:ExpectedToken);
	IsNode(kind:SyntaxKind, fullStart:Int);
	Throws;
}

/** `coveringElement(offset)`の結果を確かめるケース。 */
private typedef CoverCase = Target & {
	final offset:Int;
	final expected:Covering;
}

/** `byteSpan()`が返す範囲を確かめるケース。`text`は範囲の中身を文字列にしたもの。 */
private typedef SpanCase = Target & {
	final text:String;
	final start:Int;
	final length:Int;
}

/**
	`SyntaxTree`・`SyntaxNode`・`SyntaxToken`のテスト。
	根拠は各メンバーのdocコメントと、`ByteSpan`のクラスのdocコメント。

	位置の期待値は、次の2つから導く。
	- `SyntaxNode`のクラスのdocコメント「位置はすべて、ファイル先頭からのバイトオフセット」。木はファイル全体から作るので、根の`fullStart`は0
	- `GreenNode.new`・`GreenToken.new`のdocコメント（`fullLength`は子・トリビアと本体の長さの合計）。要素は前から隙間なく並ぶので、
	  子の`fullStart`は、親の`fullStart`に前の兄弟の`fullLength`を足したもの

	木は下の`dictTree`などで組む。どの木も、根の`GreenNode`の`fullLength`が入力のバイト数と等しくなるように組んでいる。
**/
class SyntaxNodeTest extends utest.Test {
	// 木を短く組むための補助
	static inline function ws(length:Int) {
		return new GreenTrivia(Whitespace, length);
	}

	static inline function comment(length:Int) {
		return new GreenTrivia(Comment, length);
	}

	static function tok(kind:SyntaxKind, textLength:Int, ?trivia:ReadOnlyArray<GreenTrivia>, ?flags:TokenFlags) {
		return new GreenToken(kind, flags ?? TokenFlags.NONE, trivia ?? [], textLength);
	}

	static inline function node(kind:SyntaxKind, children:ReadOnlyArray<GreenNodeChild>) {
		return new GreenNode(kind, children);
	}

	/**
		`<< /A 1 >> %x\n`（14バイト）。
		```
		Document              0..14
		├─ Dictionary         0..10
		│  ├─ <<              fullStart 0, start 0
		│  ├─ DictEntry       fullStart 2
		│  │  ├─ Name   ws(1) fullStart 2, start 3
		│  │  └─ Integer ws(1) fullStart 5, start 6
		│  └─ >>        ws(1) fullStart 7, start 8
		├─ Array（子なし）     fullStart 10
		└─ EndOfFile          fullStart 10, start 14（トリビア: 空白1・コメント2・改行1）
		```
	**/
	static function dictTree() {
		return new SyntaxTree(Bytes.ofString("<< /A 1 >> %x\n"), node(Document, [
			node(Dictionary, [
				tok(LeftDoubleAngle, 2),
				node(DictEntry, [tok(Name, 2, [ws(1)]), tok(Integer, 1, [ws(1)])]),
				tok(RightDoubleAngle, 2, [ws(1)]),
			]),
			node(SyntaxKind.Array, []),
			tok(EndOfFile, 0, [ws(1), comment(2), ws(1)]),
		]));
	}

	/** `<< /A 1`（7バイト）。閉じの`>>`が無く、幅0のmissing tokenで閉じた木。`EndOfFile`はトリビアを持たない。 */
	static function missingTree() {
		return new SyntaxTree(Bytes.ofString("<< /A 1"), node(Document, [
			node(Dictionary, [
				tok(LeftDoubleAngle, 2),
				node(DictEntry, [tok(Name, 2, [ws(1)]), tok(Integer, 1, [ws(1)])]),
				tok(RightDoubleAngle, 0, [], TokenFlags.MISSING),
			]),
			tok(EndOfFile, 0),
		]));
	}

	/** 空のファイル。根は子を持たない。 */
	static function emptyTree() {
		return new SyntaxTree(Bytes.alloc(0), node(Document, []));
	}

	/** `1`（1バイト）。トークンが3段のノードの下にある木（`Document > Segment > IndirectObject > Integer`）。 */
	static function deepTree() {
		return new SyntaxTree(Bytes.ofString("1"), node(Document, [node(Segment, [node(IndirectObject, [tok(Integer, 1)])])]));
	}

	/**
		` 1`（2バイト）。唯一のトークンの前後に、トークンを持たないノードがある木。
		先頭の`Segment`は、子の無い`Array`だけを子に持つ（トークンを持たないノードだけを子に持つノード）。
		```
		Document
		├─ Segment            fullStart 0
		│  └─ Array（子なし）  fullStart 0
		├─ Integer      ws(1) fullStart 0, start 1
		└─ Array（子なし）     fullStart 2
		```
	**/
	static function edgeEmptyTree() {
		return new SyntaxTree(Bytes.ofString(" 1"), node(Document, [
			node(Segment, [node(SyntaxKind.Array, [])]),
			tok(Integer, 1, [ws(1)]),
			node(SyntaxKind.Array, []),
		]));
	}

	// 期待値を短く書くための補助

	/** `children()`・`childNodes()`の要素の要約（ノード）。 */
	static function n(kind:SyntaxKind, fullStart:Int) {
		return 'Node $kind @$fullStart';
	}

	/** `children()`の要素の要約（トークン）。 */
	static function t(kind:SyntaxKind, fullStart:Int) {
		return 'Token $kind @$fullStart';
	}

	static function summary(c:SyntaxNodeChild) {
		return switch c {
			case Node(node): n(node.kind, node.fullStart);
			case Token(token): t(token.kind, token.fullStart);
		}
	}

	// 木をたどるための補助

	static function childAt(parent:SyntaxNode, i:Int):SyntaxNodeChild {
		final children = [for (c in parent.children()) c];
		if (i < 0 || children.length <= i) {
			throw 'child $i does not exist (${children.length} children)';
		}
		return children[i];
	}

	static function nodeAt(target:Target):SyntaxNode {
		var current = target.tree.root;
		for (i in target.path) {
			switch childAt(current, i) {
				case Node(child):
					current = child;
				case Token(_):
					throw '${target.name}: path ${target.path} reaches a token';
			}
		}
		return current;
	}

	static function tokenAt(target:Target):SyntaxToken {
		final parent = nodeAt({name: target.name, tree: target.tree, path: target.path.slice(0, target.path.length - 1)});
		return switch childAt(parent, target.path[target.path.length - 1]) {
			case Token(token): token;
			case Node(_): throw '${target.name}: path ${target.path} reaches a node';
		}
	}

	// 比較

	static function checkToken(name:String, expected:ExpectedToken, actual:Null<SyntaxToken>) {
		if (actual == null) {
			Assert.fail('$name: expected a token, but was null');
			return;
		}
		Assert.equals(expected.kind, actual.kind, '$name: kind');
		Assert.equals(expected.fullStart, actual.fullStart, '$name: fullStart');
		Assert.equals(expected.flags ?? TokenFlags.NONE, actual.flags, '$name: flags');

		final parents:Array<SyntaxKind> = [];
		var p:Null<SyntaxNode> = actual.parent;
		while (p != null) {
			parents.push(p.kind);
			p = p.parent;
		}
		Assert.same(expected.parents, parents, '$name: parents');
	}

	static final NODE_POSITIONS_CASES:Array<NodePosCase> = [
		{
			name: "根（<< /A 1 >> %x\\n） → 0, 0, 14（endは末尾のトリビアの後ろ）",
			tree: dictTree(),
			path: [],
			fullStart: 0,
			start: 0,
			end: 14
		},
		{
			name: "Dictionary → 0, 0, 10",
			tree: dictTree(),
			path: [0],
			fullStart: 0,
			start: 0,
			end: 10
		},
		{
			name: "先頭のNameが空白を持つDictEntry → fullStart 2, start 3, end 7",
			tree: dictTree(),
			path: [0, 1],
			fullStart: 2,
			start: 3,
			end: 7
		},
		{
			name: "子の無いArray（Dictionaryの直後） → 10, 10, 10（トークンが無いのでfullStart）",
			tree: dictTree(),
			path: [1],
			fullStart: 10,
			start: 10,
			end: 10
		},
		{
			name: "空のファイルの根 → 0, 0, 0",
			tree: emptyTree(),
			path: [],
			fullStart: 0,
			start: 0,
			end: 0
		},
		{
			name: "末尾がmissing tokenのDictionary（<< /A 1） → 0, 0, 7",
			tree: missingTree(),
			path: [0],
			fullStart: 0,
			start: 0,
			end: 7
		},
		{
			name: "前後にトークンの無いノードを持つ根（ 1） → 0, 1, 2",
			tree: edgeEmptyTree(),
			path: [],
			fullStart: 0,
			start: 1,
			end: 2
		},
		{
			name: "トークンの無いノードだけを子に持つSegment → 0, 0, 0",
			tree: edgeEmptyTree(),
			path: [0],
			fullStart: 0,
			start: 0,
			end: 0
		},
	];

	/**
		[SyntaxNode.fullStart・start・endのdocコメント] `start`は`firstToken()`の`start`、`end`は`lastToken()`の`end`。
		部分木にトークンが無ければどちらも`fullStart`。`end`は常に`fullStart + green.fullLength`。
		観点:
		-         正常: 根・入れ子のノード、先頭の子がトリビアを持つノード（`start`がずれる）
		-         境目: 該当なし（字句の切れ目を持たない）
		-     範囲の端: 末尾のトリビアを持つ`EndOfFile`で終わる根、末尾がmissing token（幅0）、前後にトークンの無いノードがある根
		-     空・最小: 空のファイルの根、子の無いノード、トークンの無いノードだけを子に持つノード
		- 不正なバイト: 該当なし（位置だけを見る。中身はtestByteSpanで見る）
		-       大きさ: 該当なし（深さはパーサのネストの上限で抑えられる）
		-   仕様の細則: `start`と`fullStart`の違い（leading trivia）
	**/
	function testNodePositions() {
		for (c in NODE_POSITIONS_CASES) {
			final actual = nodeAt(c);
			Assert.equals(c.fullStart, actual.fullStart, '${c.name}: fullStart');
			Assert.equals(c.start, actual.start, '${c.name}: start');
			Assert.equals(c.end, actual.end, '${c.name}: end');
		}
	}

	static final TOKEN_POSITIONS_CASES:Array<TokenPosCase> = [
		{
			name: "<<（トリビアなし） → 0, 0, 2",
			tree: dictTree(),
			path: [0, 0],
			fullStart: 0,
			start: 0,
			end: 2
		},
		{
			name: "Name（空白1つの後） → 2, 3, 5",
			tree: dictTree(),
			path: [0, 1, 0],
			fullStart: 2,
			start: 3,
			end: 5
		},
		{
			name: "Integer（空白1つの後） → 5, 6, 7",
			tree: dictTree(),
			path: [0, 1, 1],
			fullStart: 5,
			start: 6,
			end: 7
		},
		{
			name: ">>（空白1つの後） → 7, 8, 10",
			tree: dictTree(),
			path: [0, 2],
			fullStart: 7,
			start: 8,
			end: 10
		},
		{
			name: "EndOfFile（空白・コメント・改行の後） → 10, 14, 14（本体が幅0なのでend＝start）",
			tree: dictTree(),
			path: [2],
			fullStart: 10,
			start: 14,
			end: 14
		},
		{
			name: "missing token（幅0） → 7, 7, 7",
			tree: missingTree(),
			path: [0, 2],
			fullStart: 7,
			start: 7,
			end: 7
		},
		{
			name: "トリビアの無いEndOfFile → 7, 7, 7",
			tree: missingTree(),
			path: [1],
			fullStart: 7,
			start: 7,
			end: 7
		},
	];

	/**
		[SyntaxToken.fullStart・start・endのdocコメント] `fullStart`はleading trivia込みの開始、`start`はleading triviaの直後。
		`end`は本体の終わり（含まない）で`start + green.textLength`。本体が幅0のトークンでは`start`と等しい。
		観点:
		-         正常: トリビアなし・空白1つのトークン
		-         境目: 該当なし（字句の切れ目を持たない）
		-     範囲の端: トリビアを3つ持つ末尾の`EndOfFile`、幅0のmissing token、トリビアの無い`EndOfFile`
		-     空・最小: `textLength`0のトークン（missing token・`EndOfFile`。`end == start`）
		- 不正なバイト: 該当なし（位置だけを見る）
		-       大きさ: 該当なし
		-   仕様の細則: `end`はトリビアを含まない本体の終わり（`<<`の`end`は次のトークンの`fullStart`と同じ2）
	**/
	function testTokenPositions() {
		for (c in TOKEN_POSITIONS_CASES) {
			final actual = tokenAt(c);
			Assert.equals(c.fullStart, actual.fullStart, '${c.name}: fullStart');
			Assert.equals(c.start, actual.start, '${c.name}: start');
			Assert.equals(c.end, actual.end, '${c.name}: end');
		}
	}

	static final LEADING_TRIVIA_CASES:Array<TriviaCase> = [
		{
			name: "<<（トリビアなし） → 空",
			tree: dictTree(),
			path: [0, 0],
			trivia: []
		},
		{
			name: "Name（空白1つ） → 空白@2（長さ1）",
			tree: dictTree(),
			path: [0, 1, 0],
			trivia: [{kind: Whitespace, start: 2, length: 1}]
		},
		{
			name: "EndOfFile（空白・コメント・改行） → 空白@10・コメント@11・改行@13（前のトリビアの直後から始まる）",
			tree: dictTree(),
			path: [2],
			trivia: [
				{kind: Whitespace, start: 10, length: 1},
				{kind: Comment, start: 11, length: 2},
				{kind: Whitespace, start: 13, length: 1},
			]
		},
		{
			name: "missing token（トリビアなし・幅0） → 空",
			tree: missingTree(),
			path: [0, 2],
			trivia: []
		},
	];

	/**
		[SyntaxToken.leadingTriviaのdocコメント] leading triviaを前から順に、絶対位置を付けて返す。無ければ空。
		最初のトリビアの`start`は`fullStart`で、各トリビアは前のトリビアの直後から始まる。最後のトリビアの直後が`start`。
		種類と長さは、木を組むときに渡した`GreenTrivia`のもの。
		観点:
		-         正常: トリビア1つ
		-         境目: 該当なし（字句の切れ目を持たない）
		-     範囲の端: 複数のトリビア（2つ目以降の`start`が前の直後）、ファイル末尾の`EndOfFile`
		-     空・最小: トリビアなし（空の列）、幅0のmissing token
		- 不正なバイト: 該当なし（位置だけを見る）
		-       大きさ: 該当なし
		-   仕様の細則: 最後のトリビアの直後がトークンの`start`（下で各ケースについて確かめる）
	**/
	function testLeadingTrivia() {
		for (c in LEADING_TRIVIA_CASES) {
			final token = tokenAt(c);
			final actual = [for (t in token.leadingTrivia()) t];
			Assert.same(c.trivia, actual, '${c.name}: leadingTrivia');

			final triviaEnd = if (actual.length == 0) {
				token.fullStart;
			} else {
				final last = actual[actual.length - 1];
				last.start + last.length;
			}
			Assert.equals(token.start, triviaEnd, '${c.name}: the last trivia should end at start');
		}
	}

	/**
		[SyntaxTree.rootのdocコメント] 根の`fullStart`は0、`parent`は`null`。
		[SyntaxTree.bytesのdocコメント] 渡したバイト列を複製せずにそのまま参照する。
		観点: 正常（トークンを持つ木）と空・最小（空のファイル）。他の観点は該当なし（木を作るだけ）。
	**/
	function testTreeRoot() {
		for (c in [
			{name: "<< /A 1 >> %x\\n", tree: dictTree()},
			{name: "空のファイル", tree: emptyTree()}
		]) {
			Assert.equals(0, c.tree.root.fullStart, '${c.name}: root.fullStart');
			Assert.isNull(c.tree.root.parent, '${c.name}: root.parent');
		}

		final bytes = Bytes.ofString("1");
		final tree = new SyntaxTree(bytes, node(Document, [tok(Integer, 1)]));
		Assert.isTrue(tree.bytes == bytes, "bytes should be the given Bytes itself");
	}

	static final CHILDREN_CASES:Array<ChildrenCase> = [
		{
			name: "根 → Dictionary・子の無いArray・EndOfFile（幅0のArrayとEndOfFileはどちらも10）",
			tree: dictTree(),
			path: [],
			children: [n(Dictionary, 0), n(SyntaxKind.Array, 10), t(EndOfFile, 10)]
		},
		{
			name: "Dictionary → <<・DictEntry・>>",
			tree: dictTree(),
			path: [0],
			children: [t(LeftDoubleAngle, 0), n(DictEntry, 2), t(RightDoubleAngle, 7)]
		},
		{
			name: "DictEntry（トークンだけ） → Name・Integer",
			tree: dictTree(),
			path: [0, 1],
			children: [t(Name, 2), t(Integer, 5)]
		},
		{
			name: "子の無いArray → 空",
			tree: dictTree(),
			path: [1],
			children: []
		},
		{
			name: "前後にトークンの無いノードを持つ根 → Segment・Integer・Array",
			tree: edgeEmptyTree(),
			path: [],
			children: [n(Segment, 0), t(Integer, 0), n(SyntaxKind.Array, 2)]
		},
	];

	/**
		[SyntaxNode.childrenのdocコメント] 子（ノードとトークン）を前から順に返す。
		[SyntaxNode.parentのdocコメント] 返った子の`parent`は、`children()`を呼んだノード（`green`が同じ）。
		観点:
		-         正常: ノードとトークンが混ざった子、トークンだけの子
		-         境目: 該当なし（字句の切れ目を持たない）
		-     範囲の端: 同じ位置に並ぶ幅0のノードとトークン（子の無い`Array`と`EndOfFile`）
		-     空・最小: 子の無いノード
		- 不正なバイト: 該当なし
		-       大きさ: 該当なし
		-   仕様の細則: 順番（前から）
	**/
	function testChildren() {
		for (c in CHILDREN_CASES) {
			final parent = nodeAt(c);
			final children = [for (child in parent.children()) child];
			Assert.same(c.children, children.map(summary), '${c.name}: children');
			for (i => child in children) {
				final childParent = switch child {
					case Node(node): node.parent;
					case Token(token): token.parent;
				}
				Assert.isTrue(childParent != null && childParent.green == parent.green, '${c.name}: children[$i].parent');
			}
		}
	}

	static final CHILD_NODES_CASES:Array<ChildrenCase> = [
		{
			name: "根 → Dictionary・子の無いArray（EndOfFileを除く）",
			tree: dictTree(),
			path: [],
			children: [n(Dictionary, 0), n(SyntaxKind.Array, 10)]
		},
		{
			name: "Dictionary → DictEntryだけ",
			tree: dictTree(),
			path: [0],
			children: [n(DictEntry, 2)]
		},
		{
			name: "子がトークンだけのDictEntry → 空",
			tree: dictTree(),
			path: [0, 1],
			children: []
		},
		{
			name: "子の無いArray → 空",
			tree: dictTree(),
			path: [1],
			children: []
		},
		{
			name: "前後にトークンの無いノードを持つ根 → Segment・Array",
			tree: edgeEmptyTree(),
			path: [],
			children: [n(Segment, 0), n(SyntaxKind.Array, 2)]
		},
	];

	/**
		[SyntaxNode.childNodesのdocコメント] 子のうちノードだけを前から順に返す（`children()`からトークンを除いたもの）。
		観点の表はtestChildrenと同じ。加えて、子がトークンだけのノード（→空）。
	**/
	function testChildNodes() {
		for (c in CHILD_NODES_CASES) {
			final parent = nodeAt(c);
			final actual = [for (child in parent.childNodes()) n(child.kind, child.fullStart)];
			Assert.same(c.children, actual, '${c.name}: childNodes');
		}
	}

	static final FIRST_TOKEN_CASES:Array<TokenSearchCase> = [
		{
			name: "根 → <<（親はDictionary）",
			tree: dictTree(),
			path: [],
			expected: {kind: LeftDoubleAngle, fullStart: 0, parents: [Dictionary, Document]}
		},
		{
			name: "DictEntry → Name",
			tree: dictTree(),
			path: [0, 1],
			expected: {kind: Name, fullStart: 2, parents: [DictEntry, Dictionary, Document]}
		},
		{
			name: "3段下のトークン → Integer（親をIndirectObject・Segment・Documentとたどれる）",
			tree: deepTree(),
			path: [],
			expected: {kind: Integer, fullStart: 0, parents: [IndirectObject, Segment, Document]}
		},
		{
			name: "先頭にトークンの無いSegmentがある根 → それを飛ばしてInteger",
			tree: edgeEmptyTree(),
			path: [],
			expected: {kind: Integer, fullStart: 0, parents: [Document]}
		},
		{
			name: "空のファイルの根 → null",
			tree: emptyTree(),
			path: [],
			expected: null
		},
		{
			name: "子の無いArray → null",
			tree: dictTree(),
			path: [1],
			expected: null
		},
		{
			name: "トークンの無いノードだけを子に持つSegment → null",
			tree: edgeEmptyTree(),
			path: [0],
			expected: null
		},
	];

	/**
		[SyntaxNode.firstTokenのdocコメント] 子孫のトークンのうち最初のもの。幅0のトークンも含む。
		返るトークンの`parent`は、そのトークンを直接の子に持つノード。部分木にトークンが無ければ`null`。
		観点:
		-         正常: 根、入れ子のノード
		-         境目: 該当なし（字句の切れ目を持たない）
		-     範囲の端: 先頭にトークンの無いノードがある（飛ばす）、3段下にあるトークン（親を根までたどる）
		-     空・最小: 空のファイルの根、子の無いノード、トークンの無いノードだけを子に持つノード（→`null`）
		- 不正なバイト: 該当なし
		-       大きさ: 該当なし（深さはパーサのネストの上限で抑えられる）
		-   仕様の細則: 返るトークンの`parent`が直接の親であること
	**/
	function testFirstToken() {
		for (c in FIRST_TOKEN_CASES) {
			checkSearch(c, nodeAt(c).firstToken());
		}
	}

	static final LAST_TOKEN_CASES:Array<TokenSearchCase> = [
		{
			name: "根 → EndOfFile（幅0でもトークン）",
			tree: dictTree(),
			path: [],
			expected: {kind: EndOfFile, fullStart: 10, parents: [Document]}
		},
		{
			name: "Dictionary → >>",
			tree: dictTree(),
			path: [0],
			expected: {kind: RightDoubleAngle, fullStart: 7, parents: [Dictionary, Document]}
		},
		{
			name: "DictEntry → Integer",
			tree: dictTree(),
			path: [0, 1],
			expected: {kind: Integer, fullStart: 5, parents: [DictEntry, Dictionary, Document]}
		},
		{
			name: "末尾がmissing tokenのDictionary → missing token（幅0でもトークン）",
			tree: missingTree(),
			path: [0],
			expected: {
				kind: RightDoubleAngle,
				fullStart: 7,
				flags: TokenFlags.MISSING,
				parents: [Dictionary, Document]
			}
		},
		{
			name: "3段下のトークン → Integer（親をIndirectObject・Segment・Documentとたどれる）",
			tree: deepTree(),
			path: [],
			expected: {kind: Integer, fullStart: 0, parents: [IndirectObject, Segment, Document]}
		},
		{
			name: "末尾にトークンの無いArrayがある根 → それを飛ばしてInteger",
			tree: edgeEmptyTree(),
			path: [],
			expected: {kind: Integer, fullStart: 0, parents: [Document]}
		},
		{
			name: "空のファイルの根 → null",
			tree: emptyTree(),
			path: [],
			expected: null
		},
		{
			name: "子の無いArray → null",
			tree: dictTree(),
			path: [1],
			expected: null
		},
		{
			name: "トークンの無いノードだけを子に持つSegment → null",
			tree: edgeEmptyTree(),
			path: [0],
			expected: null
		},
	];

	/**
		[SyntaxNode.lastTokenのdocコメント] 子孫のトークンのうち最後のもの。条件は`firstToken()`と同じ。
		観点の表はtestFirstTokenと同じ。末尾の側は、幅0のトークン（`EndOfFile`・missing token）と、後ろにあるトークンの無いノード。
	**/
	function testLastToken() {
		for (c in LAST_TOKEN_CASES) {
			checkSearch(c, nodeAt(c).lastToken());
		}
	}

	static function checkSearch(c:TokenSearchCase, actual:Null<SyntaxToken>) {
		final expected = c.expected;
		if (expected == null) {
			Assert.isNull(actual, '${c.name}: should be null');
		} else {
			checkToken(c.name, expected, actual);
		}
	}

	// testCoveringElementで使う、期待するトークン
	static final dictLt:ExpectedToken = {kind: LeftDoubleAngle, fullStart: 0, parents: [Dictionary, Document]};
	static final nameTok:ExpectedToken = {kind: Name, fullStart: 2, parents: [DictEntry, Dictionary, Document]};
	static final integerTok:ExpectedToken = {kind: Integer, fullStart: 5, parents: [DictEntry, Dictionary, Document]};
	static final dictGt:ExpectedToken = {kind: RightDoubleAngle, fullStart: 7, parents: [Dictionary, Document]};
	static final eof:ExpectedToken = {kind: EndOfFile, fullStart: 10, parents: [Document]};

	static final COVERING_ELEMENT_CASES:Array<CoverCase> = [
		{
			name: "根・0（<<の先頭） → <<",
			tree: dictTree(),
			path: [],
			offset: 0,
			expected: IsToken(dictLt)
		},
		{
			name: "根・1（<<の中） → <<",
			tree: dictTree(),
			path: [],
			offset: 1,
			expected: IsToken(dictLt)
		},
		{
			name: "根・2（Nameの前の空白） → Name（トリビアを持つトークン）",
			tree: dictTree(),
			path: [],
			offset: 2,
			expected: IsToken(nameTok)
		},
		{
			name: "根・3（Nameの本体の先頭） → Name",
			tree: dictTree(),
			path: [],
			offset: 3,
			expected: IsToken(nameTok)
		},
		{
			name: "根・5（Nameの終わり＝Integerの空白の先頭） → Integer（後ろのトークン）",
			tree: dictTree(),
			path: [],
			offset: 5,
			expected: IsToken(integerTok)
		},
		{
			name: "根・9（>>の中） → >>",
			tree: dictTree(),
			path: [],
			offset: 9,
			expected: IsToken(dictGt)
		},
		{
			name: "根・10（>>の終わり。幅0のArrayも10にある） → EndOfFile（幅0のArrayは飛ばす）",
			tree: dictTree(),
			path: [],
			offset: 10,
			expected: IsToken(eof)
		},
		{
			name: "根・13（EndOfFileのトリビアの改行） → EndOfFile",
			tree: dictTree(),
			path: [],
			offset: 13,
			expected: IsToken(eof)
		},
		{
			name: "根・14（end。ファイル末尾） → lastToken()のEndOfFile",
			tree: dictTree(),
			path: [],
			offset: 14,
			expected: IsToken(eof)
		},
		{
			name: "根・-1（fullStartの手前） → 例外",
			tree: dictTree(),
			path: [],
			offset: -1,
			expected: Throws
		},
		{
			name: "根・15（endの後ろ） → 例外",
			tree: dictTree(),
			path: [],
			offset: 15,
			expected: Throws
		},
		{
			name: "Dictionary・10（end） → lastToken()の>>",
			tree: dictTree(),
			path: [0],
			offset: 10,
			expected: IsToken(dictGt)
		},
		{
			name: "Dictionary・11（endの後ろ） → 例外",
			tree: dictTree(),
			path: [0],
			offset: 11,
			expected: Throws
		},
		{
			name: "DictEntry・2（fullStart） → Name",
			tree: dictTree(),
			path: [0, 1],
			offset: 2,
			expected: IsToken(nameTok)
		},
		{
			name: "DictEntry・1（fullStartの手前） → 例外",
			tree: dictTree(),
			path: [0, 1],
			offset: 1,
			expected: Throws
		},
		{
			name: "子の無いArray・10（fullStart＝end） → Array自身",
			tree: dictTree(),
			path: [1],
			offset: 10,
			expected: IsNode(SyntaxKind.Array, 10)
		},
		{
			name: "空のファイルの根・0 → 根自身",
			tree: emptyTree(),
			path: [],
			offset: 0,
			expected: IsNode(Document, 0)
		},
		{
			name: "missingの木の根・6（Integerの本体） → Integer",
			tree: missingTree(),
			path: [],
			offset: 6,
			expected: IsToken({kind: Integer, fullStart: 5, parents: [DictEntry, Dictionary, Document]})
		},
		{
			name: "missingの木の根・7（end。幅0の>>も7にある） → lastToken()のEndOfFile",
			tree: missingTree(),
			path: [],
			offset: 7,
			expected: IsToken({kind: EndOfFile, fullStart: 7, parents: [Document]})
		},
		{
			name: "missingの木のDictionary・7（end） → lastToken()のmissing token",
			tree: missingTree(),
			path: [0],
			offset: 7,
			expected: IsToken({
				kind: RightDoubleAngle,
				fullStart: 7,
				flags: TokenFlags.MISSING,
				parents: [Dictionary, Document]
			})
		},
	];

	/**
		[SyntaxNode.coveringElementのdocコメント] 各要素はleading trivia込みの半開区間を占める。
		トリビアの中はそのトリビアを持つトークン、境界ちょうどは後ろのトークン。幅0のトークンはどの位置も含まない。
		`byteOffset == end`なら`lastToken()`。部分木にトークンが無ければノード自身。`[fullStart, end]`の外は例外。
		観点:
		-         正常: トークン本体の中・先頭
		-         境目: トークンの境界ちょうど（後ろのトークン）、幅0のノード・トークンと同じ位置（飛ばす）
		-     範囲の端: `end`ちょうど（根・途中のノード・missing tokenで終わるノード）、`fullStart`の手前と`end`の後ろ（例外）
		-     空・最小: 空のファイルの根、子の無いノード（ノード自身）
		- 不正なバイト: 該当なし（位置だけを見る）
		-       大きさ: 該当なし
		-   仕様の細則: トリビアの中の位置（そのトリビアを持つトークン）、返るトークンの`parent`が直接の親
	**/
	function testCoveringElement() {
		for (c in COVERING_ELEMENT_CASES) {
			final target = nodeAt(c);
			switch c.expected {
				case Throws:
					Assert.raises(() -> target.coveringElement(c.offset), haxe.Exception, c.name);
				case IsToken(expected):
					switch target.coveringElement(c.offset) {
						case Token(token): checkToken(c.name, expected, token);
						case Node(node): Assert.fail('${c.name}: expected a token, but was a node (${node.kind})');
					}
				case IsNode(kind, fullStart):
					switch target.coveringElement(c.offset) {
						case Node(node):
							Assert.equals(kind, node.kind, '${c.name}: kind');
							Assert.equals(fullStart, node.fullStart, '${c.name}: fullStart');
							Assert.isTrue(node.green == target.green, '${c.name}: should be the node itself');
						case Token(token):
							Assert.fail('${c.name}: expected a node, but was a token (${token.kind})');
					}
			}
		}
	}

	static final BYTE_SPAN_CASES:Array<SpanCase> = [
		{
			name: "<< → \"<<\"（0から2バイト）",
			tree: dictTree(),
			path: [0, 0],
			text: "<<",
			start: 0,
			length: 2
		},
		{
			name: "Name → \"/A\"（前の空白を含まない）",
			tree: dictTree(),
			path: [0, 1, 0],
			text: "/A",
			start: 3,
			length: 2
		},
		{
			name: "トリビアだけのEndOfFile → 空（14から0バイト）",
			tree: dictTree(),
			path: [2],
			text: "",
			start: 14,
			length: 0
		},
		{
			name: "missing token → 空（7から0バイト）",
			tree: missingTree(),
			path: [0, 2],
			text: "",
			start: 7,
			length: 0
		},
	];

	/**
		[ByteSpanのクラスのdocコメント] `SyntaxToken.byteSpan()`は、トークン本体（トリビアを含まない）の範囲を、元のバイト列をコピーせずに返す。
		範囲の開始は[SyntaxToken.startのdocコメント]、長さはトークン本体の長さ（`GreenToken`の`textLength`）。
		観点:
		-         正常: トリビアなし・空白の後ろのトークン
		-         境目: 該当なし（字句の切れ目を持たない）
		-     範囲の端: ファイル末尾の`EndOfFile`（トリビアだけで本体は空）
		-     空・最小: 幅0のmissing token（空の範囲）
		- 不正なバイト: 該当なし（中身はそのまま見せるだけで解釈しない。`ByteSpanTest`で0x80以上のバイトを見る）
		-       大きさ: 該当なし（コピーしないこと自体はtestByteSpanSourceで見る）
		-   仕様の細則: トリビアを含まないこと
	**/
	function testByteSpan() {
		for (c in BYTE_SPAN_CASES) {
			final span = tokenAt(c).byteSpan();
			Assert.equals(c.start, span.start, '${c.name}: start');
			Assert.equals(c.length, span.length, '${c.name}: length');
			Assert.equals(c.text, span.toBytes().toString(), '${c.name}: text');
		}
	}

	/** [ByteSpanのクラスのdocコメント] 元のバイト列をコピーせずに見せる → `source`は`SyntaxTree.bytes`そのもの。 */
	function testByteSpanSource() {
		final tree = dictTree();
		final span = tokenAt({name: "Name", tree: tree, path: [0, 1, 0]}).byteSpan();
		Assert.isTrue(span.source == tree.bytes, "Name: source should be SyntaxTree.bytes itself");
	}
}
