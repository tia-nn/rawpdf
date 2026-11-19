package rawpdf.cst.lex;

import haxe.Exception;
import haxe.io.Bytes;
import rawpdf.cst.syntax.SyntaxKind;
import rawpdf.cst.syntax.TokenFlags;
import utest.Assert;

/** 期待するトークン1つ。`kind`が`null`なら、種類とフラグは見ずに位置だけを見る。`end`が`null`なら終わりの位置も見ない。 */
typedef ExpectedToken = {
	final ?kind:SyntaxKind;
	final start:Int;
	final ?end:Int;
	final ?flags:TokenFlags;
}

/** テーブルの1行。入力を`EndOfFile`まで字句解析し、`tokens`と突き合わせる。 */
typedef LexCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final input:Bytes;
	final ?start:Int;
	final ?end:Int;

	/** 先頭から順に期待するトークン（`EndOfFile`も含める）。 */
	final tokens:Array<ExpectedToken>;

	/** `true`なら`tokens`の分だけを先頭から比べ、トークンの総数は見ない。後のタスクで振る舞いが変わるトークンが続くときに使う。 */
	final ?prefix:Bool;
}

/** コンストラクタが例外を投げるかどうかを確かめるケース（`GreenNodeTest`の`ConstructCase`と同じ形）。 */
private typedef ConstructCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final make:() -> Void;
	final throws:Bool;
}

/** Lexerのテスト（根拠はLexerリファレンス`docs/reference/lexer.md`）。ケースは節ごとのテーブルにまとめる。 */
class LexerTest extends utest.Test {
	/** 空白6種（Lexerリファレンス0章）。 */
	static final WHITESPACES = [0x00, 0x09, 0x0A, 0x0C, 0x0D, 0x20];

	/** delimiter 10種（Lexerリファレンス0章）。 */
	static final DELIMITERS = ["(", ")", "<", ">", "[", "]", "{", "}", "/", "%"];

	/** 無限ループで止まらないようにするための、1回の字句解析で読むトークン数の上限。 */
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

	/** 0x00が`length`個並んだバイト列。 */
	static function zeros(length:Int) {
		final bytes = Bytes.alloc(length);
		bytes.fill(0, length, 0x00); // allocの初期値はターゲットによって保証されないため、明示的に埋める
		return bytes;
	}

	/** 種類・位置・フラグをすべて見るトークン。`flags`を省略すると`NONE`を期待する。 */
	static function tok(kind:SyntaxKind, start:Int, end:Int, ?flags:TokenFlags):ExpectedToken {
		return {
			kind: kind,
			start: start,
			end: end,
			flags: flags
		};
	}

	/** 位置だけを見るトークン（種類が後のタスクで変わるもの）。 */
	static function anyAt(start:Int, ?end:Int):ExpectedToken {
		return {start: start, end: end};
	}

	/** 入力全体が1つのトークンになり、その後ろが`EndOfFile`であるケース。 */
	static function whole(name:String, input:Bytes, kind:SyntaxKind):LexCase {
		return {
			name: name,
			input: input,
			tokens: [tok(kind, 0, input.length), tok(EndOfFile, input.length, input.length)]
		};
	}

	// 実行と比較

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

	static function check(c:LexCase) {
		final actual = lexAll(c.input, {start: c.start, end: c.end});

		if (!(c.prefix ?? false)) {
			Assert.equals(c.tokens.length, actual.length, '${c.name}: token count');
		}
		for (i => expected in c.tokens) {
			final at = '${c.name}: tokens[$i]';
			if (i >= actual.length) {
				Assert.fail('$at is missing');
				continue;
			}
			final token = actual[i];
			Assert.equals(expected.start, token.start, '$at.start');
			if (expected.end != null) {
				Assert.equals(expected.end, token.end, '$at.end');
			}
			if (expected.kind != null) {
				Assert.equals(expected.kind, token.kind, '$at.kind');
				Assert.equals(expected.flags ?? TokenFlags.NONE, token.flags, '$at.flags');
			}
		}
	}

	/** 節ごとの小さな表をつないで1つの表にする。引数の型が決まっているので、中の配列リテラルも`LexCase`として型付けされる。 */
	static function flatten(groups:Array<Array<LexCase>>):Array<LexCase> {
		return [
			for (g in groups) {
				for (c in g) {
					c;
				}
			}
		];
	}

	static function checkAll(cases:Array<LexCase>) {
		for (c in cases) {
			check(c);
		}
	}

	// EndOfFile（Lexerリファレンス1章）
	static final END_OF_FILE_CASES:Array<LexCase> = [
		{
			name: "空の入力は、位置0のEndOfFileだけ",
			input: str(""),
			tokens: [tok(EndOfFile, 0, 0)]
		},
		{
			name: "範囲が空（start = end）なら、その位置のEndOfFileだけ。範囲外のバイトは読まない",
			input: str("abc"),
			start: 1,
			end: 1,
			tokens: [tok(EndOfFile, 1, 1)]
		},
	];

	/**
		[Lexerリファレンス1章 EndOfFile]・[Lexer.nextのdocコメント] 範囲の終端では幅0のEndOfFileを返す。
		ほかのトークンの後ろのEndOfFileは、各テストのケースの末尾で見ている。
		観点:
		-         正常: 空の入力
		-         境目: 該当なし（幅0で、切れ目を持たない）
		-     範囲の端: 範囲が空（`start` = `end`）で、範囲外にバイトがある
		-     空・最小: 空の入力
		- 不正なバイト: 該当なし（バイトを読まない）
		-       大きさ: 該当なし（幅0）
		-   仕様の細則: 何度呼ばれても返し続ける（testEndOfFileRepeats）
	**/
	function testEndOfFile() {
		checkAll(END_OF_FILE_CASES);
	}

