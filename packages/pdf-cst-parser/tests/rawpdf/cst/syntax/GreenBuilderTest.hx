package rawpdf.cst.syntax;

import haxe.Exception;
import haxe.ds.ReadOnlyArray;
import rawpdf.cst.syntax.GreenNode.NodeChild;
import utest.Assert;

/** イベントを送ったときに例外を投げるかどうかを確かめるケース。`GreenNodeTest`の`ConstructCase`と同じ形。 */
private typedef ThrowCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	/** 新しい`GreenBuilder`にイベントを送る。 */
	final run:GreenBuilder->Void;

	final throws:Bool;
}

/** イベントを送って`finish`で受け取った木が、期待する木と同じ形かを確かめるケース。 */
private typedef TreeCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	/** 新しい`GreenBuilder`にイベントを送る。`finish`は呼ばない（`checkTrees`が呼ぶ）。 */
	final run:GreenBuilder->Void;

	/** 期待する木。`GreenNode`・`GreenToken`・`GreenTrivia`のコンストラクタで組む。 */
	final expected:GreenNode;
}

/** イベントを送って`finish`で受け取った根の`fullLength`を確かめるケース。 */
private typedef RootLengthCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	/** 新しい`GreenBuilder`にイベントを送る。`finish`は呼ばない（`checkRootLengths`が呼ぶ）。 */
	final run:GreenBuilder->Void;

	final fullLength:Int;
}

/**
	`GreenBuilder`のテスト。
	根拠は`GreenBuilder`のクラスと各メソッドのdocコメント。
	`@throws`に挙がっていない呼び出し方は例外を投げない、と読む。
	期待する木は`GreenNode`・`GreenToken`・`GreenTrivia`のコンストラクタで組む。
	それらの`fullLength`の決まり方は`GreenNodeTest`で確かめている。

	観点:
	-         正常: `<< /A 1 >>`の木、子の順番、閉じたノードの行き先、`token`の引数、`missingToken`の中身、根の`fullLength`
	-         境目: 該当なし（字句の切れ目を持たない）
	-     範囲の端: どのノードにも入らないトークン（ノードの前・後）、内側だけ閉じたままの`finish`、閉じすぎの`finishNode`
	-     空・最小: 何も送らずに`finish`・`finishNode`、子0個のノード、`textLength`0
	- 不正なバイト: 該当なし（バイト列を受け取らない）。不正な引数はtestTokenThrows・testNodeKindCheckedAtFinishNode
	-       大きさ: 該当なし（イベントごとの処理で、再帰しない）
	-   仕様の細則: `startNode`の`kind`は`finishNode`で検査する、検査するのは閉じるノードだけ、数えるのは最上位の要素だけ
**/
class GreenBuilderTest extends utest.Test {
	// テーブルを短く書くための補助

	/** フラグ無しのトークンを送る。 */
	static function send(b:GreenBuilder, kind:SyntaxKind, textLength:Int, ?trivia:ReadOnlyArray<GreenTrivia>) {
		b.token(kind, TokenFlags.NONE, trivia ?? [], textLength);
	}

	// 期待する木を組むための補助
	static inline function ws(length:Int) {
		return new GreenTrivia(Whitespace, length);
	}

	/** フラグ無しのトークン。 */
	static function tok(kind:SyntaxKind, textLength:Int, ?trivia:ReadOnlyArray<GreenTrivia>) {
		return new GreenToken(kind, TokenFlags.NONE, trivia ?? [], textLength);
	}

	static inline function node(kind:SyntaxKind, children:ReadOnlyArray<NodeChild>) {
		return new GreenNode(kind, children);
	}

	/**
		2つの要素が同じ形かを確かめる。比べるのは、種類・`fullLength`と、
		トークンなら`flags`・`textLength`・`leadingTrivia`（種類と長さ）、ノードなら子（数と、順に再帰）。
		`path`は失敗したときに、根からどこをたどったかを示す。
	**/
	static function assertSameElement(expected:NodeChild, actual:NodeChild, path:String) {
		Assert.equals(expected.kind, actual.kind, '$path: kind');
		Assert.equals(expected.fullLength, actual.fullLength, '$path: fullLength');
		final eToken = Std.downcast(expected, GreenToken);
		final aToken = Std.downcast(actual, GreenToken);
		final eNode = Std.downcast(expected, GreenNode);
		final aNode = Std.downcast(actual, GreenNode);
		if (eToken != null) {
			if (aToken == null) {
				Assert.fail('$path: expected a token, but was a node');
				return;
			}
			Assert.isTrue(eToken.flags == aToken.flags, '$path: flags');
			Assert.equals(eToken.textLength, aToken.textLength, '$path: textLength');
			Assert.equals(eToken.leadingTrivia.length, aToken.leadingTrivia.length, '$path: leadingTrivia count');
			for (i in 0...Std.int(Math.min(eToken.leadingTrivia.length, aToken.leadingTrivia.length))) {
				Assert.equals(eToken.leadingTrivia[i].kind, aToken.leadingTrivia[i].kind, '$path: leadingTrivia[$i].kind');
				Assert.equals(eToken.leadingTrivia[i].length, aToken.leadingTrivia[i].length, '$path: leadingTrivia[$i].length');
			}
		} else if (eNode != null) {
			if (aNode == null) {
				Assert.fail('$path: expected a node, but was a token');
				return;
			}
			Assert.equals(eNode.children.length, aNode.children.length, '$path: children count');
			for (i in 0...Std.int(Math.min(eNode.children.length, aNode.children.length))) {
				assertSameElement(eNode.children[i], aNode.children[i], '$path/${aNode.children[i].kind}[$i]');
			}
		}
	}

