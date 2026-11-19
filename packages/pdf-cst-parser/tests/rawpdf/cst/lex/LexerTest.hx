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

	// Name（基本設計4.2節、Lexer仕様書1章）

	/** `/`から、regular byteが続く限りが1つのName。 */
	function testName() {
		final tokens = lexAll(Bytes.ofString("/Type"));
		Assert.equals(2, tokens.length);
		assertToken(Name, 0, 5, tokens[0]);
		assertToken(EndOfFile, 5, 5, tokens[1]);
	}

	/** `/`だけの入力は、空のName（入力の末尾）。 */
	function testEmptyNameAtEndOfInput() {
		final tokens = lexAll(Bytes.ofString("/"));
		Assert.equals(2, tokens.length);
		assertToken(Name, 0, 1, tokens[0]);
		assertToken(EndOfFile, 1, 1, tokens[1]);
	}

	/** `/`の直後が空白でも、空のNameになる。 */
	function testEmptyNameBeforeWhitespace() {
		final tokens = lexAll(Bytes.ofString("/ "));
		Assert.equals(3, tokens.length);
		assertToken(Name, 0, 1, tokens[0]);
		assertToken(Whitespace, 1, 2, tokens[1]);
	}

	/** 空白6種のどれでも、Nameはその手前で終わる。 */
	function testNameStopsBeforeEachWhitespace() {
		for (b in WHITESPACES) {
			final tokens = lexAll(bytesOf(["/".code, "A".code, b]));
			Assert.equals(3, tokens.length, 'byte=$b');
			assertToken(Name, 0, 2, tokens[0]);
			assertToken(Whitespace, 2, 3, tokens[1]);
		}
	}

	/** delimiter 10種のどれでも、Nameはその手前で終わる。 */
	function testNameStopsBeforeEachDelimiter() {
		for (d in ["(", ")", "<", ">", "[", "]", "{", "}", "/", "%"]) {
			final tokens = lexAll(Bytes.ofString("/A" + d));
			assertToken(Name, 0, 2, tokens[0]);
			// delimiterの種類は別のテストで見るので、位置だけを見る
			Assert.equals(2, tokens[1].start, d);
		}
	}

	/** 空白をはさまない`/A/B`は、2つのName。 */
	function testNamesInARow() {
		final tokens = lexAll(Bytes.ofString("/A/B"));
		Assert.equals(3, tokens.length);
		assertToken(Name, 0, 2, tokens[0]);
		assertToken(Name, 2, 4, tokens[1]);
		assertToken(EndOfFile, 4, 4, tokens[2]);
	}

	/** `//`は空のNameが2つ。 */
	function testEmptyNamesInARow() {
		final tokens = lexAll(Bytes.ofString("//"));
		Assert.equals(3, tokens.length);
		assertToken(Name, 0, 1, tokens[0]);
		assertToken(Name, 1, 2, tokens[1]);
	}

	/** 辞書の中のName。`<<`・`>>`との境目で切れる。 */
	function testNamesInDictionary() {
		final tokens = lexAll(Bytes.ofString("<</Type/Page>>"));
		Assert.equals(5, tokens.length);
		assertToken(LeftDoubleAngle, 0, 2, tokens[0]);
		assertToken(Name, 2, 7, tokens[1]);
		assertToken(Name, 7, 12, tokens[2]);
		assertToken(RightDoubleAngle, 12, 14, tokens[3]);
	}

	/** 数字やキーワードと同じ並びでも、`/`の後ろはNameの一部（数値・キーワードに分けない）。 */
	function testNameLooksLikeNumberOrKeyword() {
		for (s in ["/00hoge", "/1", "/-1.5", "/R", "/n", "/obj", "/endstream"]) {
			final tokens = lexAll(Bytes.ofString(s));
			Assert.equals(2, tokens.length, s);
			assertToken(Name, 0, s.length, tokens[0]);
		}
	}

	/** `#xx`は解釈せず、`#` `-` `.`もregular byteとしてNameに含める。 */
	function testNameWithHashAndPunctuation() {
		final tokens = lexAll(Bytes.ofString("/A#20B-c.d"));
		Assert.equals(2, tokens.length);
		assertToken(Name, 0, 10, tokens[0]);
	}

	/** 0x80以上のバイト（UTF-8として不正な並びを含む）も、例外にならずNameに含まれる。 */
	function testNameWithHighBytes() {
		final tokens = lexAll(bytesOf(["/".code, 0x80, 0xFF, 0xC3, 0xE3]));
		Assert.equals(2, tokens.length);
		assertToken(Name, 0, 5, tokens[0]);
		assertToken(EndOfFile, 5, 5, tokens[1]);
	}

	/** 範囲の終端（`end`）がNameの途中にあれば、そこで止まる。 */
	function testNameCutByRangeEnd() {
		final tokens = lexAll(Bytes.ofString("/Type"), {end: 3});
		Assert.equals(2, tokens.length);
		assertToken(Name, 0, 3, tokens[0]);
		assertToken(EndOfFile, 3, 3, tokens[1]);
	}

	/** 範囲の終端（`end`）が`/`の直後にあれば、空のNameになる。 */
	function testEmptyNameCutByRangeEnd() {
		final tokens = lexAll(Bytes.ofString("/Type"), {end: 1});
		Assert.equals(2, tokens.length);
		assertToken(Name, 0, 1, tokens[0]);
		assertToken(EndOfFile, 1, 1, tokens[1]);
	}

	// regular run: 数値・キーワード・Unknown（基本設計4.2節、詳細設計6.2節、Lexer仕様書2章）

	/** 入力全体が1つのregular runとして、`kind`に分類されることを確かめる。 */
	static function assertWholeRun(s:String, kind:SyntaxKind, ?pos:haxe.PosInfos) {
		final tokens = lexAll(Bytes.ofString(s));
		Assert.equals(2, tokens.length, s, pos);
		Assert.equals(kind, tokens[0].kind, s, pos);
		Assert.equals(0, tokens[0].start, s, pos);
		Assert.equals(s.length, tokens[0].end, s, pos);
		Assert.isTrue(tokens[0].flags.isNone(), s, pos);
	}

	/** 符号は1個以下、数字が1個以上、`.`が無ければInteger。先頭の`0`も許す。 */
	function testInteger() {
		for (s in ["0", "123", "-12", "+3", "007", "-0", "+0"]) {
			assertWholeRun(s, Integer);
		}
	}

	/** `.`が1個あればReal。`.`は先頭・末尾・途中のどこでもよい（ISO 32000-2 7.3.3節）。 */
	function testReal() {
		for (s in ["3.14", "-3.62", "+123.6", "4.", "-.002", ".5", "+.5", "-.5", "0.0"]) {
			assertWholeRun(s, Real);
		}
	}

	/** 数字を1つも含まない列は数値にならない。 */
	function testSignOrDotOnlyIsUnknown() {
		for (s in ["+", "-", ".", "+.", "-.", ".."]) {
			assertWholeRun(s, Unknown);
		}
	}

	/** 符号が2個以上・途中にある列、`.`が2個以上の列は、分けずにrun全体が1つのUnknown。 */
	function testMalformedNumberIsOneUnknown() {
		for (s in ["--1", "+-1", "1-2", "1+", "12.34.56", "1..2", "1.2."]) {
			assertWholeRun(s, Unknown);
		}
	}

	/** 指数表記・基数表記は数値にならない（ISO 32000-2 7.3.3節）。 */
	function testExponentAndRadixAreUnknown() {
		for (s in ["123e5", "6.02E23", "16#FF"]) {
			assertWholeRun(s, Unknown);
		}
	}

	/** 数字の後ろに英字が続く列は、数値とキーワードに分けずにUnknown（最長一致）。 */
	function testNumberFollowedByLettersIsUnknown() {
		for (s in ["123abc", "0R", "1obj"]) {
			assertWholeRun(s, Unknown);
		}
	}

	/** 13種のキーワードは、完全に一致すれば対応するKw*。 */
	function testKeywords() {
		final cases:Array<{s:String, kind:SyntaxKind}> = [
			{s: "R", kind: KwR},
			{s: "n", kind: KwN},
			{s: "f", kind: KwF},
			{s: "obj", kind: KwObj},
			{s: "true", kind: KwTrue},
			{s: "null", kind: KwNull},
			{s: "xref", kind: KwXref},
			{s: "false", kind: KwFalse},
			{s: "endobj", kind: KwEndobj},
			{s: "trailer", kind: KwTrailer},
			{s: "endstream", kind: KwEndstream},
			{s: "startxref", kind: KwStartxref},
		];
		for (c in cases) {
			assertWholeRun(c.s, c.kind);
		}
	}

	/** `stream`はKwStream。直後の本体の扱いはM3-2で変わるので、最初のトークンだけを見る。 */
	function testStreamKeyword() {
		final tokens = lexAll(Bytes.ofString("stream"));
		assertToken(KwStream, 0, 6, tokens[0]);
	}

	/** キーワードは大文字・小文字を区別する。 */
	function testKeywordIsCaseSensitive() {
		for (s in ["r", "N", "F", "Obj", "TRUE", "Null", "Stream", "EndObj"]) {
			assertWholeRun(s, Unknown);
		}
	}

	/** キーワードと長さが1違うだけの列は、キーワードにならない（前方一致で判定していないこと）。 */
	function testKeywordWithExtraOrMissingBytesIsUnknown() {
		for (s in [
			"ob",
			"objx",
			"R0",
			"nn",
			"fals",
			"falsey",
			"endstrea",
			"endstreamX",
			"startxre",
			"trailers"
		]) {
			assertWholeRun(s, Unknown);
		}
	}

	/** 0x80以上のバイトを含むrunも、例外にならずUnknownになる。 */
	function testRegularRunWithHighBytes() {
		final tokens = lexAll(bytesOf(["R".code, 0xFF, 0x80, 0xC3]));
		Assert.equals(2, tokens.length);
		assertToken(Unknown, 0, 4, tokens[0]);
	}

	/** 間接参照`1 0 R`は、Integer・Integer・KwRに分かれる。 */
	function testIndirectReference() {
		final tokens = lexAll(Bytes.ofString("1 0 R"));
		Assert.equals(6, tokens.length);
		assertToken(Integer, 0, 1, tokens[0]);
		assertToken(Whitespace, 1, 2, tokens[1]);
		assertToken(Integer, 2, 3, tokens[2]);
		assertToken(Whitespace, 3, 4, tokens[3]);
		assertToken(KwR, 4, 5, tokens[4]);
	}

	/** regular runはdelimiterの手前で終わる。 */
	function testRegularRunStopsBeforeDelimiter() {
		final tokens = lexAll(Bytes.ofString("obj<<"));
		Assert.equals(3, tokens.length);
		assertToken(KwObj, 0, 3, tokens[0]);
		assertToken(LeftDoubleAngle, 3, 5, tokens[1]);
	}

	/** delimiterと隣り合う数値。 */
	function testNumbersInArray() {
		final tokens = lexAll(Bytes.ofString("[.5 -.5]"));
		Assert.equals(6, tokens.length);
		assertToken(LeftBracket, 0, 1, tokens[0]);
		assertToken(Real, 1, 3, tokens[1]);
		assertToken(Whitespace, 3, 4, tokens[2]);
		assertToken(Real, 4, 7, tokens[3]);
		assertToken(RightBracket, 7, 8, tokens[4]);
	}

	/** オブジェクトの見出し`1 0 obj`と、Nameの直後の数値・キーワード。 */
	function testObjectHeaderAndDictionary() {
		final tokens = lexAll(Bytes.ofString("1 0 obj<</Count 3/Kids[]/X true>>endobj"));
		final kinds = [for (t in tokens) t.kind];
		final expected:Array<SyntaxKind> = [
			Integer,
			Whitespace,
			Integer,
			Whitespace,
			KwObj,
			LeftDoubleAngle,
			Name,
			Whitespace,
			Integer,
			Name,
			LeftBracket,
			RightBracket,
			Name,
			Whitespace,
			KwTrue,
			RightDoubleAngle,
			KwEndobj,
			EndOfFile,
		];
		Assert.same(expected, kinds);
	}

	/** 範囲の終端（`end`）がregular runの途中にあれば、そこで切ってから分類する。 */
	function testRegularRunCutByRangeEnd() {
		final cases:Array<{s:String, end:Int, kind:SyntaxKind}> = [
			{s: "objx", end: 3, kind: KwObj},
			{s: "obj", end: 2, kind: Unknown},
			{s: "123", end: 2, kind: Integer},
			{s: "1.5", end: 2, kind: Real},
			{s: "-5", end: 1, kind: Unknown},
		];
		for (c in cases) {
			final tokens = lexAll(Bytes.ofString(c.s), {end: c.end});
			Assert.equals(2, tokens.length, c.s);
			assertToken(c.kind, 0, c.end, tokens[0]);
			assertToken(EndOfFile, c.end, c.end, tokens[1]);
		}
	}
}