	/** [Lexerリファレンス1章 EndOfFile]・[Lexer.nextのdocコメント] 範囲の終端に達した後は、何度呼んでも同じ位置の幅0のEndOfFileを返す。観点の表はtestEndOfFile。 */
	function testEndOfFileRepeats() {
		// 入力"ab c"の範囲[0, 2)。前にトークン（ab）があり、範囲外（" c"）がある
		final lexer = new Lexer(str("ab c"), {end: 2});
		final first = lexer.next();
		Assert.equals(Unknown, first.kind, "最初のトークンはab（Unknown）");
		for (i in 1...5) {
			final token = lexer.next();
			final at = 'EndOfFileの${i}回目';
			Assert.equals(EndOfFile, token.kind, '$at: kind');
			Assert.equals(2, token.start, '$at: start（範囲の終端）');
			Assert.equals(2, token.end, '$at: end（幅0）');
			Assert.equals(TokenFlags.NONE, token.flags, '$at: flags');
		}
	}

	// 範囲の検査（Lexer.newのdocコメント）

	/** 5バイトの入力。範囲の検査はバイトの中身によらないので、中身は何でもよい。 */
	static final RANGE_INPUT = str("abcde");

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
		[Lexer.newのdocコメント] `start`が0未満、`end`が`bytes.length`より大きい、`start`が`end`より大きいときは例外。
		省略した`start`は0、`end`は`bytes.length`として比べる。`start = end`は許す。
		観点:
		-         正常: 省略なし（`bytes`全体）、`{start: 0, end: bytes.length}`、途中の範囲
		-         境目: `start` = 0（作れる）と-1（例外）、`end` = `bytes.length`（作れる）と+1（例外）、`start` = `end`（作れる）と`end` + 1（例外）
		-     範囲の端: 範囲が末尾で空（`start` = `end` = `bytes.length`）、`end`だけ省略して`start` = `bytes.length`（作れる）と+1（例外）、`start`だけ省略して`end` = -1（例外）
		-     空・最小: 空の入力で範囲を省略（作れる）、空の入力で`end` = 1（例外）
		- 不正なバイト: 該当なし（バイトの中身を見ない）
		-       大きさ: 該当なし（中身を走査しない）
		-   仕様の細則: 省略したほうは既定値で比べる
	**/
	function testConstructorRange() {
		final len = RANGE_INPUT.length;
		checkConstruct([
			{name: "範囲を省略 → 作れる（bytes全体）", make: () -> new Lexer(RANGE_INPUT), throws: false},
			{name: "start 0・end bytes.length → 作れる", make: () -> new Lexer(RANGE_INPUT, {start: 0, end: len}), throws: false},
			{name: "途中の範囲 [1, 3) → 作れる", make: () -> new Lexer(RANGE_INPUT, {start: 1, end: 3}), throws: false},
			{name: "start -1 → 例外（0未満）", make: () -> new Lexer(RANGE_INPUT, {start: -1, end: len}), throws: true},
			{name: "end bytes.length + 1 → 例外（bytes.lengthより大きい）", make: () -> new Lexer(RANGE_INPUT, {start: 0, end: len + 1}), throws: true},
			{name: "start = end（途中の空の範囲） → 作れる", make: () -> new Lexer(RANGE_INPUT, {start: 2, end: 2}), throws: false},
			{name: "start = end + 1 → 例外（startがendより大きい）", make: () -> new Lexer(RANGE_INPUT, {start: 3, end: 2}), throws: true},
			{
				name: "start = end = bytes.length（末尾の空の範囲） → 作れる",
				make: () -> new Lexer(RANGE_INPUT, {start: len, end: len}),
				throws: false
			},
			{
				name: "endを省略してstart = bytes.length → 作れる（endはbytes.length）",
				make: () -> new Lexer(RANGE_INPUT, {start: len}),
				throws: false
			},
			{
				name: "endを省略してstart = bytes.length + 1 → 例外（endはbytes.lengthなので、startがendより大きい）",
				make: () -> new Lexer(RANGE_INPUT, {start: len + 1}),
				throws: true
			},
			{
				name: "startを省略してend -1 → 例外（startは0なので、startがendより大きい）",
				make: () -> new Lexer(RANGE_INPUT, {end: -1}),
				throws: true
			},
			{name: "空の入力で範囲を省略 → 作れる", make: () -> new Lexer(str("")), throws: false},
			{name: "空の入力でend 1 → 例外（bytes.lengthより大きい）", make: () -> new Lexer(str(""), {end: 1}), throws: true},
		]);
	}

	// Whitespace（Lexerリファレンス1章）
	static final WHITESPACE_CASES = flatten([
		[
			for (b in WHITESPACES) {
				whole('空白6種のどれも、1バイトだけでWhitespaceになる: byte=$b', bytesOf([b]), Whitespace);
			}
		],
		[
			whole("6種が混ざった連続は、1つのWhitespaceにまとまる（最長一致）", bytesOf(WHITESPACES), Whitespace),
			{
				name: "空白でないバイトの手前で止まり、そのバイトを取り込まない",
				input: str(" \ta"),
				tokens: [tok(Whitespace, 0, 2), tok(Unknown, 2, 3), tok(EndOfFile, 3, 3)]
			},
			{
				name: "空白でないトークンの後ろから始まる空白",
				input: str("a  "),
				tokens: [tok(Unknown, 0, 1), tok(Whitespace, 1, 3), tok(EndOfFile, 3, 3)]
			},
			whole("入力が空白で終わっても、範囲外を読まずにEndOfFileになる", str("   "), Whitespace),
			{
				name: "範囲の終端（end）が空白の途中にあれば、そこで止まる",
				input: str("    "),
				end: 2,
				tokens: [tok(Whitespace, 0, 2), tok(EndOfFile, 2, 2)]
			},
			{
				name: "範囲の開始（start）から読み始める",
				input: str("a   "),
				start: 2,
				tokens: [tok(Whitespace, 2, 4), tok(EndOfFile, 4, 4)]
			},
			whole("長い空白（0x00の連続）でもスタックがあふれず、1つのWhitespaceになる", zeros(100000), Whitespace),
		]
	]);