	static function checkTrees(cases:Array<TreeCase>) {
		for (c in cases) {
			final b = new GreenBuilder();
			c.run(b);
			assertSameElement(c.expected, b.finish(), c.name);
		}
	}

	static function checkRootLengths(cases:Array<RootLengthCase>) {
		for (c in cases) {
			final b = new GreenBuilder();
			c.run(b);
			Assert.equals(c.fullLength, b.finish().fullLength, c.name);
		}
	}

	static function checkThrows(cases:Array<ThrowCase>) {
		for (c in cases) {
			final make = () -> c.run(new GreenBuilder());
			if (c.throws) {
				Assert.raises(make, Exception, c.name);
			} else {
				try {
					make();
					Assert.pass(c.name);
				} catch (e:Exception) {
					Assert.fail('${c.name}: unexpected exception: ${e.message}');
				}
			}
		}
	}

	/** [GreenBuilder.finishNodeのdocコメント] 開いているノードが無いときだけ例外。 */
	function testFinishNodeThrows() {
		checkThrows([
			{
				name: "何も送らずにfinishNode → 例外（開いているノードが無い）",
				run: b -> b.finishNode(),
				throws: true
			},
			{
				name: "トークンだけ送ってfinishNode → 例外（トークンはノードを開かない）",
				run: function(b) {
					send(b, Integer, 1);
					b.finishNode();
				},
				throws: true
			},
			{
				name: "startNode1回にfinishNode2回 → 例外（2回目には開いているノードが無い）",
				run: function(b) {
					b.startNode(Document);
					b.finishNode();
					b.finishNode();
				},
				throws: true
			},
			{
				name: "startNodeの直後にfinishNode（子0個） → 例外にならない",
				run: function(b) {
					b.startNode(Document);
					b.finishNode();
				},
				throws: false
			},
			{
				name: "2段の入れ子をfinishNode2回で閉じる → 例外にならない",
				run: function(b) {
					b.startNode(Document);
					b.startNode(Dictionary);
					send(b, LeftDoubleAngle, 2);
					b.finishNode();
					b.finishNode();
				},
				throws: false
			},
		]);
	}

	/** [GreenBuilder.finishのdocコメント] 閉じていないノードがあれば例外。 */
	function testFinishThrowsWhenNodeOpen() {
		checkThrows([
			{
				name: "startNodeだけでfinish → 例外",
				run: function(b) {
					b.startNode(Document);
					b.finish();
				},
				throws: true
			},
			{
				name: "内側だけ閉じて外側を閉じずにfinish → 例外",
				run: function(b) {
					b.startNode(Document);
					b.startNode(Dictionary);
					b.finishNode();
					b.finish();
				},
				throws: true
			},
		]);
	}

	/** [GreenBuilder.finishのdocコメント] 最上位の要素がノード1つでなければ例外。docコメントの「たとえば」の3つと、その近く。 */
	function testFinishThrowsUnlessSingleRootNode() {
		checkThrows([
			{
				name: "何も送らずにfinish → 例外（最上位の要素が0個）",
				run: b -> b.finish(),
				throws: true
			},
			{
				name: "最上位でノードを2つ閉じてfinish → 例外",
				run: function(b) {
					b.startNode(Document);
					b.finishNode();
					b.startNode(Document);
					b.finishNode();
					b.finish();
				},
				throws: true
			},
			{
				name: "最上位にトークン1つだけでfinish → 例外（要素は1つだがノードでない）",
				run: function(b) {
					send(b, Integer, 1);
					b.finish();
				},
				throws: true
			},
			{
				name: "最上位にmissingToken1つだけでfinish → 例外（要素は1つだがノードでない）",
				run: function(b) {
					b.missingToken(RightDoubleAngle);
					b.finish();
				},
				throws: true
			},
		]);
	}

