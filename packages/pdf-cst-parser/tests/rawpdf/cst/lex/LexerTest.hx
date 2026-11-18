package rawpdf.cst.lex;

import haxe.io.Bytes;
import rawpdf.cst.syntax.SyntaxKind;
import utest.Assert;

/** Lexerのテスト（パーサ基本設計4.2節・詳細設計6.2節）。 */
class LexerTest extends utest.Test {
	/** 空白6種（基本設計4.1節）。 */
	static final WHITESPACES = [0x00, 0x09, 0x0A, 0x0C, 0x0D, 0x20];

	/** 無限ループで止まらないようにするための、1回の字句解析で読むトークン数の上限。 */
	static inline final MAX_TOKENS = 10000;

	static function bytesOf(values:Array<Int>) {
		final bytes = Bytes.alloc(values.length);
		for (i => v in values) {
			bytes.set(i, v);
		}
		return bytes;
	}

	/** `EndOfFile`までのトークンをすべて読む（`EndOfFile`自身も含む）。 */
	static function lexAll(bytes:Bytes, ?options:Lexer.LexerOptions):Array<RawToken> {
		final lexer = new Lexer(bytes, options);
		final tokens = [];
		for (_ in 0...MAX_TOKENS) {
			final token = lexer.next();
			tokens.push(token);
			if (token.kind == EndOfFile) {
				return tokens;
			}
		}
		throw 'EndOfFile was not returned within $MAX_TOKENS tokens';
	}

	static function assertToken(kind:SyntaxKind, start:Int, end:Int, token:RawToken, ?pos:haxe.PosInfos) {
		Assert.equals(kind, token.kind, "kind", pos);
		Assert.equals(start, token.start, "start", pos);
		Assert.equals(end, token.end, "end", pos);
		Assert.isTrue(token.flags.isNone(), "flags", pos);
	}

	/** 空白6種のどれも、1バイトだけでWhitespaceになる。 */
	function testEachWhitespaceByte() {
		for (b in WHITESPACES) {
			final tokens = lexAll(bytesOf([b]));
			Assert.equals(2, tokens.length, 'byte=$b');
			assertToken(Whitespace, 0, 1, tokens[0]);
			assertToken(EndOfFile, 1, 1, tokens[1]);
		}
	}

	/** 6種が混ざった連続は、1つのWhitespaceにまとまる（最長一致）。 */
	function testMixedWhitespaceRunIsOneToken() {
		final tokens = lexAll(bytesOf(WHITESPACES));
		Assert.equals(2, tokens.length);
		assertToken(Whitespace, 0, 6, tokens[0]);
		assertToken(EndOfFile, 6, 6, tokens[1]);
	}

	/** 空白でないバイトの手前で止まり、そのバイトを取り込まない。 */
	function testStopsBeforeNonWhitespace() {
		final tokens = lexAll(Bytes.ofString(" \ta"));
		assertToken(Whitespace, 0, 2, tokens[0]);
		// 次のトークンが`a`の位置から始まる（`a`の種類はここでは見ない）
		Assert.equals(2, tokens[1].start);
	}

	/** 空白でないトークンの後ろから始まる空白。 */
	function testWhitespaceAfterOtherToken() {
		final tokens = lexAll(Bytes.ofString("a  "));
		assertToken(Whitespace, 1, 3, tokens[1]);
		assertToken(EndOfFile, 3, 3, tokens[2]);
	}

	/** 入力が空白で終わっても、範囲外を読まずにEndOfFileになる。 */
	function testWhitespaceAtEndOfInput() {
		final tokens = lexAll(Bytes.ofString("   "));
		Assert.equals(2, tokens.length);
		assertToken(Whitespace, 0, 3, tokens[0]);
		assertToken(EndOfFile, 3, 3, tokens[1]);
	}

	/** 範囲の終端（`end`）が空白の途中にあれば、そこで止まる。 */
	function testStopsAtRangeEnd() {
		final tokens = lexAll(Bytes.ofString("    "), {end: 2});
		Assert.equals(2, tokens.length);
		assertToken(Whitespace, 0, 2, tokens[0]);
		assertToken(EndOfFile, 2, 2, tokens[1]);
	}