	/**
		[Lexerリファレンス1章 Whitespace]
		観点:
		-         正常: 空白6種それぞれの1バイト、6種が混ざった連続
		-         境目: 空白でないバイトの手前で止まる、空白でないトークンの後ろから始まる
		-     範囲の端: 入力の末尾、`end`が空白の途中、`start`から読み始める
		-     空・最小: 1バイト（6種それぞれ）
		- 不正なバイト: 該当なし（空白6種以外は空白にならない。「境目」で見る）
		-       大きさ: 0x00が100000個
		-   仕様の細則: NULも空白（6種の1バイトのケースに含まれる）
	**/
	function testWhitespace() {
		checkAll(WHITESPACE_CASES);
	}

	// コメントとHeaderMarker（Lexerリファレンス1章）
	static final COMMENT_CASES = flatten([
		[
			{
				name: "コメントは行末の手前まで。LFは含まない",
				input: str("%abc\n"),
				tokens: [tok(Comment, 0, 4), tok(Whitespace, 4, 5), tok(EndOfFile, 5, 5)]
			},
			{
				name: "CRでも止まる。CRLFはまとめて後ろのWhitespaceになる",
				input: str("%abc\r\n"),
				tokens: [tok(Comment, 0, 4), tok(Whitespace, 4, 6), tok(EndOfFile, 6, 6)]
			},
			whole("改行の無い末尾のコメントは、入力の終わりまで", str("%abc"), Comment),
			{
				name: "空のコメント（%の直後が改行）",
				input: str("%\n"),
				tokens: [tok(Comment, 0, 1), tok(Whitespace, 1, 2), tok(EndOfFile, 2, 2)]
			},
			whole("%だけの入力。PDF-を調べるときに範囲外を読まない", str("%"), Comment),
			{
				name: "コメントの中のdelimiter・空白（SP・TAB等の改行以外）は、コメントの一部になる",
				input: str("%a (b) <</c>> [\t%d\n"),
				tokens: [tok(Comment, 0, 18), tok(Whitespace, 18, 19), tok(EndOfFile, 19, 19)]
			},
			{
				name: "%%EOFは、PDF-で始まらないのでComment",
				input: str("%%EOF\n"),
				tokens: [tok(Comment, 0, 5), tok(Whitespace, 5, 6), tok(EndOfFile, 6, 6)]
			},
			{
				name: "%PDF-で始まるコメントはHeaderMarker（トリビアではない実トークン）",
				input: str("%PDF-1.7\r\n"),
				tokens: [tok(HeaderMarker, 0, 8), tok(Whitespace, 8, 10), tok(EndOfFile, 10, 10)]
			},
			whole("PDF-がちょうど入力の終わりに達する場合も、範囲内に収まるのでHeaderMarker", str("%PDF-"), HeaderMarker),
			whole("%PDF-の後ろのバイトに条件は付けない", str("%PDF-abc"), HeaderMarker),
			whole("大文字・小文字は区別する", str("%pdf-1.7"), Comment),
			whole("0x80以上のバイト（UTF-8として不正な並び）も、例外にならずコメントの一部になる", bytesOf(["%".code, 0x80, 0xFF, 0xC3]), Comment),
			whole("長いコメントでもスタックがあふれず、1つのCommentになる", str("%" + [for (_ in 0...100000) "a"].join("")), Comment),
			{
				name: "ファイルの途中の%PDF-もHeaderMarkerになる（Lexerリファレンス1章: 位置を問わない）",
				input: str("\n%PDF-2.0"),
				tokens: [tok(Whitespace, 0, 1), tok(HeaderMarker, 1, 9), tok(EndOfFile, 9, 9)]
			},
			{
				name: "範囲の終端（end）がコメントの途中にあれば、そこで止まる",
				input: str("%abcdef\n"),
				end: 4,
				tokens: [tok(Comment, 0, 4), tok(EndOfFile, 4, 4)]
			},
		],
		[
			for (s in ["%P", "%PD", "%PDF"]) {
				whole('%の後ろが4バイトに満たない入力は、例外にならずCommentになる: $s', str(s), Comment);
			}
		],
		[
			for (end in 1...5) {
				{
					name: '範囲の終端（end）がPDF-の途中にあれば、範囲外を見ずにCommentになる: end=$end',
					input: str("%PDF-1.7"),
					end: end,
					tokens: [tok(Comment, 0, end), tok(EndOfFile, end, end)]
				};
			}
		]
	]);

	/**
		[Lexerリファレンス1章 Comment・HeaderMarker]
		観点:
		-         正常: コメント、`%%EOF`、`%PDF-1.7`のHeaderMarker
		-         境目: LF・CRの手前で止まる、CRLFは後ろのWhitespace、中のdelimiter・空白はコメントの一部
		-     範囲の端: 改行の無い末尾、`end`がコメントの途中、`end`が`PDF-`の途中（1〜4）、`PDF-`がちょうど入力の終わり
		-     空・最小: 空のコメント、`%`だけ、`%`の後ろが4バイト未満
		- 不正なバイト: 0x80以上・UTF-8として不正な並び
		-       大きさ: 長いコメント（100000バイト）
		-   仕様の細則: 大文字・小文字の区別、`PDF-`の後ろに条件なし、ファイルの途中の`%PDF-`
	**/
	function testCommentAndHeaderMarker() {
		checkAll(COMMENT_CASES);
	}

