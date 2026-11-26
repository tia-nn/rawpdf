package rawpdf.cst.syntax;

import haxe.Exception;
import haxe.ds.ReadOnlyArray;
import utest.Assert;

/** 組み立てた要素の`fullLength`を確かめるケース。要素はテーブルの中で組み立てる。 */
private typedef LengthCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final element:GreenNode.GreenNodeChild;
	final fullLength:Int;
}

/** コンストラクタが例外を投げるかどうかを確かめるケース。 */
private typedef ConstructCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final make:() -> Void;
	final throws:Bool;
}

/**
	Green層（`GreenTrivia`・`GreenToken`・`GreenNode`）のテスト。
	根拠は各コンストラクタのdocコメント。種別がトリビア・トークン・ノードのどれかは、`SyntaxKind`の定義の区分（`// trivia`・`// tokens`・`// nodes`）による。
**/
class GreenNodeTest extends utest.Test {
	// テーブルを短く書くための補助
	static inline function ws(length:Int) {
		return new GreenTrivia(Whitespace, length);
	}

	static inline function comment(length:Int) {
		return new GreenTrivia(Comment, length);
	}

	/** フラグ無しのトークン。 */
	static function tok(kind:SyntaxKind, textLength:Int, ?trivia:ReadOnlyArray<GreenTrivia>) {
		return new GreenToken(kind, TokenFlags.NONE, trivia ?? [], textLength);
	}

	static inline function node(kind:SyntaxKind, children:ReadOnlyArray<GreenNode.GreenNodeChild>) {
		return new GreenNode(kind, children);
	}

	static function checkLengths(cases:Array<LengthCase>) {
		for (c in cases) {
			Assert.equals(c.fullLength, c.element.fullLength, c.name);
		}
	}

	static function checkConstruct(cases:Array<ConstructCase>) {
		for (c in cases) {
			if (c.throws) {
				Assert.raises(c.make, Exception, c.name);
			} else {
				try {
					c.make();
					Assert.pass(c.name);
				} catch (e:Exception) {
					Assert.fail('${c.name}: unexpected exception: ${e.message}');
				}
			}
		}
	}

	/**
		[GreenTrivia.newのdocコメント] トリビア以外の`kind`と、1未満の`length`は例外。
		観点:
		-         正常: Whitespace・Comment、長さ1
		-         境目: 該当なし（字句の切れ目を持たない）
		-     範囲の端: 長さ1（作れる）と0（例外）、トリビアの区間の外側（Integer・Document）
		-     空・最小: 長さ0・-1で例外
		- 不正なバイト: 該当なし（バイト列を受け取らない）
		-       大きさ: 該当なし（中身を走査しない）
		-   仕様の細則: 該当なし
	**/
	function testTriviaConstruct() {
		checkConstruct([
			{name: "Whitespace・長さ1 → 作れる", make: () -> new GreenTrivia(Whitespace, 1), throws: false},
			{name: "Comment・長さ1 → 作れる", make: () -> new GreenTrivia(Comment, 1), throws: false},
			{name: "長さ0 → 例外（1未満）", make: () -> new GreenTrivia(Whitespace, 0), throws: true},
			{name: "長さ-1 → 例外（1未満）", make: () -> new GreenTrivia(Whitespace, -1), throws: true},
			{name: "トークンの種別（トリビアの直後のInteger） → 例外", make: () -> new GreenTrivia(Integer, 1), throws: true},
			{name: "ノードの種別（Document） → 例外", make: () -> new GreenTrivia(Document, 1), throws: true},
		]);
	}

	/**
		[GreenToken.newのdocコメント] トークン以外の`kind`と、0未満の`textLength`は例外。
		`fullLength`はtestTokenFullLengthで見る。この表は両方のメソッドの分。
		観点:
		-         正常: トリビアなし・1つ・2つの`fullLength`
		-         境目: 該当なし（字句の切れ目を持たない）
		-     範囲の端: トークンの区間の両端（Integer・EndOfFile）とその外側（Comment・Document）、`textLength`0と-1
		-     空・最小: `textLength`0（missing token、トリビアだけのEndOfFile）
		- 不正なバイト: 該当なし（バイト列を受け取らない）
		-       大きさ: 該当なし（トリビアの長さを足すだけで、再帰しない）
		-   仕様の細則: 該当なし
	**/
	function testTokenConstruct() {
		checkConstruct([
			{name: "トークンの先頭の種別（Integer） → 作れる", make: () -> tok(Integer, 1), throws: false},
			{name: "トークンの末尾の種別（EndOfFile）・長さ0 → 作れる", make: () -> tok(EndOfFile, 0), throws: false},
			{name: "textLength 0 → 作れる（0未満ではない）", make: () -> tok(Name, 0), throws: false},
			{name: "textLength -1 → 例外（0未満）", make: () -> tok(Name, -1), throws: true},
			{name: "トリビアの種別（Comment） → 例外", make: () -> tok(Comment, 1), throws: true},
			{name: "ノードの種別（Document） → 例外", make: () -> tok(Document, 1), throws: true},
		]);
	}

