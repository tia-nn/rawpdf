package rawpdf.cst.syntax;

/**
	構文要素の種別。

	定義済みの種別は、トリビア（定義の`// trivia`の区分）・トークン（`// tokens`の区分）・ノード（`// nodes`の区分）の
	ちょうど1つに属する。`isTrivia`・`isToken`・`isNode`は、そのうち1つだけが`true`になる。

	呼び出し側は定義済みの値以外をcastで作らない。 `cast` で作った隙間の値に対する判定メソッドの結果は未定義。
**/
enum abstract SyntaxKind(Int) {
	// trivia
	var Whitespace;
	var Comment;
	// tokens
	var Integer = 10;
	var Real;
	var Name;
	var LiteralString;
	var HexString;
	var LeftBracket;
	var RightBracket;
	var LeftDoubleAngle;
	var RightDoubleAngle;
	var LeftBrace;
	var RightBrace;
	var KwTrue = 30;
	var KwFalse;
	var KwNull;
	var KwR;
	var KwObj;
	var KwEndobj;
	var KwStream;
	var KwEndstream;
	var KwXref;
	var KwTrailer;
	var KwStartxref;
	var KwN;
	var KwF;
	var HeaderMarker = 50;
	var StreamBody;
	var Unknown = 60;
	var EndOfFile;
	// nodes
	var Document = 100;
	var Header;
	var Segment;
	var IndirectObject;
	var StreamClause;
	var Array;
	var Dictionary;
	var DictEntry;
	var Reference;
	var XrefSection;
	var XrefSubsection;
	var XrefEntry;
	var TrailerClause;
	var StartxrefClause;
	var ErrorNode;

	/** トリビア（`Whitespace`・`Comment`）なら`true`。 **/
	public inline function isTrivia() {
		return 0 <= this && this < cast Integer;
	}

	/** トークン（`Integer`から`EndOfFile`まで）なら`true`。トリビアとノードは含まない。 **/
	public inline function isToken() {
		return (cast Integer) <= this && this < cast Document;
	}

	/** キーワード（`KwTrue`から`KwF`までの`Kw*`13種）なら`true`。キーワードはすべてトークンでもある。 **/
	public inline function isKeyword() {
		return (cast KwTrue) <= this && this < cast HeaderMarker;
	}

	/** ノード（`Document`から`ErrorNode`まで）なら`true`。 **/
	public inline function isNode() {
		return (cast Document) <= this;
	}
}