	// delimiter（Lexerリファレンス1章）。単独の`<`（HexString）と`(`（LiteralString）は、それぞれの節で詳しく見る
	static final DELIMITER_CASES:Array<LexCase> = [
		whole("[は1バイトのトークン", str("["), LeftBracket),
		whole("]は1バイトのトークン", str("]"), RightBracket),
		whole("{は1バイトのトークン", str("{"), LeftBrace),
		whole("}は1バイトのトークン", str("}"), RightBrace),
		{
			name: "1バイトのdelimiterは、連続しても1つずつに分かれる",
			input: str("[[]{}]"),
			tokens: [
				tok(LeftBracket, 0, 1),
				tok(LeftBracket, 1, 2),
				tok(RightBracket, 2, 3),
				tok(LeftBrace, 3, 4),
				tok(RightBrace, 4, 5),
				tok(RightBracket, 5, 6),
				tok(EndOfFile, 6, 6),
			]
		},
		{
			name: "<<と>>は2バイトのトークン",
			input: str("<<>>"),
			tokens: [tok(LeftDoubleAngle, 0, 2), tok(RightDoubleAngle, 2, 4), tok(EndOfFile, 4, 4)]
		},
		{
			name: "<<<<は<<が2つ（最長一致で前から2バイトずつ）",
			input: str("<<<<>>>>"),
			tokens: [
				tok(LeftDoubleAngle, 0, 2),
				tok(LeftDoubleAngle, 2, 4),
				tok(RightDoubleAngle, 4, 6),
				tok(RightDoubleAngle, 6, 8),
				tok(EndOfFile, 8, 8),
			]
		},
		whole("単独の>は1バイトのUnknown（入力の末尾）", str(">"), Unknown),
		{
			name: "間に空白がある> >は、>>にならない",
			input: str("> >"),
			tokens: [
				tok(Unknown, 0, 1),
				tok(Whitespace, 1, 2),
				tok(Unknown, 2, 3),
				tok(EndOfFile, 3, 3)
			]
		},
		{
			name: ">>>は>>と単独の>",
			input: str(">>>"),
			tokens: [tok(RightDoubleAngle, 0, 2), tok(Unknown, 2, 3), tok(EndOfFile, 3, 3)]
		},
		{
			name: "><は<<にならない。>はUnknownで、<は次のトークンの先頭になる",
			input: str("><"),
			tokens: [
				tok(Unknown, 0, 1),
				tok(HexString, 1, 2, TokenFlags.UNTERMINATED),
				tok(EndOfFile, 2, 2)
			]
		},
		{
			name: "範囲の終端（end）が>>の間にあれば、範囲外を見ずに単独の>（Unknown）になる",
			input: str(">>"),
			end: 1,
			tokens: [tok(Unknown, 0, 1), tok(EndOfFile, 1, 1)]
		},
		{
			name: "範囲の終端（end）が<<の間にあれば、範囲外を見ない（<<にならず1バイトで終わる）",
			input: str("<<"),
			end: 1,
			tokens: [tok(HexString, 0, 1, TokenFlags.UNTERMINATED), tok(EndOfFile, 1, 1)]
		},
		{
			name: "単独の)は1バイトのUnknown（Lexerリファレンス1章）",
			input: str("))"),
			tokens: [tok(Unknown, 0, 1), tok(Unknown, 1, 2), tok(EndOfFile, 2, 2)]
		},
		{
			name: "空白をはさんだ辞書・配列の区切り",
			input: str("<< [ ] >>\n"),
			tokens: [
				tok(LeftDoubleAngle, 0, 2),
				tok(Whitespace, 2, 3),
				tok(LeftBracket, 3, 4),
				tok(Whitespace, 4, 5),
				tok(RightBracket, 5, 6),
				tok(Whitespace, 6, 7),
				tok(RightDoubleAngle, 7, 9),
				tok(Whitespace, 9, 10),
				tok(EndOfFile, 10, 10),
			]
		},
	];

	/**
		[Lexerリファレンス1章 LeftBracket〜RightDoubleAngle・Unknown]
		観点:
		-         正常: `[` `]` `{` `}` `<<` `>>`、連続したdelimiter
		-         境目: `<<<<`、`> >`、`>>>`、`><`、空白をはさんだ辞書・配列
		-     範囲の端: `end`が`>>`・`<<`の間、単独の`>`が入力の末尾
		-     空・最小: 1バイトのdelimiterそれぞれ
		- 不正なバイト: 単独の`>`・`)`はUnknown
		-       大きさ: 該当なし（どれも1〜2バイトの固定長）
		-   仕様の細則: 単独の`<`と`(`は、testHexString・testLiteralStringで見る
	**/
	function testDelimiters() {
		checkAll(DELIMITER_CASES);
	}

