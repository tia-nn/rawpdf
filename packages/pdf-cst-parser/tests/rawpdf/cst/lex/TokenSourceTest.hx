package rawpdf.cst.lex;

import haxe.Exception;
import haxe.io.Bytes;
import rawpdf.cst.lex.TokenSource.CookedToken;
import rawpdf.cst.syntax.SyntaxKind;
import rawpdf.cst.syntax.TokenFlags;
import utest.Assert;

/** 期待するトリビア1つ。 */
private typedef ExpectedTrivia = {
	final kind:SyntaxKind;
	final length:Int;
}

/** 期待する`CookedToken`1つ。`flags`を省略すると`NONE`を期待する。 */
private typedef ExpectedCooked = {
	final kind:SyntaxKind;
	final textLength:Int;
	final trivia:Array<ExpectedTrivia>;
	final ?flags:TokenFlags;
}

/** `next`で`EndOfFile`まで読み、`tokens`と突き合わせるケース。 */
private typedef CookCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final input:Bytes;
	final ?start:Int;
	final ?end:Int;

	/** 先頭から順に期待するトークン（`EndOfFile`も含める）。 */
	final tokens:Array<ExpectedCooked>;
}

/** `advance`回`next`を呼んだ後の`peek(n)`を確かめるケース。 */
private typedef PeekCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final input:Bytes;
	final advance:Int;
	final n:Int;
	final expected:ExpectedCooked;
}

/** `advance`回`next`を呼んだ後の、`Bool`を返す判定メソッドの結果を確かめるケース。 */
private typedef BoolCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final input:Bytes;
	final ?start:Int;
	final ?end:Int;
	final ?advance:Int;
	final expected:Bool;
}

/** 例外を投げるかどうかを確かめるケース（`LexerTest`の`ConstructCase`と同じ形）。 */
private typedef ThrowCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final run:() -> Void;
	final throws:Bool;
}

/**
	TokenSourceのテスト。根拠は`TokenSource`・`CookedToken`のpublicなメンバーのdocコメントと、
	トークンの切り方についてはLexerリファレンス（`docs/reference/lexer.md`）。
**/
class TokenSourceTest extends utest.Test {
	/** 無限ループで止まらないようにするための、1回の読み取りで読むトークン数の上限。 */
	static inline final MAX_TOKENS = 10000;

	// テーブルを短く書くための補助

	static inline function str(s:String) {
		return Bytes.ofString(s);
	}

	static function bytesOf(values:Array<Int>) {
		final bytes = Bytes.alloc(values.length);
		for (i => v in values) {
			bytes.set(i, v);
		}
		return bytes;
	}

	/** `s`の後ろに`count`個の`byte`を並べたバイト列。 */
	static function padded(s:String, byte:Int, count:Int) {
		final head = Bytes.ofString(s);
		final bytes = Bytes.alloc(head.length + count);
		bytes.blit(0, head, 0, head.length);
		bytes.fill(head.length, count, byte);
		return bytes;
	}

	static inline function ws(length:Int):ExpectedTrivia {
		return {kind: Whitespace, length: length};
	}

	static inline function cm(length:Int):ExpectedTrivia {
		return {kind: Comment, length: length};
	}

	/** 実トークン。`trivia`を省略するとトリビア無し、`flags`を省略すると`NONE`を期待する。 */
	static function ct(kind:SyntaxKind, textLength:Int, ?trivia:Array<ExpectedTrivia>, ?flags:TokenFlags):ExpectedCooked {
		return {
			kind: kind,
			textLength: textLength,
			trivia: trivia ?? [],
			flags: flags
		};
	}

	/** 幅0の`EndOfFile`。 */
	static function eof(?trivia:Array<ExpectedTrivia>):ExpectedCooked {
		return ct(EndOfFile, 0, trivia);
	}

	// 実行と比較

	static function sourceOf(input:Bytes, ?start:Int, ?end:Int) {
		return new TokenSource(new Lexer(input, {start: start, end: end}));
	}