	/** 範囲の開始（`start`）から読み始める。 */
	function testStartsAtRangeStart() {
		final tokens = lexAll(Bytes.ofString("a   "), {start: 2});
		Assert.equals(2, tokens.length);
		assertToken(Whitespace, 2, 4, tokens[0]);
		assertToken(EndOfFile, 4, 4, tokens[1]);
	}

	/** 長い空白（0x00の連続）でもスタックがあふれず、1つのWhitespaceになる。 */
	function testLongWhitespace() {
		final length = 100000;
		final bytes = Bytes.alloc(length);
		bytes.fill(0, length, 0x00); // allocの初期値はターゲットによって保証されないため、明示的に埋める
		final tokens = lexAll(bytes);
		Assert.equals(2, tokens.length);
		assertToken(Whitespace, 0, length, tokens[0]);
		assertToken(EndOfFile, length, length, tokens[1]);
	}

	// コメントとHeaderMarker（基本設計4.2節、詳細設計1章・6.2節、Lexer仕様書1章）

	/** コメントは行末の手前まで。LFは含まない。 */
	function testCommentStopsBeforeLf() {
		final tokens = lexAll(Bytes.ofString("%abc\n"));
		Assert.equals(3, tokens.length);
		assertToken(Comment, 0, 4, tokens[0]);
		assertToken(Whitespace, 4, 5, tokens[1]);
		assertToken(EndOfFile, 5, 5, tokens[2]);
	}

	/** CRでも止まる。CRLFはまとめて後ろのWhitespaceになる。 */
	function testCommentStopsBeforeCrLf() {
		final tokens = lexAll(Bytes.ofString("%abc\r\n"));
		Assert.equals(3, tokens.length);
		assertToken(Comment, 0, 4, tokens[0]);
		assertToken(Whitespace, 4, 6, tokens[1]);
	}

	/** 改行の無い末尾のコメントは、入力の終わりまで。 */
	function testCommentAtEndOfInput() {
		final tokens = lexAll(Bytes.ofString("%abc"));
		Assert.equals(2, tokens.length);
		assertToken(Comment, 0, 4, tokens[0]);
		assertToken(EndOfFile, 4, 4, tokens[1]);
	}

	/** 空のコメント（`%`の直後が改行）。 */
	function testEmptyComment() {
		final tokens = lexAll(Bytes.ofString("%\n"));
		assertToken(Comment, 0, 1, tokens[0]);
		assertToken(Whitespace, 1, 2, tokens[1]);
	}

	/** `%`だけの入力。`PDF-`を調べるときに範囲外を読まない。 */
	function testPercentOnly() {
		final tokens = lexAll(Bytes.ofString("%"));
		Assert.equals(2, tokens.length);
		assertToken(Comment, 0, 1, tokens[0]);
		assertToken(EndOfFile, 1, 1, tokens[1]);
	}

	/** `%`の後ろが4バイトに満たない入力は、例外にならずCommentになる。 */
	function testShortCommentsAtEndOfInput() {
		for (s in ["%P", "%PD", "%PDF"]) {
			final tokens = lexAll(Bytes.ofString(s));
			Assert.equals(2, tokens.length, s);
			assertToken(Comment, 0, s.length, tokens[0]);
		}
	}

	/** コメントの中のdelimiter・空白（SP・TAB等の改行以外）は、コメントの一部になる。 */
	function testCommentContainsDelimitersAndSpaces() {
		final tokens = lexAll(Bytes.ofString("%a (b) <</c>> [\t%d\n"));
		assertToken(Comment, 0, 18, tokens[0]);
		assertToken(Whitespace, 18, 19, tokens[1]);
	}

	/** `%%EOF`は、`PDF-`で始まらないのでComment。 */
	function testEofMarkerIsComment() {
		final tokens = lexAll(Bytes.ofString("%%EOF\n"));
		assertToken(Comment, 0, 5, tokens[0]);
	}

	/** `%PDF-`で始まるコメントはHeaderMarker（トリビアではない実トークン）。 */
	function testHeaderMarker() {
		final tokens = lexAll(Bytes.ofString("%PDF-1.7\r\n"));
		Assert.equals(3, tokens.length);
		assertToken(HeaderMarker, 0, 8, tokens[0]);
		assertToken(Whitespace, 8, 10, tokens[1]);
	}