	// Name（Lexerリファレンス1章）
	static final NAME_CASES = flatten([
		[
			whole("/から、regular byteが続く限りが1つのName", str("/Type"), Name),
			whole("/だけの入力は、空のName（入力の末尾）", str("/"), Name),
			{
				name: "/の直後が空白でも、空のNameになる",
				input: str("/ "),
				tokens: [tok(Name, 0, 1), tok(Whitespace, 1, 2), tok(EndOfFile, 2, 2)]
			},
			{
				name: "空白をはさまない/A/Bは、2つのName",
				input: str("/A/B"),
				tokens: [tok(Name, 0, 2), tok(Name, 2, 4), tok(EndOfFile, 4, 4)]
			},
			{
				name: "//は空のNameが2つ",
				input: str("//"),
				tokens: [tok(Name, 0, 1), tok(Name, 1, 2), tok(EndOfFile, 2, 2)]
			},
			{
				name: "辞書の中のName。<<・>>との境目で切れる",
				input: str("<</Type/Page>>"),
				tokens: [
					tok(LeftDoubleAngle, 0, 2),
					tok(Name, 2, 7),
					tok(Name, 7, 12),
					tok(RightDoubleAngle, 12, 14),
					tok(EndOfFile, 14, 14),
				]
			},
			whole("#xxは解釈せず、# - .もregular byteとしてNameに含める", str("/A#20B-c.d"), Name),
			whole("0x80以上のバイト（UTF-8として不正な並びを含む）も、例外にならずNameに含まれる", bytesOf(["/".code, 0x80, 0xFF, 0xC3, 0xE3]), Name),
			whole("長いNameでもスタックがあふれず、1つのNameになる", str("/" + [for (_ in 0...100000) "A"].join("")), Name),
			{
				name: "範囲の終端（end）がNameの途中にあれば、そこで止まる",
				input: str("/Type"),
				end: 3,
				tokens: [tok(Name, 0, 3), tok(EndOfFile, 3, 3)]
			},
			{
				name: "範囲の終端（end）が/の直後にあれば、空のNameになる",
				input: str("/Type"),
				end: 1,
				tokens: [tok(Name, 0, 1), tok(EndOfFile, 1, 1)]
			},
		],
		[
			for (b in WHITESPACES) {
				{
					name: '空白6種のどれでも、Nameはその手前で終わる: byte=$b',
					input: bytesOf(["/".code, "A".code, b]),
					tokens: [tok(Name, 0, 2), tok(Whitespace, 2, 3), tok(EndOfFile, 3, 3)]
				};
			}
		],
		[
			for (d in DELIMITERS) {
				{
					name: 'delimiter 10種のどれでも、Nameはその手前で終わる: $d',
					input: str("/A" + d),
					tokens: [tok(Name, 0, 2), anyAt(2)],
					prefix: true
				};
			}
		],
		[
			for (s in ["/00hoge", "/1", "/-1.5", "/R", "/n", "/obj", "/endstream"]) {
				whole('数字やキーワードと同じ並びでも、/の後ろはNameの一部: $s', str(s), Name);
			}
		]
	]);

	/**
		[Lexerリファレンス1章 Name]
		観点:
		-         正常: `/Type`、辞書の中のName
		-         境目: 空白6種・delimiter 10種の手前で終わる、`/A/B`、`//`
		-     範囲の端: `end`がNameの途中、`end`が`/`の直後、`/`だけの入力
		-     空・最小: 空のName（`/`だけ、`/`の直後が空白、`//`）
		- 不正なバイト: 0x80以上・UTF-8として不正な並び
		-       大きさ: 長いName（100000バイト）
		-   仕様の細則: `#xx`を解釈しない、数字やキーワードと同じ並びでもName
	**/
	function testName() {
		checkAll(NAME_CASES);
	}

	// regular run: 数値・キーワード・Unknown（Lexerリファレンス2章）

	/** 入力全体が1つのregular runになるケースの表。`kind`ごとに、その種類になる入力を並べる。 */
	static final WHOLE_RUNS:Array<{kind:SyntaxKind, why:String, inputs:Array<String>}> = [
		{
			kind: Integer,
			why: "符号は1個以下、数字が1個以上、.が無ければInteger。先頭の0も許す",
			inputs: ["0", "123", "-12", "+3", "007", "-0", "+0"]
		},
		{
			kind: Real,
			why: ".が1個あればReal。.は先頭・末尾・途中のどこでもよい（ISO 32000-2 7.3.3節）",
			inputs: ["3.14", "-3.62", "+123.6", "4.", "-.002", ".5", "+.5", "-.5", "0.0"]
		},
		{
			kind: Unknown,
			why: "数字を1つも含まない列は数値にならない",
			inputs: ["+", "-", ".", "+.", "-.", ".."]
		},
		{
			kind: Unknown,
			why: "符号が2個以上・途中にある列、.が2個以上の列は、分けずにrun全体が1つのUnknown",
			inputs: ["--1", "+-1", "1-2", "1+", "12.34.56", "1..2", "1.2."]
		},
		{
			kind: Unknown,
			why: "指数表記・基数表記は数値にならない（ISO 32000-2 7.3.3節）",
			inputs: ["123e5", "6.02E23", "16#FF"]
		},
		{
			kind: Unknown,
			why: "数字の後ろに英字が続く列は、数値とキーワードに分けずにUnknown（最長一致）",
			inputs: ["123abc", "0R", "1obj"]
		},
		{kind: KwR, why: "キーワードは完全に一致すれば対応するKw*", inputs: ["R"]},
		{kind: KwN, why: "同上", inputs: ["n"]},
		{kind: KwF, why: "同上", inputs: ["f"]},
		{kind: KwObj, why: "同上", inputs: ["obj"]},
		{kind: KwTrue, why: "同上", inputs: ["true"]},
		{kind: KwNull, why: "同上", inputs: ["null"]},
		{kind: KwXref, why: "同上", inputs: ["xref"]},
		{kind: KwFalse, why: "同上", inputs: ["false"]},
		{kind: KwEndobj, why: "同上", inputs: ["endobj"]},
		{kind: KwTrailer, why: "同上", inputs: ["trailer"]},
		{kind: KwEndstream, why: "同上", inputs: ["endstream"]},
		{kind: KwStartxref, why: "同上", inputs: ["startxref"]},
		{
			kind: Unknown,
			why: "キーワードは大文字・小文字を区別する",
			inputs: ["r", "N", "F", "Obj", "TRUE", "Null", "Stream", "EndObj"]
		},
		{
			kind: Unknown,
			why: "キーワードと長さが1違うだけの列は、キーワードにならない（前方一致で判定していないこと）",
			inputs: [
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
			]
		},
	];