	static function advanced(input:Bytes, ?start:Int, ?end:Int, ?advance:Int) {
		final source = sourceOf(input, start, end);
		for (_ in 0...(advance ?? 0)) {
			source.next();
		}
		return source;
	}

	static function checkCooked(expected:ExpectedCooked, actual:CookedToken, at:String) {
		Assert.equals(expected.kind, actual.kind, '$at.kind');
		Assert.equals(expected.textLength, actual.textLength, '$at.textLength');
		Assert.equals(expected.flags ?? TokenFlags.NONE, actual.flags, '$at.flags');
		Assert.equals(expected.trivia.length, actual.trivia.length, '$at.trivia.length');
		for (i => t in expected.trivia) {
			if (i >= actual.trivia.length) {
				break;
			}
			Assert.equals(t.kind, actual.trivia[i].kind, '$at.trivia[$i].kind');
			Assert.equals(t.length, actual.trivia[i].length, '$at.trivia[$i].length');
		}
	}

	/** `EndOfFile`までのトークンをすべて読む（`EndOfFile`自身も含む）。 */
	static function readAll(source:TokenSource):Array<CookedToken> {
		final tokens = [];
		for (_ in 0...MAX_TOKENS) {
			final token = source.next();
			tokens.push(token);
			if (token.kind == EndOfFile) {
				return tokens;
			}
		}
		throw 'EndOfFile was not returned within $MAX_TOKENS tokens';
	}

	/**
		トークン列を比べる。あわせて、トリビアと本体の幅の合計が読んだ範囲の長さに等しいことを確かめる
		（[TokenSourceのdocコメント] トリビアはすべて直後の実トークンか`EndOfFile`に付くので、どのバイトも落ちず、二重にも数えられない）。
	**/
	static function checkCook(c:CookCase) {
		final actual = readAll(sourceOf(c.input, c.start, c.end));

		Assert.equals(c.tokens.length, actual.length, '${c.name}: token count');
		for (i => expected in c.tokens) {
			if (i >= actual.length) {
				Assert.fail('${c.name}: tokens[$i] is missing');
				continue;
			}
			checkCooked(expected, actual[i], '${c.name}: tokens[$i]');
		}

		var width = 0;
		for (token in actual) {
			for (t in token.trivia) {
				width += t.length;
			}
			width += token.textLength;
		}
		final rangeLength = (c.end ?? c.input.length) - (c.start ?? 0);
		Assert.equals(rangeLength, width, '${c.name}: total width');
	}

	static function checkBool(cases:Array<BoolCase>, judge:TokenSource->Bool) {
		for (c in cases) {
			final source = advanced(c.input, c.start, c.end, c.advance);
			Assert.equals(c.expected, judge(source), c.name);
		}
	}

	static function checkThrows(cases:Array<ThrowCase>) {
		for (c in cases) {
			if (c.throws) {
				Assert.raises(c.run, Exception, c.name);
			} else {
				try {
					c.run();
					Assert.pass(c.name);
				} catch (e:Exception) {
					Assert.fail('${c.name}: unexpected exception: ${e.message}');
				}
			}
		}
	}