	/** [GreenToken.newのdocコメント] `fullLength`は`textLength`とleadingTriviaの`length`の合計。観点の表はtestTokenConstruct。 */
	function testTokenFullLength() {
		checkLengths([
			{name: "トリビアなし → textLength", element: tok(Name, 2), fullLength: 2},
			{name: "トリビア1つ → 1 + 2", element: tok(Name, 2, [ws(1)]), fullLength: 3},
			{name: "トリビア2つ（空白とコメント） → 1 + 4 + 1", element: tok(Integer, 1, [ws(1), comment(4)]), fullLength: 6},
			{name: "textLength 0・トリビアなし（missing token） → 0", element: new GreenToken(RightDoubleAngle, TokenFlags.MISSING, [], 0), fullLength: 0},
			{name: "textLength 0・トリビアあり（末尾のEndOfFile） → トリビアの合計", element: tok(EndOfFile, 0, [ws(2)]), fullLength: 2},
		]);
	}

	/**
		[GreenNode.newのdocコメント] ノード以外の`kind`は例外。
		`fullLength`はtestNodeFullLengthで見る。この表は両方のメソッドの分。
		観点:
		-         正常: トークンだけ・入れ子・ノードだけを子に持つノードの`fullLength`
		-         境目: 該当なし（字句の切れ目を持たない）
		-     範囲の端: ノードの区間の両端（Document・ErrorNode）とその外側（EndOfFile・Whitespace）
		-     空・最小: 子なし（0）、幅0の子（missing token）を含む
		- 不正なバイト: 該当なし（バイト列を受け取らない）
		-       大きさ: 該当なし（子の`fullLength`を足すだけで、再帰しない）
		-   仕様の細則: 該当なし
	**/
	function testNodeConstruct() {
		checkConstruct([
			{name: "ノードの先頭の種別（Document） → 作れる", make: () -> node(Document, []), throws: false},
			{name: "ノードの末尾の種別（ErrorNode） → 作れる", make: () -> node(ErrorNode, []), throws: false},
			{name: "トークンの種別（EndOfFile） → 例外", make: () -> node(EndOfFile, []), throws: true},
			{name: "トリビアの種別（Whitespace） → 例外", make: () -> node(Whitespace, []), throws: true},
		]);
	}

	/** [GreenNode.newのdocコメント] `fullLength`は子の`fullLength`の合計。観点の表はtestNodeConstruct。 */
	function testNodeFullLength() {
		checkLengths([
			{name: "子なし → 0（空の合計）", element: node(Document, []), fullLength: 0},
			{name: "トークンだけ（[ 1 ]） → 1 + 2", element: node(SyntaxKind.Array, [tok(LeftBracket, 1), tok(RightBracket, 1, [ws(1)])]), fullLength: 3},
			{
				name: "入れ子（<< /A 1 >>） → 2 + (3 + 2) + 3",
				element: node(Dictionary, [
					tok(LeftDoubleAngle, 2),
					node(DictEntry, [tok(Name, 2, [ws(1)]), tok(Integer, 1, [ws(1)])]),
					tok(RightDoubleAngle, 2, [ws(1)]),
				]),
				fullLength: 10
			},
			{
				name: "幅0の子（missing token）を含む → 残りの子の合計",
				element: node(Dictionary, [
					tok(LeftDoubleAngle, 2),
					new GreenToken(RightDoubleAngle, TokenFlags.MISSING, [], 0)
				]),
				fullLength: 2
			},
			{
				name: "ノードだけを子に持つ → 1 + (1 + 1)",
				element: node(Document, [node(Segment, [tok(Integer, 1)]), node(Segment, [tok(Integer, 1, [ws(1)])])]),
				fullLength: 3
			},
		]);
	}
}
