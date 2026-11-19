package rawpdf.cst.syntax;

import utest.Assert;

using rawpdf.cst.syntax.SyntaxKind;

/** テストの期待値として使う、種別のグループ（SyntaxKindの型のdocコメント: トリビア・トークン・ノード）。 */
private enum Group {
	Trivia;
	Token;
	Node;
}

/**
	SyntaxKindの分類ヘルパのテスト。根拠はSyntaxKindの型と、`isTrivia`・`isToken`・`isKeyword`・`isNode`のdocコメント。

	観点:
	-         正常: 全種別がグループのちょうど1つに属する、キーワードはKw*の13種だけ
	-         境目: 該当なし（字句の切れ目を持たない）
	-     範囲の端: 各グループの区間の両端と、その外側（test*Boundary）
	-     空・最小: 該当なし（入力は種別1つ）
	- 不正なバイト: 該当なし（定義済みの種別だけを扱う）
	-       大きさ: 該当なし（値の比較だけ）
	-   仕様の細則: キーワードはすべてトークンでもある
**/
class SyntaxKindTest extends utest.Test {
	/**
		定義済みの全種別。種別を足したら、ここと`expectedGroup`の両方に足す。
		`expectedGroup`は網羅的なswitchなので、足し忘れるとコンパイルエラーになる。
		`Array`は型名と衝突しないよう修飾して書く。
	**/
	static final allKinds:Array<SyntaxKind> = [
		// trivia
		Whitespace,
		Comment,
		// tokens
		Integer,
		Real,
		Name,
		LiteralString,
		HexString,
		LeftBracket,
		RightBracket,
		LeftDoubleAngle,
		RightDoubleAngle,
		LeftBrace,
		RightBrace,
		KwTrue,
		KwFalse,
		KwNull,
		KwR,
		KwObj,
		KwEndobj,
		KwStream,
		KwEndstream,
		KwXref,
		KwTrailer,
		KwStartxref,
		KwN,
		KwF,
		HeaderMarker,
		StreamBody,
		Unknown,
		EndOfFile,
		// nodes
		Document,
		Header,
		Segment,
		IndirectObject,
		StreamClause,
		SyntaxKind.Array,
		Dictionary,
		DictEntry,
		Reference,
		XrefSection,
		XrefSubsection,
		XrefEntry,
		TrailerClause,
		StartxrefClause,
		ErrorNode,
	];

	/** 各種別が属するべきグループ。定義の`// trivia`・`// tokens`・`// nodes`の区分を写す（SyntaxKindの型のdocコメント）。 */
	static function expectedGroup(k:SyntaxKind):Group {
		return switch k {
			case Whitespace | Comment: Trivia;
			case Integer | Real | Name | LiteralString | HexString | LeftBracket | RightBracket | LeftDoubleAngle | RightDoubleAngle | LeftBrace |
				RightBrace | KwTrue | KwFalse | KwNull | KwR | KwObj | KwEndobj | KwStream | KwEndstream | KwXref | KwTrailer | KwStartxref | KwN | KwF |
				HeaderMarker | StreamBody | Unknown | EndOfFile: Token;
			case Document | Header | Segment | IndirectObject | StreamClause | Array | Dictionary | DictEntry | Reference | XrefSection | XrefSubsection |
				XrefEntry | TrailerClause | StartxrefClause | ErrorNode: Node;
		}
	}

	/** キーワードであるべき種別（isKeywordのdocコメント: `Kw*`の13種）。Lexerリファレンス2章の表のキーワード13個と1対1に対応する。 */
	static function expectedKeyword(k:SyntaxKind):Bool {
		return switch k {
			case KwTrue | KwFalse | KwNull | KwR | KwObj | KwEndobj | KwStream | KwEndstream | KwXref | KwTrailer | KwStartxref | KwN | KwF: true;
			case _: false;
		}
	}

	/** [isTriviaのdocコメント] トリビアの両端（Whitespace・Comment）と、その直後のグループの先頭（Integer）。 */
	function testIsTriviaBoundary() {
		Assert.isTrue(Whitespace.isTrivia());
		Assert.isTrue(Comment.isTrivia());
		Assert.isFalse(Integer.isTrivia());
	}

	/** [isTokenのdocコメント] トークンの両端（Integer・EndOfFile）と、その外側（Comment・Document）。 */
	function testIsTokenBoundary() {
		Assert.isFalse(Comment.isToken());
		Assert.isTrue(Integer.isToken());
		Assert.isTrue(EndOfFile.isToken());
		Assert.isFalse(Document.isToken());
	}

	/** [isKeywordのdocコメント] キーワードの両端（KwTrue・KwF）と、その外側（RightBrace・HeaderMarker）。 */
	function testIsKeywordBoundary() {
		Assert.isFalse(RightBrace.isKeyword());
		Assert.isTrue(KwTrue.isKeyword());
		Assert.isTrue(KwF.isKeyword());
		Assert.isFalse(HeaderMarker.isKeyword());
	}

	/** [isNodeのdocコメント] ノードの両端（Document・ErrorNode）と、その外側（EndOfFile）。 */
	function testIsNodeBoundary() {
		Assert.isFalse(EndOfFile.isNode());
		Assert.isTrue(Document.isNode());
		Assert.isTrue(ErrorNode.isNode());
	}

	/** [SyntaxKindの型のdocコメント] 全種別が、期待どおりのグループのちょうど1つに属する。 */
	function testEveryKindBelongsToExactlyOneGroup() {
		for (k in allKinds) {
			final group = expectedGroup(k);
			final message = 'kind=$k';
			Assert.equals(group == Trivia, k.isTrivia(), message);
			Assert.equals(group == Token, k.isToken(), message);
			Assert.equals(group == Node, k.isNode(), message);
		}
	}

	/** [isKeywordのdocコメント] キーワードはKw*の13種だけで、すべてトークンでもある。 */
	function testKeywordsAreExactlyKwKinds() {
		var count = 0;
		for (k in allKinds) {
			final message = 'kind=$k';
			Assert.equals(expectedKeyword(k), k.isKeyword(), message);
			if (k.isKeyword()) {
				count++;
				Assert.isTrue(k.isToken(), message);
			}
		}
		Assert.equals(13, count);
	}
}