	// トリビアの吸着（TokenSource・CookedTokenのdocコメント）
	static final COOK_CASES:Array<CookCase> = [
		{
			name: "空の入力は、トリビアの無いEndOfFileだけ",
			input: str(""),
			tokens: [eof()]
		},
		{
			name: "トリビアが無ければ、どのトークンのtriviaも空",
			input: str("[]"),
			tokens: [ct(LeftBracket, 1), ct(RightBracket, 1), eof()]
		},
		{
			name: "先頭のトリビアは、最初の実トークンに付く",
			input: str(" 1"),
			tokens: [ct(Integer, 1, [ws(1)]), eof()]
		},
		{
			name: "トークンの間のトリビアは、後ろのトークンに付く（前のトークンには付かない）",
			input: str("1 0 R"),
			tokens: [ct(Integer, 1), ct(Integer, 1, [ws(1)]), ct(KwR, 1, [ws(1)]), eof()]
		},
		{
			name: "続いたトリビアは、ファイルの中の順のまま1つのトークンに付く",
			input: str(" %a\n1"),
			tokens: [ct(Integer, 1, [ws(1), cm(2), ws(1)]), eof()]
		},
		{
			name: "ファイル末尾のトリビアは、EndOfFileに付く",
			input: str("1 %x"),
			tokens: [ct(Integer, 1), eof([ws(1), cm(2)])]
		},
		{
			name: "トリビアだけの入力は、すべてEndOfFileに付く",
			input: str("  %%EOF\n"),
			tokens: [eof([ws(2), cm(5), ws(1)])]
		},
		{
			name: "textLengthはトリビアを含まない",
			input: str("  /Type"),
			tokens: [ct(Name, 5, [ws(2)]), eof()]
		},
		{
			name: "Lexerが付けたフラグはそのまま写る（閉じないLiteralStringのUNTERMINATED）",
			input: str(" (abc"),
			tokens: [ct(LiteralString, 4, [ws(1)], TokenFlags.UNTERMINATED), eof()]
		},
		{
			name: "HeaderMarkerはトリビアではなく実トークン",
			input: str("%PDF-1.7\n%a\n"),
			tokens: [ct(HeaderMarker, 8), eof([ws(1), cm(2), ws(1)])]
		},
		{
			name: "0x80以上のバイトはUnknown（実トークン）として、前のトリビアを受け取る",
			input: bytesOf([0x20, 0x80]),
			tokens: [ct(Unknown, 1, [ws(1)]), eof()]
		},
		{
			name: "Lexerの範囲の開始（start）から読む",
			input: str("ab 1 c"),
			start: 2,
			end: 4,
			tokens: [ct(Integer, 1, [ws(1)]), eof()]
		},
		{
			name: "Lexerの範囲の終端（end）がトリビアの途中なら、そこまでのトリビアがEndOfFileに付く",
			input: str("1    2"),
			end: 3,
			tokens: [ct(Integer, 1), eof([ws(2)])]
		},
		{
			name: "長いトリビア（空白100000バイト）も1つのトリビアとして付く",
			input: padded("", 0x20, 100000),
			tokens: [eof([ws(100000)])]
		},
	];

	/**
		[TokenSourceのdocコメント] トリビアはすべて直後の実トークンの`trivia`に付き、ファイル末尾のトリビアは幅0の`EndOfFile`に付く。
		[CookedToken.trivia・textLength・flagsのdocコメント] トリビアはファイルの中の順に並び、無ければ空。`textLength`はトリビアを含まない。フラグはLexerが付けたもの。
		[TokenSource.newのdocコメント] `lexer`の現在位置（範囲の開始）から読む。
		トークンの切り方と種類は[Lexerリファレンス1章・3章]。
		各ケースで、トリビアと本体の幅の合計が読んだ範囲の長さに等しいことも確かめる（`checkCook`）。
		観点:
		-         正常: トリビア無し、先頭・間・末尾のトリビア、WhitespaceとCommentの混在
		-         境目: トリビアは後ろのトークンに付き前には付かない、HeaderMarkerはトリビアではない
		  （StreamBodyのケースは、Lexerのstream本体モード（WBS M3-2）ができてから足す）
		-     範囲の端: トリビアだけの入力、末尾のトリビア、Lexerの`start`・`end`（`end`がトリビアの途中）
		-     空・最小: 空の入力、1バイトのトークン
		- 不正なバイト: 0x80（Unknownとして実トークンになる）
		-       大きさ: 100000バイトのトリビア、トリビアが100000個（testManyTrivia）
		-   仕様の細則: `textLength`はトリビアを含まない、フラグがそのまま写る、何度読んでもEndOfFile（testEndOfFileRepeats）
	**/
	function testCook() {
		for (c in COOK_CASES) {
			checkCook(c);
		}
	}