	static final REGULAR_RUN_CASES = flatten([
		[
			for (row in WHOLE_RUNS) {
				for (s in row.inputs) {
					whole('${row.why}: $s', str(s), row.kind);
				}
			}
		],
		[
			for (c in [
				{s: "objx", end: 3, kind: KwObj},
				{s: "obj", end: 2, kind: Unknown},
				{s: "123", end: 2, kind: Integer},
				{s: "1.5", end: 2, kind: Real},
				{s: "-5", end: 1, kind: Unknown},
			]) {
				{
					name: '範囲の終端（end）がregular runの途中にあれば、そこで切ってから分類する: ${c.s}',
					input: str(c.s),
					end: c.end,
					tokens: [tok(c.kind, 0, c.end), tok(EndOfFile, c.end, c.end)]
				};
			}
		],
		[
			{
				// 直後の本体の扱いはM3-2で変わるので、最初のトークンだけを見る
				name: "streamはKwStream",
				input: str("stream"),
				tokens: [tok(KwStream, 0, 6)],
				prefix: true
			},
			whole("0x80以上のバイトを含むrunも、例外にならずUnknownになる", bytesOf(["R".code, 0xFF, 0x80, 0xC3]), Unknown),
			whole("長いrun（数字だけ）でもスタックがあふれず、1つのIntegerになる", str([for (_ in 0...100000) "1"].join("")), Integer),
			{
				name: "間接参照1 0 Rは、Integer・Integer・KwRに分かれる",
				input: str("1 0 R"),
				tokens: [
					tok(Integer, 0, 1),
					tok(Whitespace, 1, 2),
					tok(Integer, 2, 3),
					tok(Whitespace, 3, 4),
					tok(KwR, 4, 5),
					tok(EndOfFile, 5, 5),
				]
			},
			{
				name: "regular runはdelimiterの手前で終わる",
				input: str("obj<<"),
				tokens: [tok(KwObj, 0, 3), tok(LeftDoubleAngle, 3, 5), tok(EndOfFile, 5, 5)]
			},
			{
				name: "delimiterと隣り合う数値",
				input: str("[.5 -.5]"),
				tokens: [
					tok(LeftBracket, 0, 1),
					tok(Real, 1, 3),
					tok(Whitespace, 3, 4),
					tok(Real, 4, 7),
					tok(RightBracket, 7, 8),
					tok(EndOfFile, 8, 8),
				]
			},
			{
				name: "オブジェクトの見出し1 0 objと、Nameの直後の数値・キーワード",
				input: str("1 0 obj<</Count 3/Kids[]/X true>>endobj"),
				tokens: [
					tok(Integer, 0, 1),
					tok(Whitespace, 1, 2),
					tok(Integer, 2, 3),
					tok(Whitespace, 3, 4),
					tok(KwObj, 4, 7),
					tok(LeftDoubleAngle, 7, 9),
					tok(Name, 9, 15),
					tok(Whitespace, 15, 16),
					tok(Integer, 16, 17),
					tok(Name, 17, 22),
					tok(LeftBracket, 22, 23),
					tok(RightBracket, 23, 24),
					tok(Name, 24, 26),
					tok(Whitespace, 26, 27),
					tok(KwTrue, 27, 31),
					tok(RightDoubleAngle, 31, 33),
					tok(KwEndobj, 33, 39),
					tok(EndOfFile, 39, 39),
				]
			},
		]
	]);

	/**
		[Lexerリファレンス2章 regular runの分類]
		観点:
		-         正常: Integer・Real・キーワード13種（`stream`は先頭だけ）、間接参照、オブジェクトの見出し
		-         境目: delimiterの手前で終わる、delimiterと隣り合う数値、Nameの直後の数値・キーワード
		-     範囲の端: `end`がrunの途中なら、切ってから分類する
		-     空・最小: 1バイトのrun（`0`・`R`・`n`・`f`・`+`・`-`・`.`）
		- 不正なバイト: 0x80以上を含むrun
		-       大きさ: 長いrun（数字100000個）
		-   仕様の細則: 符号・`.`の数と位置、指数・基数表記、数字と英字の混在、大文字・小文字、前方一致でないこと
	**/
	function testRegularRun() {
		checkAll(REGULAR_RUN_CASES);
	}