	/** `PDF-`がちょうど入力の終わりに達する場合も、範囲内に収まるのでHeaderMarker。 */
	function testHeaderMarkerExactlyAtEndOfInput() {
		final tokens = lexAll(Bytes.ofString("%PDF-"));
		Assert.equals(2, tokens.length);
		assertToken(HeaderMarker, 0, 5, tokens[0]);
		assertToken(EndOfFile, 5, 5, tokens[1]);
	}

	/** 大文字・小文字は区別する。 */
	function testLowercasePdfIsComment() {
		final tokens = lexAll(Bytes.ofString("%pdf-1.7"));
		assertToken(Comment, 0, 8, tokens[0]);
	}

	/** ファイルの途中の`%PDF-`もHeaderMarkerになる（詳細設計1章）。 */
	function testHeaderMarkerInMiddle() {
		final tokens = lexAll(Bytes.ofString("\n%PDF-2.0"));
		assertToken(Whitespace, 0, 1, tokens[0]);
		assertToken(HeaderMarker, 1, 9, tokens[1]);
	}

	/** 範囲の終端（`end`）が`PDF-`の途中にあれば、範囲外を見ずにCommentになる。 */
	function testHeaderMarkerCutByRangeEnd() {
		for (end in 1...5) {
			final tokens = lexAll(Bytes.ofString("%PDF-1.7"), {end: end});
			Assert.equals(2, tokens.length, 'end=$end');
			assertToken(Comment, 0, end, tokens[0]);
			assertToken(EndOfFile, end, end, tokens[1]);
		}
	}

	/** 範囲の終端（`end`）がコメントの途中にあれば、そこで止まる。 */
	function testCommentCutByRangeEnd() {
		final tokens = lexAll(Bytes.ofString("%abcdef\n"), {end: 4});
		Assert.equals(2, tokens.length);
		assertToken(Comment, 0, 4, tokens[0]);
		assertToken(EndOfFile, 4, 4, tokens[1]);
	}

	// delimiter（基本設計4.2節、Lexer仕様書1章）。`<`単独・`(`・`/`は後のステップで振る舞いが変わるので、ここでは扱わない

	/** `[` `]` `{` `}`は、それぞれ1バイトのトークン。 */
	function testSingleByteDelimiters() {
		final cases:Array<{s:String, kind:SyntaxKind}> = [
			{s: "[", kind: LeftBracket},
			{s: "]", kind: RightBracket},
			{s: "{", kind: LeftBrace},
			{s: "}", kind: RightBrace},
		];
		for (c in cases) {
			final tokens = lexAll(Bytes.ofString(c.s));
			Assert.equals(2, tokens.length, c.s);
			assertToken(c.kind, 0, 1, tokens[0]);
			assertToken(EndOfFile, 1, 1, tokens[1]);
		}
	}

	/** 1バイトのdelimiterは、連続しても1つずつに分かれる。 */
	function testSingleByteDelimitersInARow() {
		final tokens = lexAll(Bytes.ofString("[[]{}]"));
		Assert.equals(7, tokens.length);
		assertToken(LeftBracket, 0, 1, tokens[0]);
		assertToken(LeftBracket, 1, 2, tokens[1]);
		assertToken(RightBracket, 2, 3, tokens[2]);
		assertToken(LeftBrace, 3, 4, tokens[3]);
		assertToken(RightBrace, 4, 5, tokens[4]);
		assertToken(RightBracket, 5, 6, tokens[5]);
		assertToken(EndOfFile, 6, 6, tokens[6]);
	}

	/** `<<`と`>>`は2バイトのトークン。 */
	function testDoubleAngles() {
		final tokens = lexAll(Bytes.ofString("<<>>"));
		Assert.equals(3, tokens.length);
		assertToken(LeftDoubleAngle, 0, 2, tokens[0]);
		assertToken(RightDoubleAngle, 2, 4, tokens[1]);
		assertToken(EndOfFile, 4, 4, tokens[2]);
	}

