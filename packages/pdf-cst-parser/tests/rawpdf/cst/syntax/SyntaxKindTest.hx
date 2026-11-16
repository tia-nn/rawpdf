package rawpdf.cst.syntax;

import utest.Assert;
import rawpdf.cst.syntax.SyntaxKind;

/** テストの期待値として使う、種別のグループ（パーサ詳細設計3章）。 */
private enum Group {
	Trivia;
	Token;
	Node;
}

/** SyntaxKindの分類ヘルパのテスト（パーサ詳細設計3章）。 */
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

	/** 各種別が属するべきグループ。`isToken`はトリビアを含まない（詳細設計3章）。 */
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

	/** キーワードであるべき種別。基本設計4.2節の既知キーワード13個と1対1に対応する。 */
	static function expectedKeyword(k:SyntaxKind):Bool {
		return switch k {
			case KwTrue | KwFalse | KwNull | KwR | KwObj | KwEndobj | KwStream | KwEndstream | KwXref | KwTrailer | KwStartxref | KwN | KwF: true;
			case _: false;
		}
	}

	/** トリビアの区間の両端（Whitespace・Comment）と、その直後のグループの先頭（Integer）。 */
	function testIsTriviaBoundary() {
		Assert.isTrue(Whitespace.isTrivia());
		Assert.isTrue(Comment.isTrivia());
		Assert.isFalse(Integer.isTrivia());
	}

	/** トークンの区間の両端（Integer・EndOfFile）と、その外側（Comment・Document）。 */
	function testIsTokenBoundary() {
		Assert.isFalse(Comment.isToken());
		Assert.isTrue(Integer.isToken());
		Assert.isTrue(EndOfFile.isToken());
		Assert.isFalse(Document.isToken());
	}

	/** キーワードの区間の両端（KwTrue・KwF）と、その外側（RightBrace・HeaderMarker）。 */
	function testIsKeywordBoundary() {
		Assert.isFalse(RightBrace.isKeyword());
		Assert.isTrue(KwTrue.isKeyword());
		Assert.isTrue(KwF.isKeyword());
		Assert.isFalse(HeaderMarker.isKeyword());
	}

	/** ノードの区間の両端（Document・ErrorNode）と、その外側（EndOfFile）。 */
	function testIsNodeBoundary() {
		Assert.isFalse(EndOfFile.isNode());
		Assert.isTrue(Document.isNode());
		Assert.isTrue(ErrorNode.isNode());
	}

	/** 全種別が、期待どおりのグループのちょうど1つに属する。 */
	function testEveryKindBelongsToExactlyOneGroup() {
		for (k in allKinds) {
			final group = expectedGroup(k);
			final message = 'kind=$k';
			Assert.equals(group == Trivia, k.isTrivia(), message);
			Assert.equals(group == Token, k.isToken(), message);
			Assert.equals(group == Node, k.isNode(), message);
		}
	}

	/** キーワードはKw*の13種だけで、すべてトークンでもある。 */
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