	/** [TokenSourceのdocコメント] トリビアがいくつ続いても、すべて直後の実トークンに付く。観点の表はtestCook。 */
	function testManyTrivia() {
		// "%\n"を50000回: Comment（1バイト）とWhitespace（1バイト）が交互に100000個並び、最後に"1"
		final count = 50000;
		final buf = new StringBuf();
		for (_ in 0...count) {
			buf.add("%\n");
		}
		buf.add("1");
		final source = sourceOf(str(buf.toString()));
		final first = source.next();
		Assert.equals(Integer, first.kind, "最後の1がIntegerになる");
		Assert.equals(count * 2, first.trivia.length, "トリビアが100000個すべて付く");
		Assert.equals(EndOfFile, source.next().kind, "その後ろはEndOfFile");
	}

	/** [TokenSource.nextのdocコメント] ファイル末尾では`EndOfFile`を返し続け、末尾のトリビアは最初の`EndOfFile`だけに付く（2回目以降の`trivia`は空）。観点の表はtestCook。 */
	function testEndOfFileRepeats() {
		// 末尾に空白1バイトのトリビアがある入力
		final source = sourceOf(str("1 "));
		checkCooked(ct(Integer, 1), source.next(), "最初のトークンは1（Integer）");
		checkCooked(eof([ws(1)]), source.next(), "EndOfFileの1回目: 末尾のトリビアが付く");
		for (i in 2...6) {
			checkCooked(eof(), source.next(), 'EndOfFileの${i}回目: 幅0で、triviaは空');
		}
	}

	// 先読み（TokenSource.peekのdocコメント）
	static final PEEK_CASES:Array<PeekCase> = [
		{
			name: "読み始めのpeek(0)は先頭のトークン",
			input: str("1 0 R"),
			advance: 0,
			n: 0,
			expected: ct(Integer, 1)
		},
		{
			name: "読み始めのpeek(1)は2つ目のトークン（トリビアを読み飛ばす）",
			input: str("1 0 R"),
			advance: 0,
			n: 1,
			expected: ct(Integer, 1, [ws(1)])
		},
		{
			name: "読み始めのpeek(2)は3つ目のトークン",
			input: str("1 0 R"),
			advance: 0,
			n: 2,
			expected: ct(KwR, 1, [ws(1)])
		},
		{
			name: "nextを1回呼んだ後のpeek(0)は2つ目のトークン",
			input: str("1 0 R"),
			advance: 1,
			n: 0,
			expected: ct(Integer, 1, [ws(1)])
		},
		{
			name: "nextを1回呼んだ後のpeek(2)はEndOfFile",
			input: str("1 0 R"),
			advance: 1,
			n: 2,
			expected: eof()
		},
		{
			name: "nextを3回呼んだ後のpeek(2)は6つ目のトークン（先読みが一周した後）",
			input: str("1 2 3 4 5 /F"),
			advance: 3,
			n: 2,
			expected: ct(Name, 2, [ws(1)])
		},
		{
			name: "nextを4回呼んだ後のpeek(1)は6つ目のトークン（先読みが一周した後）",
			input: str("1 2 3 4 5 /F"),
			advance: 4,
			n: 1,
			expected: ct(Name, 2, [ws(1)])
		},
		{
			name: "EndOfFileより先のpeek(1)はEndOfFile",
			input: str("1"),
			advance: 0,
			n: 1,
			expected: eof()
		},
		{
			name: "EndOfFileより先のpeek(2)はEndOfFile",
			input: str("1"),
			advance: 0,
			n: 2,
			expected: eof()
		},
		{
			name: "空の入力のpeek(0)はEndOfFile",
			input: str(""),
			advance: 0,
			n: 0,
			expected: eof()
		},
		{
			name: "末尾のトリビアはpeekで見たEndOfFileにも付いている",
			input: str("1 %x"),
			advance: 0,
			n: 1,
			expected: eof([ws(1), cm(2)])
		},
		{
			name: "末尾のトリビアがあっても、その先のEndOfFile（peek(2)）のtriviaは空",
			input: str("1 %x"),
			advance: 0,
			n: 2,
			expected: eof()
		},
	];