	/** `<<<<`は`<<`が2つ（最長一致で前から2バイトずつ）。 */
	function testDoubleAnglesInARow() {
		final tokens = lexAll(Bytes.ofString("<<<<>>>>"));
		Assert.equals(5, tokens.length);
		assertToken(LeftDoubleAngle, 0, 2, tokens[0]);
		assertToken(LeftDoubleAngle, 2, 4, tokens[1]);
		assertToken(RightDoubleAngle, 4, 6, tokens[2]);
		assertToken(RightDoubleAngle, 6, 8, tokens[3]);
	}

	/** 単独の`>`は1バイトのUnknown（入力の末尾）。 */
	function testLoneRightAngleAtEndOfInput() {
		final tokens = lexAll(Bytes.ofString(">"));
		Assert.equals(2, tokens.length);
		assertToken(Unknown, 0, 1, tokens[0]);
		assertToken(EndOfFile, 1, 1, tokens[1]);
	}

	/** 間に空白がある`> >`は、`>>`にならない。 */
	function testRightAnglesSeparatedBySpace() {
		final tokens = lexAll(Bytes.ofString("> >"));
		Assert.equals(4, tokens.length);
		assertToken(Unknown, 0, 1, tokens[0]);
		assertToken(Whitespace, 1, 2, tokens[1]);
		assertToken(Unknown, 2, 3, tokens[2]);
	}

	/** `>>>`は`>>`と単独の`>`。 */
	function testThreeRightAngles() {
		final tokens = lexAll(Bytes.ofString(">>>"));
		Assert.equals(3, tokens.length);
		assertToken(RightDoubleAngle, 0, 2, tokens[0]);
		assertToken(Unknown, 2, 3, tokens[1]);
	}

	/** `><`は`<<`にならない。`>`はUnknownで、`<`は次のトークンの先頭になる。 */
	function testRightAngleThenLeftAngle() {
		final tokens = lexAll(Bytes.ofString("><"));
		assertToken(Unknown, 0, 1, tokens[0]);
		// `<`単独の種類はM1-4で変わるので、位置だけを見る
		Assert.equals(1, tokens[1].start);
	}

	/** 範囲の終端（`end`）が`>>`の間にあれば、範囲外を見ずに単独の`>`（Unknown）になる。 */
	function testRightDoubleAngleCutByRangeEnd() {
		final tokens = lexAll(Bytes.ofString(">>"), {end: 1});
		Assert.equals(2, tokens.length);
		assertToken(Unknown, 0, 1, tokens[0]);
		assertToken(EndOfFile, 1, 1, tokens[1]);
	}

	/** 範囲の終端（`end`）が`<<`の間にあれば、範囲外を見ない（`<<`にならない）。 */
	function testLeftDoubleAngleCutByRangeEnd() {
		final tokens = lexAll(Bytes.ofString("<<"), {end: 1});
		Assert.equals(2, tokens.length);
		// `<`単独の種類はM1-4で変わるので、`<<`にならず1バイトで終わることだけを見る
		Assert.notEquals(LeftDoubleAngle, tokens[0].kind);
		Assert.equals(0, tokens[0].start);
		Assert.equals(1, tokens[0].end);
	}

	/** 単独の`)`は1バイトのUnknown（基本設計4.2節）。 */
	function testLoneRightParen() {
		final tokens = lexAll(Bytes.ofString("))"));
		Assert.equals(3, tokens.length);
		assertToken(Unknown, 0, 1, tokens[0]);
		assertToken(Unknown, 1, 2, tokens[1]);
		assertToken(EndOfFile, 2, 2, tokens[2]);
	}

	/** 空白をはさんだ辞書・配列の区切り。 */
	function testDelimitersWithWhitespace() {
		final tokens = lexAll(Bytes.ofString("<< [ ] >>\n"));
		Assert.equals(9, tokens.length);
		assertToken(LeftDoubleAngle, 0, 2, tokens[0]);
		assertToken(Whitespace, 2, 3, tokens[1]);
		assertToken(LeftBracket, 3, 4, tokens[2]);
		assertToken(Whitespace, 4, 5, tokens[3]);
		assertToken(RightBracket, 5, 6, tokens[4]);
		assertToken(Whitespace, 6, 7, tokens[5]);
		assertToken(RightDoubleAngle, 7, 9, tokens[6]);
		assertToken(Whitespace, 9, 10, tokens[7]);
		assertToken(EndOfFile, 10, 10, tokens[8]);
	}
}