	/** [GreenBuilder.finishのdocコメント] どのノードにも入らないトークンがあれば例外（最上位の要素がノード1つでない）。 */
	function testFinishThrowsOnTokenOutsideNode() {
		checkThrows([
			{
				name: "ノードの前に、どのノードにも入らないトークン → 例外",
				run: function(b) {
					send(b, Integer, 1);
					b.startNode(Document);
					b.finishNode();
					b.finish();
				},
				throws: true
			},
			{
				name: "ノードの後に、どのノードにも入らないトークン → 例外",
				run: function(b) {
					b.startNode(Document);
					b.finishNode();
					send(b, Integer, 1);
					b.finish();
				},
				throws: true
			},
		]);
	}

	/** [GreenBuilder.finishのdocコメント] `@throws`のどれにも当たらなければ例外にならない。 */
	function testFinishSucceeds() {
		checkThrows([
			{
				name: "子0個のノード1つ → 例外にならない",
				run: function(b) {
					b.startNode(Document);
					b.finishNode();
					b.finish();
				},
				throws: false
			},
			{
				name: "トークンとmissingTokenを子に持つノード1つ → 例外にならない",
				run: function(b) {
					b.startNode(Dictionary);
					send(b, LeftDoubleAngle, 2);
					b.missingToken(RightDoubleAngle);
					b.finishNode();
					b.finish();
				},
				throws: false
			},
			{
				name: "最上位のノード1つの中に、閉じたノードが2つ → 例外にならない（数えるのは最上位だけ）",
				run: function(b) {
					b.startNode(Document);
					b.startNode(IndirectObject);
					b.finishNode();
					b.startNode(IndirectObject);
					b.finishNode();
					b.finishNode();
					b.finish();
				},
				throws: false
			},
		]);
	}

	/**
		[GreenBuilderのクラスのdocコメント] 要素は最も内側の開いているノードの子になり、順番は送った順。
		[GreenBuilder.finishNodeのdocコメント] 閉じたノードは1つ外側のノードの子になる。
		学習ノート`event-builder.md`の`<< /A 1 >>`の例。
	**/
	function testTreeOfDictionaryExample() {
		checkTrees([
			{
				name: "<< /A 1 >> → Dictionary(<<, DictEntry(/A, 1), >>)",
				run: function(b) {
					b.startNode(Dictionary);
					send(b, LeftDoubleAngle, 2);
					b.startNode(DictEntry);
					send(b, Name, 2, [ws(1)]);
					send(b, Integer, 1, [ws(1)]);
					b.finishNode();
					send(b, RightDoubleAngle, 2, [ws(1)]);
					b.finishNode();
				},
				expected: node(Dictionary, [
					tok(LeftDoubleAngle, 2),
					node(DictEntry, [tok(Name, 2, [ws(1)]), tok(Integer, 1, [ws(1)])]),
					tok(RightDoubleAngle, 2, [ws(1)])
				])
			},
		]);
	}

	/** [GreenBuilderのクラスのdocコメント]・[GreenBuilder.finishNodeのdocコメント] 子の数・順番と、閉じたノードの行き先。 */
	function testTreeShape() {
		checkTrees([
			{
				name: "startNodeの直後にfinishNode → 子0個のノード",
				run: function(b) {
					b.startNode(Document);
					b.finishNode();
				},
				expected: node(Document, [])
			},
			{
				name: "トークン3つ → 送った順に3つの子",
				run: function(b) {
					b.startNode(Array);
					send(b, Integer, 1);
					send(b, Real, 3, [ws(1)]);
					send(b, Name, 2, [ws(1)]);
					b.finishNode();
				},
				expected: node(Array, [tok(Integer, 1), tok(Real, 3, [ws(1)]), tok(Name, 2, [ws(1)])])
			},
			{
				name: "内側のノードを閉じた後のトークン → 外側のノードの、内側のノードの次の子",
				run: function(b) {
					b.startNode(Document);
					b.startNode(IndirectObject);
					send(b, KwObj, 3);
					b.finishNode();
					send(b, EndOfFile, 0, [ws(1)]);
					b.finishNode();
				},
				expected: node(Document, [node(IndirectObject, [tok(KwObj, 3)]), tok(EndOfFile, 0, [ws(1)])])
			},
		]);
	}