	/**
		[TokenSource.peekのdocコメント] トリビアを読み飛ばして`n`個先の実トークンを返す。`n`は0〜2で、0が次に`next`で返るトークン。
		`EndOfFile`より先を見ると`EndOfFile`が返る。範囲外の`n`は例外。
		観点:
		-         正常: 読み始めの`peek(0..2)`、`next`の後の`peek`
		-         境目: `n` = 0と2（範囲内の端）、-1と3（例外。testPeekRange）
		-     範囲の端: `EndOfFile`より先を見る、`next`を3回以上呼んだ後（先読みが一周した後）
		-     空・最小: 空の入力、1トークンの入力
		- 不正なバイト: 該当なし（トークンの中身によらない。testCookで見る）
		-       大きさ: 該当なし（先読みは最大3つ）
		-   仕様の細則: 消費しない（testPeekDoesNotConsume）、引数の省略は`peek(0)`（testPeekDefault）
	**/
	function testPeek() {
		for (c in PEEK_CASES) {
			final source = advanced(c.input, null, null, c.advance);
			checkCooked(c.expected, source.peek(c.n), c.name);
		}
	}

	/** [TokenSource.peekのdocコメント] `n`が0〜2の範囲外なら例外。観点の表はtestPeek。 */
	function testPeekRange() {
		final source = sourceOf(str("1 0 R"));
		checkThrows([
			{name: "peek(0) → 例外にならない", run: () -> source.peek(0), throws: false},
			{name: "peek(2) → 例外にならない", run: () -> source.peek(2), throws: false},
			{name: "peek(-1) → 例外（0未満）", run: () -> source.peek(-1), throws: true},
			{name: "peek(3) → 例外（2より大きい）", run: () -> source.peek(3), throws: true},
		]);
	}

	/** [TokenSource.peekのdocコメント] peekは消費しない。[TokenSource.nextのdocコメント] nextは`peek(0)`と同じものを返す。観点の表はtestPeek。 */
	function testPeekDoesNotConsume() {
		final source = sourceOf(str("1 0 R"));
		source.peek(0);
		source.peek(1);
		source.peek(2);
		checkCooked(ct(Integer, 1), source.peek(0), "peekを何度呼んでもpeek(0)は先頭のまま");
		checkCooked(ct(Integer, 1), source.next(), "peekの後のnextは先頭のトークン");
		checkCooked(ct(Integer, 1, [ws(1)]), source.next(), "その次のnextは2つ目のトークン");
	}

	/** [TokenSource.peekのdocコメント] `n`を省略すると0（次に`next`で返るトークン）。観点の表はtestPeek。 */
	function testPeekDefault() {
		final source = sourceOf(str("1 0 R"));
		source.next();
		checkCooked(ct(Integer, 1, [ws(1)]), source.peek(), "nextを1回呼んだ後のpeek()は2つ目のトークン");
	}

	// Integer Integer obj（TokenSource.atObjHeaderのdocコメント）
	static final OBJ_HEADER_CASES:Array<BoolCase> = [
		{name: "1 0 obj → true", input: str("1 0 obj"), expected: true},
		{name: "-1 0 obj → true（-1もInteger）", input: str("-1 0 obj"), expected: true},
		{name: "間に改行とコメントがあっても true", input: str("1 %c\n0\r\n\nobj"), expected: true},
		{
			name: "前のトークンをnextで読んだ後なら true",
			input: str("x 1 0 obj"),
			advance: 1,
			expected: true
		},
		{name: "前のトークンを読む前は false（peek(0)がx）", input: str("x 1 0 obj"), expected: false},
		{name: "1 0 R → false", input: str("1 0 R"), expected: false},
		{name: "1.0 0 obj → false（1.0はReal）", input: str("1.0 0 obj"), expected: false},
		{name: "1 0 Obj → false（大文字・小文字を区別する。ObjはUnknown）", input: str("1 0 Obj"), expected: false},
		{name: "1 0 objx → false（objxはUnknown）", input: str("1 0 objx"), expected: false},
		{name: "1 obj → false（Integerが1つ）", input: str("1 obj"), expected: false},
		{name: "1 0 で入力が終わる → false（3つ目がEndOfFile）", input: str("1 0"), expected: false},
		{
			name: "Lexerの範囲の終端がobjの前 → false",
			input: str("1 0 obj"),
			end: 4,
			expected: false
		},
		{name: "空の入力 → false", input: str(""), expected: false},
	];