	// LiteralString（Lexerリファレンス1章。エスケープの並びはISO 32000-2 7.3.4.2節）
	static final LITERAL_STRING_CASES = flatten([
		[
			whole("(から、括弧の深さが0に戻る)までが1つのLiteralString", str("(abc)"), LiteralString),
			whole("空の文字列()", str("()"), LiteralString),
			whole("入れ子の括弧は深さに数え、外側の)で閉じる（リファレンスの例）", str("(a(b)c)"), LiteralString),
			whole("何重に入れ子でも、深さが0に戻る)で閉じる", str("((()))"), LiteralString),
			{
				name: "隣り合う2つの文字列は、最初の)で切れて2つのトークンになる",
				input: str("(a)(b)"),
				tokens: [tok(LiteralString, 0, 3), tok(LiteralString, 3, 6), tok(EndOfFile, 6, 6)]
			},
		],
		[
			// エスケープされた括弧は深さに数えない
			whole("エスケープされた\\)では閉じない", str("(a\\)b)"), LiteralString),
			whole("エスケープされた\\(は深さを増やさないので、次の)で閉じる", str("(a\\(b)"), LiteralString),
			whole("\\\\は\\のエスケープなので、直後の)は本物で、そこで閉じる（\\が偶数個）", str("(\\\\)"), LiteralString),
			whole("\\\\\\)は\\のエスケープと\\)なので、最後の)で閉じる（\\が奇数個）", str("(\\\\\\))"), LiteralString),
			whole("\\\\の直後の(は本物なので深さに数え、)が2つ要る", str("(\\\\(a))"), LiteralString),
			whole("8進のエスケープ\\dddの直後の)は本物", str("(\\051)"), LiteralString),
			whole("定義の無いエスケープ（\\x）でも、直後の)は本物", str("(\\x)"), LiteralString),
			whole("\\と改行（行の継続）の後ろも、文字列の続き", str("(a\\\r\nb)"), LiteralString),
		],
		[
			// 文字列の中身は字句解析しない
			whole("中のdelimiter・%・空白・改行は、文字列の一部になる", str("(a%b [c]<d> /e\r\n{f})"), LiteralString),
			whole("0x80以上のバイト（UTF-8として不正な並び）やNULも、例外にならず文字列の一部になる", bytesOf(["(".code, 0x80, 0xFF, 0xC3, 0x00, ")".code]), LiteralString),
		],
		[
			// 範囲の終端で打ち切ったらUNTERMINATED。トークンは範囲の終端まで
			{
				name: "(だけの入力は、UNTERMINATEDの文字列",
				input: str("("),
				tokens: [tok(LiteralString, 0, 1, TokenFlags.UNTERMINATED), tok(EndOfFile, 1, 1)]
			},
			{
				name: ")が無いまま入力が終わったら、UNTERMINATEDで入力の終わりまで",
				input: str("(abc"),
				tokens: [tok(LiteralString, 0, 4, TokenFlags.UNTERMINATED), tok(EndOfFile, 4, 4)]
			},
			{
				name: "入れ子の内側だけが閉じて深さが0に戻らなければ、UNTERMINATED",
				input: str("(a(b)"),
				tokens: [tok(LiteralString, 0, 5, TokenFlags.UNTERMINATED), tok(EndOfFile, 5, 5)]
			},
			{
				name: "最後の)がエスケープされていれば、UNTERMINATED",
				input: str("(a\\)"),
				tokens: [tok(LiteralString, 0, 4, TokenFlags.UNTERMINATED), tok(EndOfFile, 4, 4)]
			},
			{
				name: "\\で入力が終われば、UNTERMINATEDで、\\も文字列に含める",
				input: str("(abc\\"),
				tokens: [tok(LiteralString, 0, 5, TokenFlags.UNTERMINATED), tok(EndOfFile, 5, 5)]
			},
		],
		[
			{
				name: "範囲の終端（end）が文字列の途中にあれば、そこで止まりUNTERMINATED",
				input: str("(abc)"),
				end: 3,
				tokens: [tok(LiteralString, 0, 3, TokenFlags.UNTERMINATED), tok(EndOfFile, 3, 3)]
			},
			{
				name: "範囲の終端（end）が\\の直後にあれば、範囲外の)を読まずにUNTERMINATED",
				input: str("(a\\)b)"),
				end: 3,
				tokens: [tok(LiteralString, 0, 3, TokenFlags.UNTERMINATED), tok(EndOfFile, 3, 3)]
			},
			{
				name: "範囲の終端（end）がちょうど閉じる)の直後なら、閉じた文字列になる",
				input: str("(a)b"),
				end: 3,
				tokens: [tok(LiteralString, 0, 3), tok(EndOfFile, 3, 3)]
			},
			{
				name: "範囲の開始（start）から読み始める",
				input: str("xx(a)"),
				start: 2,
				tokens: [tok(LiteralString, 2, 5), tok(EndOfFile, 5, 5)]
			},
		],
		[
			{
				name: "閉じた)の直後のregular byteは、別のトークンになる",
				input: str("(a)b"),
				tokens: [tok(LiteralString, 0, 3), tok(Unknown, 3, 4), tok(EndOfFile, 4, 4)]
			},
			{
				name: "閉じた)の直後のNameは、別のトークンになる",
				input: str("(a)/N"),
				tokens: [tok(LiteralString, 0, 3), tok(Name, 3, 5), tok(EndOfFile, 5, 5)]
			},
			{
				name: "深さが0に戻った後の)は、文字列の外の単独の)（Unknown）",
				input: str("(a))"),
				tokens: [tok(LiteralString, 0, 3), tok(Unknown, 3, 4), tok(EndOfFile, 4, 4)]
			},
			{
				name: "配列の中の文字列",
				input: str("[(a) (b)]"),
				tokens: [
					tok(LeftBracket, 0, 1),
					tok(LiteralString, 1, 4),
					tok(Whitespace, 4, 5),
					tok(LiteralString, 5, 8),
					tok(RightBracket, 8, 9),
					tok(EndOfFile, 9, 9),
				]
			},
		],
		[
			whole("長い中身でもスタックがあふれず、1つのLiteralStringになる", str("(" + [for (_ in 0...100000) "a"].join("") + ")"), LiteralString),
			whole("深い入れ子でもスタックがあふれず、1つのLiteralStringになる", str([for (_ in 0...100000) "("].join("") + [for (_ in 0...100000) ")"].join("")), LiteralString),
		]
	]);

	/**
		[Lexerリファレンス1章 LiteralString]・[ISO 32000-2 7.3.4.2節]（エスケープの並び）
		観点:
		-         正常: `(abc)`、入れ子、隣り合う2つ、配列の中
		-         境目: 閉じた`)`の直後のregular byte・Name、深さ0に戻った後の`)`
		-     範囲の端: `)`が無いまま終わる、`\`で終わる、`end`が途中・`\`の直後・ちょうど`)`の直後、`start`から読み始める
		-     空・最小: `()`、`(`だけ
		- 不正なバイト: 0x80以上・UTF-8として不正な並び・NUL
		-       大きさ: 長い中身、深い入れ子（100000）
		-   仕様の細則: エスケープされた括弧、`\`の偶奇、`\ddd`、定義の無いエスケープ、行の継続、中身を字句解析しない
	**/
	function testLiteralString() {
		checkAll(LITERAL_STRING_CASES);
	}