	/** [GreenBuilder.tokenのdocコメント] 引数どおりのトークン。[GreenBuilder.missingTokenのdocコメント] MISSINGだけ・トリビア無し・長さ0。 */
	function testTokenContents() {
		checkTrees([
			{
				name: "tokenに渡したフラグ（Unterminated）とトリビア2つ → そのままトークンに入る",
				run: function(b) {
					b.startNode(Document);
					b.token(LiteralString, TokenFlags.UNTERMINATED, [ws(2), new GreenTrivia(Comment, 4)], 3);
					b.finishNode();
				},
				expected: node(Document, [
					new GreenToken(LiteralString, TokenFlags.UNTERMINATED, [ws(2), new GreenTrivia(Comment, 4)], 3)
				])
			},
			{
				name: "missingToken(RightDoubleAngle) → 種類RightDoubleAngle・フラグMISSINGだけ・トリビア無し・textLength 0",
				run: function(b) {
					b.startNode(Dictionary);
					send(b, LeftDoubleAngle, 2);
					b.missingToken(RightDoubleAngle);
					b.finishNode();
				},
				expected: node(Dictionary, [
					tok(LeftDoubleAngle, 2),
					new GreenToken(RightDoubleAngle, TokenFlags.MISSING, [], 0)
				])
			},
		]);
	}

	/**
		[GreenBuilderのクラスのdocコメント]・[GreenNode.newのdocコメント] 根の`fullLength`は、送ったトークンの`fullLength`の合計。
		WBS M1-5の完了条件「手で組んだ木で`fullLength`が子の合計になる」。
	**/
	function testRootFullLength() {
		checkRootLengths([
			{
				name: "<< /A 1 >> → 10（<< 2、/Aと空白 3、1と空白 2、>>と空白 3）",
				run: function(b) {
					b.startNode(Dictionary);
					send(b, LeftDoubleAngle, 2);
					b.startNode(DictEntry);
					send(b, Name, 2, [ws(1)]);
					send(b, Integer, 1, [ws(1)]);
					b.finishNode();
					send(b, RightDoubleAngle, 2, [ws(1)]);
					b.finishNode();
				},
				fullLength: 10
			},
			{
				name: "子0個のノード → 0",
				run: function(b) {
					b.startNode(Document);
					b.finishNode();
				},
				fullLength: 0
			},
			{
				name: "missingTokenだけを子に持つノード → 0（missing tokenは幅0）",
				run: function(b) {
					b.startNode(Dictionary);
					b.missingToken(RightDoubleAngle);
					b.finishNode();
				},
				fullLength: 0
			},
			{
				name: "3段の入れ子の奥の<<（2）と、外側のトリビアだけのEndOfFile（3） → 5",
				run: function(b) {
					b.startNode(Document);
					b.startNode(IndirectObject);
					b.startNode(Dictionary);
					send(b, LeftDoubleAngle, 2);
					b.finishNode();
					b.finishNode();
					send(b, EndOfFile, 0, [ws(3)]);
					b.finishNode();
				},
				fullLength: 5
			},
		]);
	}

	/** [GreenBuilder.token・GreenBuilder.missingTokenのdocコメント] トークンでない`kind`と、0未満の`textLength`は例外。 */
	function testTokenThrows() {
		checkThrows([
			{name: "tokenにトリビアの種別（Comment） → 例外", run: b -> send(b, Comment, 1), throws: true},
			{name: "tokenにノードの種別（Document） → 例外", run: b -> send(b, Document, 1), throws: true},
			{name: "tokenにtextLength -1 → 例外（0未満）", run: b -> send(b, Name, -1), throws: true},
			{name: "tokenにtextLength 0 → 例外にならない（0未満ではない）", run: b -> send(b, Name, 0), throws: false},
			{name: "missingTokenにトリビアの種別（Whitespace） → 例外", run: b -> b.missingToken(Whitespace), throws: true},
			{name: "missingTokenにノードの種別（Dictionary） → 例外", run: b -> b.missingToken(Dictionary), throws: true},
			{name: "missingTokenにトークンの種別（EndOfFile） → 例外にならない", run: b -> b.missingToken(EndOfFile), throws: false},
		]);
	}

	/** [GreenBuilder.startNode・GreenBuilder.finishNodeのdocコメント] `kind`は`finishNode`で検査し、ノードでなければ例外。 */
	function testNodeKindCheckedAtFinishNode() {
		checkThrows([
			{
				name: "startNodeにトークンの種別（Integer）だけ → 例外にならない（検査はfinishNode）",
				run: b -> b.startNode(Integer),
				throws: false
			},
			{
				name: "startNode(Integer)を閉じる → 例外",
				run: function(b) {
					b.startNode(Integer);
					b.finishNode();
				},
				throws: true
			},
			{
				name: "startNode(Whitespace)を閉じる → 例外",
				run: function(b) {
					b.startNode(Whitespace);
					b.finishNode();
				},
				throws: true
			},
			{
				name: "外側がstartNode(Integer)でも、内側のDocumentを閉じる → 例外にならない（検査するのは閉じるノードだけ）",
				run: function(b) {
					b.startNode(Integer);
					b.startNode(Document);
					b.finishNode();
				},
				throws: false
			},
		]);
	}
}