	/**
		[TokenSource.atObjHeaderのdocコメント] `peek(0..2)`が`Integer Integer obj`の並びか。間のトリビアは問わない。
		トークンの種類は[Lexerリファレンス1章・2章]。
		観点:
		-         正常: `1 0 obj`、`next`の後
		-         境目: 3つ目が`R`、1つ目が`Real`、Integerが1つ
		-     範囲の端: 2トークンで入力が終わる、Lexerの`end`が`obj`の前
		-     空・最小: 空の入力
		- 不正なバイト: 該当なし（Unknownになる並びは「仕様の細則」で見る）
		-       大きさ: 該当なし（3トークンだけを見る）
		-   仕様の細則: 間のトリビアは問わない、大文字・小文字の区別、`objx`はキーワードでない、符号付きのInteger
	**/
	function testAtObjHeader() {
		checkBool(OBJ_HEADER_CASES, s -> s.atObjHeader());
	}

	// Integer Integer R（TokenSource.atReferenceのdocコメント）
	static final REFERENCE_CASES:Array<BoolCase> = [
		{name: "1 0 R → true", input: str("1 0 R"), expected: true},
		{name: "間に改行とコメントがあっても true", input: str("1\n%c\n0 R"), expected: true},
		{
			name: "前のトークンをnextで読んだ後なら true",
			input: str("/K 1 0 R"),
			advance: 1,
			expected: true
		},
		{name: "1 0 obj → false", input: str("1 0 obj"), expected: false},
		{name: "1 0 r → false（大文字・小文字を区別する。rはUnknown）", input: str("1 0 r"), expected: false},
		{name: "1 0 RR → false（RRはUnknown）", input: str("1 0 RR"), expected: false},
		{name: "1 R → false（Integerが1つ）", input: str("1 R"), expected: false},
		{name: "1 0.5 R → false（0.5はReal）", input: str("1 0.5 R"), expected: false},
		{name: "1 0 で入力が終わる → false", input: str("1 0"), expected: false},
		{name: "空の入力 → false", input: str(""), expected: false},
	];

	/**
		[TokenSource.atReferenceのdocコメント] `peek(0..2)`が`Integer Integer R`の並びか。間のトリビアは問わない。
		トークンの種類は[Lexerリファレンス1章・2章]。
		観点:
		-         正常: `1 0 R`、`next`の後
		-         境目: 3つ目が`obj`、2つ目が`Real`、Integerが1つ
		-     範囲の端: 2トークンで入力が終わる
		-     空・最小: 空の入力
		- 不正なバイト: 該当なし（Unknownになる並びは「仕様の細則」で見る）
		-       大きさ: 該当なし（3トークンだけを見る）
		-   仕様の細則: 間のトリビアは問わない、大文字・小文字の区別、`RR`はキーワードでない
	**/
	function testAtReference() {
		checkBool(REFERENCE_CASES, s -> s.atReference());
	}