	// HexString（Lexerリファレンス1章）
	static final HEX_STRING_CASES = flatten([
		[
			whole("<から>までが1つのHexString（リファレンスの例）", str("<48 65>"), HexString),
			whole("空のHexString<>", str("<>"), HexString),
			whole("桁数が奇数でも、>までが1つのHexString", str("<4>"), HexString),
			{
				name: "隣り合う2つのHexStringは、最初の>で切れて2つのトークンになる",
				input: str("<0A><0B>"),
				tokens: [tok(HexString, 0, 4), tok(HexString, 4, 8), tok(EndOfFile, 8, 8)]
			},
		],
		[
			// 不正な文字があっても止めない
			whole("16進数でない文字があっても、>まで読む", str("<xyz>"), HexString),
			whole("中のdelimiter・%・空白・改行は、HexStringの一部になる", str("<4(8)%[\r\n]/6 5>"), HexString),
			whole("中の<は入れ子にならず、最初の>で閉じる", str("<a<b>"), HexString),
			whole("0x80以上のバイト（UTF-8として不正な並び）やNULも、例外にならずHexStringの一部になる", bytesOf(["<".code, 0x80, 0xFF, 0xC3, 0x00, ">".code]), HexString),
		],
		[
			// 範囲の終端で打ち切ったらUNTERMINATED。トークンは範囲の終端まで
			{
				name: "<だけの入力は、UNTERMINATEDのHexString（<の次が範囲の終端）",
				input: str("<"),
				tokens: [tok(HexString, 0, 1, TokenFlags.UNTERMINATED), tok(EndOfFile, 1, 1)]
			},
			{
				name: ">が無いまま入力が終わったら、UNTERMINATEDで入力の終わりまで",
				input: str("<48 65"),
				tokens: [tok(HexString, 0, 6, TokenFlags.UNTERMINATED), tok(EndOfFile, 6, 6)]
			},
			{
				name: "範囲の終端（end）がHexStringの途中にあれば、そこで止まりUNTERMINATED",
				input: str("<4865>"),
				end: 3,
				tokens: [tok(HexString, 0, 3, TokenFlags.UNTERMINATED), tok(EndOfFile, 3, 3)]
			},
			{
				name: "範囲の終端（end）がちょうど閉じる>の直後なら、閉じたHexStringになる",
				input: str("<48>>"),
				end: 4,
				tokens: [tok(HexString, 0, 4), tok(EndOfFile, 4, 4)]
			},
			{
				name: "範囲の開始（start）から読み始める",
				input: str("xx<48>"),
				start: 2,
				tokens: [tok(HexString, 2, 6), tok(EndOfFile, 6, 6)]
			},
		],
		[
			{
				name: "<>>は、空のHexStringと単独の>（<の次が>なので<<ではない）",
				input: str("<>>"),
				tokens: [tok(HexString, 0, 2), tok(Unknown, 2, 3), tok(EndOfFile, 3, 3)]
			},
			{
				name: "<<>は、<<と単独の>（<の次が<なのでHexStringではない）",
				input: str("<<>"),
				tokens: [tok(LeftDoubleAngle, 0, 2), tok(Unknown, 2, 3), tok(EndOfFile, 3, 3)]
			},
			{
				name: "<の直後が空白でも、HexStringになる",
				input: str("< 48>"),
				tokens: [tok(HexString, 0, 5), tok(EndOfFile, 5, 5)]
			},
			{
				name: "閉じた>の直後のregular byteは、別のトークンになる",
				input: str("<48>R"),
				tokens: [tok(HexString, 0, 4), tok(KwR, 4, 5), tok(EndOfFile, 5, 5)]
			},
			{
				name: "辞書の値のHexString。閉じる>の後ろの>>は辞書の終わり",
				input: str("<</K<0A>>>"),
				tokens: [
					tok(LeftDoubleAngle, 0, 2),
					tok(Name, 2, 4),
					tok(HexString, 4, 8),
					tok(RightDoubleAngle, 8, 10),
					tok(EndOfFile, 10, 10),
				]
			},
			{
				name: "閉じないHexStringは、後ろの辞書の終わり>>の最初の>で閉じる",
				input: str("<</K<0A>>"),
				tokens: [
					tok(LeftDoubleAngle, 0, 2),
					tok(Name, 2, 4),
					tok(HexString, 4, 8),
					tok(Unknown, 8, 9),
					tok(EndOfFile, 9, 9),
				]
			},
		],
		[
			whole("長い中身でもスタックがあふれず、1つのHexStringになる", str("<" + [for (_ in 0...100000) "0"].join("") + ">"), HexString),
		]
	]);

	/**
		[Lexerリファレンス1章 HexString]
		観点:
		-         正常: `<48 65>`、奇数桁、隣り合う2つ、辞書の値
		-         境目: `<>>`、`<<>`、`<`の直後が空白、閉じた`>`の直後のregular byte、閉じないHexStringは後ろの`>>`の最初の`>`で閉じる
		-     範囲の端: `>`が無いまま終わる、`end`が途中・ちょうど`>`の直後、`start`から読み始める
		-     空・最小: `<>`、`<`だけ
		- 不正なバイト: 16進数でない文字、0x80以上・UTF-8として不正な並び・NUL
		-       大きさ: 長い中身
		-   仕様の細則: 中身を字句解析しない、中の`<`は入れ子にならない
	**/
	function testHexString() {
		checkAll(HEX_STRING_CASES);
	}
}