	// %%EOFの形のComment（TokenSource.hasEofCommentInTriviaのdocコメント）
	static final EOF_COMMENT_CASES:Array<BoolCase> = [
		{name: "%%EOFちょうど（EndOfFileのトリビア） → true", input: str("%%EOF"), expected: true},
		{name: "%%EOFの後ろに改行（LF） → true", input: str("%%EOF\n"), expected: true},
		{name: "%%EOFの後ろに改行（CRLF） → true", input: str("%%EOF\r\n"), expected: true},
		{
			name: "%%EOFの後ろにSP・HT・NUL・FF（コメントに入るwhitespace4種） → true",
			input: bytesOf([0x25, 0x25, 0x45, 0x4F, 0x46, 0x20, 0x09, 0x00, 0x0C, 0x0A]),
			expected: true
		},
		{name: "次の実トークンに付いた%%EOF → true", input: str("%%EOF\n1"), expected: true},
		{name: "トリビアの先頭が%%EOFで、後ろに別のトリビアが続く → true", input: str("%%EOF\n%a\n1"), expected: true},
		{name: "トリビアの途中に%%EOF → true", input: str("\n%%EOF\n1"), expected: true},
		{name: "ほかのコメントの後ろの%%EOF → true", input: str("%a\n%b\n%%EOF\n"), expected: true},
		{
			name: "行の途中（トークンの後ろ）の%%EOF → true（行のどこにあるかは問わない）",
			input: str("1 %%EOF"),
			advance: 1,
			expected: true
		},
		{name: "%%EOFの後ろに空白でないバイト（x） → false", input: str("%%EOFx"), expected: false},
		{name: "%%EOFの後ろに空白とx → false", input: str("%%EOF x"), expected: false},
		{name: "%%EOF%%EOF → false（残りが空白でない）", input: str("%%EOF%%EOF"), expected: false},
		{name: "%%EOFの後ろに0x80 → false", input: bytesOf([0x25, 0x25, 0x45, 0x4F, 0x46, 0x80]), expected: false},
		{name: "%%EO → false（短い）", input: str("%%EO"), expected: false},
		{name: "%%eof → false（大文字・小文字を区別する）", input: str("%%eof"), expected: false},
		{name: "%%%EOF → false（%%EOFで始まらない）", input: str("%%%EOF"), expected: false},
		{name: "%%PDF → false", input: str("%%PDF\n1"), expected: false},
		{name: "普通のコメントだけ → false", input: str("%a\n1"), expected: false},
		{name: "トリビアが無い → false", input: str("1"), expected: false},
		{name: "空の入力 → false", input: str(""), expected: false},
		{name: "%%EOFがpeek(1)のトリビアにある → false（peek(0)のトリビアだけを見る）", input: str("1\n%%EOF"), expected: false},
		{
			name: "%%EOFの付いたトークンを読んだ後 → false",
			input: str("%%EOF\n1 2"),
			advance: 1,
			expected: false
		},
		{name: "%PDF-1.7（HeaderMarker）はトリビアでない → false", input: str("%PDF-1.7\n"), expected: false},
		{
			name: "Lexerの範囲の終端で切れて%%EOFちょうどになる → true",
			input: str("%%EOFx"),
			end: 5,
			expected: true
		},
		{
			name: "Lexerの範囲の開始から読んだ%%EOF → true",
			input: str("x%%EOF"),
			start: 1,
			expected: true
		},
		{name: "%%EOFの後ろに空白が100000バイト → true", input: padded("%%EOF", 0x20, 100000), expected: true},
	];

	/**
		[TokenSource.hasEofCommentInTriviaのdocコメント] `peek(0)`のトリビアに、`%%EOF`で始まり残りのバイトがすべてwhitespace（6種）であるCommentが含まれるか。
		`%%EOF`ちょうども含む。Commentが行のどこにあるかは問わない。
		Commentの範囲（行末の手前まで）とwhitespace 6種は[Lexerリファレンス0章・1章]。
		観点:
		-         正常: `%%EOF`ちょうど、後ろに改行、EndOfFileと実トークンのどちらに付いても
		-         境目: 後ろに空白でないバイト、`%%EO`（短い）、`%%%EOF`、`%%EOF%%EOF`
		-     範囲の端: トリビアの先頭・途中・末尾の位置、Lexerの`end`で切れる、Lexerの`start`から読む、peek(1)のトリビアは見ない
		-     空・最小: 空の入力、トリビアの無いトークン
		- 不正なバイト: `%%EOF`の後ろに0x80
		-       大きさ: 後ろに空白100000バイト
		-   仕様の細則: コメントに入るwhitespace4種（SP・HT・NUL・FF）、大文字・小文字の区別、行の途中でもよい、HeaderMarkerはトリビアでない
		  （stream本体の中の`%%EOF`のケースは、Lexerのstream本体モード（WBS M3-2）ができてから足す）
	**/
	function testHasEofCommentInTrivia() {
		checkBool(EOF_COMMENT_CASES, s -> s.hasEofCommentInTrivia());
	}
}
