package rawpdf.cst.lex;

import rawpdf.cst.syntax.SyntaxKind;
import rawpdf.cst.syntax.TokenFlags;
import haxe.io.Bytes;

using StringTools;

typedef StreamBodyHint = {
	final bodyEnd:Int;
	final endstreamStart:Int;
}

typedef LexerOptions = {
	final ?start:Int;
	final ?end:Int;
	final ?streamBodyHints:Map<Int, StreamBodyHint>;
}

class Lexer {
	final bytes:Bytes;
	final start:Int;
	final end:Int;
	final streamBodyHints:Map<Int, StreamBodyHint>;

	var cursor:Int;

	/** `bytes` の `[start, end)` を字句解析する。`start`・`end` を省略すると `bytes` 全体。 **/
	public function new(bytes:Bytes, ?options:LexerOptions) {
		this.bytes = bytes;
		start = options?.start ?? 0;
		end = options?.end ?? bytes.length;
		streamBodyHints = options?.streamBodyHints ?? new Map();

		cursor = start;
	}

	/** `cursor` から1トークンを切り出して返す。
		範囲の終端では幅0の `EndOfFile` を返し続ける。 **/
	public function next():RawToken {
		final c = peek();
		if (c == null) { // EOF
			return {
				kind: EndOfFile,
				flags: TokenFlags.NONE,
				start: cursor,
				end: cursor,
			}
		}

		return switch ByteClass.of(c) {
			case Whitespace:
				nextWhitespace();
			case Delimiter:
				nextDelimiter(c);
			case Regular:
				nextRegular(c);
		}
	}

	/** whitespaceが続く限り読み、`Whitespace` を返す。前提: `cursor` の位置のバイトがwhitespace。 **/
	function nextWhitespace():RawToken {
		final tokenStart = cursor++;
		consumeWhitespace();

		return {
			kind: Whitespace,
			flags: TokenFlags.NONE,
			start: tokenStart,
			end: cursor,
		}
	}

	/** delimiter `c` で始まるトークンを読んで返す。前提: `c` は `cursor` の位置のバイト。 **/
	function nextDelimiter(c:Int):RawToken {
		final tokenStart = cursor++;

		var kind:SyntaxKind = Unknown;
		var flags:TokenFlags = TokenFlags.NONE;

		switch c {
			case "%".code:
				kind = if (startsWithAt(cursor, "PDF-")) HeaderMarker else Comment;
				consumeUntilCROrLF();
			case "[".code:
				kind = LeftBracket;
			case "]".code:
				kind = RightBracket;
			case "{".code:
				kind = LeftBrace;
			case "}".code:
				kind = RightBrace;
			case "<".code:
				if (peek() == "<".code) {
					cursor++;
					kind = LeftDoubleAngle;
				} else {
					flags = consumeTo(">".code);
					kind = HexString;
				}
			case ">".code:
				if (peek() == ">".code) {
					cursor++;
					kind = RightDoubleAngle;
				} else {
					// Unknown
				}
			case "/".code:
				consumeRegular();
				kind = Name;
			case "(".code:
				flags = consumeLiteralString();
				kind = LiteralString;
		}

		return {
			kind: kind,
			flags: flags,
			start: tokenStart,
			end: cursor,
		};
	}

	/** regular runを読み、数値・キーワード・`Unknown` に分類して返す。
		前提: `c` は `cursor` の位置のバイトで、regular。満たさないと幅0のトークンを返す。 **/
	function nextRegular(c:Int):RawToken {
		final tokenStart = cursor++;
		consumeRegular();

		final kind = if ((c == "+".code || c == "-".code || c == ".".code || (c >= "0".code && c <= "9".code))) {
			classifyNumber(tokenStart, cursor - tokenStart);
		} else classifyKeyword(tokenStart, cursor - tokenStart);

		return {
			kind: kind,
			flags: TokenFlags.NONE,
			start: tokenStart,
			end: cursor,
		};
	}

	/** `[pos, pos + len)` が数値なら `Integer`・`Real`、でなければ `Unknown`（Lexerリファレンス2章）。 **/
	function classifyNumber(pos:Int, len:Int):SyntaxKind {
		final runEnd = pos + len;
		var i = pos;
		if (i < runEnd && (bytes.get(i) == "+".code || bytes.get(i) == "-".code)) {
			i++;
		}

		var digits = 0;
		var dots = 0;
		while (i < runEnd) {
			switch bytes.get(i) {
				case ".".code:
					dots++;
				case c if (c >= "0".code && c <= "9".code):
					digits++;
				case _:
					return Unknown; // 2個目の符号・指数の `e`・`#` など
			}
			i++;
		}

		if (digits == 0 || dots > 1) {
			return Unknown;
		}
		return if (dots == 1) Real else Integer;
	}

	/** `[pos, pos + len)` がキーワードと完全に一致すれば対応する `Kw*`、でなければ `Unknown`。 **/
	function classifyKeyword(pos:Int, len:Int):SyntaxKind {
		switch len {
			case 1:
				if (startsWithAt(pos, "R")) {
					return KwR;
				}
				if (startsWithAt(pos, "n")) {
					return KwN;
				}
				if (startsWithAt(pos, "f")) {
					return KwF;
				}
			case 3:
				if (startsWithAt(pos, "obj")) {
					return KwObj;
				}
			case 4:
				if (startsWithAt(pos, "true")) {
					return KwTrue;
				}
				if (startsWithAt(pos, "null")) {
					return KwNull;
				}
				if (startsWithAt(pos, "xref")) {
					return KwXref;
				}
			case 5:
				if (startsWithAt(pos, "false")) {
					return KwFalse;
				}
			case 6:
				if (startsWithAt(pos, "endobj")) {
					return KwEndobj;
				}
				if (startsWithAt(pos, "stream")) {
					return KwStream;
				}
			case 7:
				if (startsWithAt(pos, "trailer")) {
					return KwTrailer;
				}
			case 9:
				if (startsWithAt(pos, "endstream")) {
					return KwEndstream;
				}
				if (startsWithAt(pos, "startxref")) {
					return KwStartxref;
				}
		}
		return Unknown;
	}

	/** `cursor` の位置のバイト。範囲の終端なら `null`。 **/
	inline function peek():Null<Int> {
		return peekPos(cursor);
	}

	/** `pos` の位置のバイト。範囲の終端以降なら `null`。 **/
	inline function peekPos(pos:Int) {
		return if (pos >= end) null else bytes.get(pos);
	}

	/** `pos` からのバイト列が `dest` で始まるか。`dest` はASCIIだけを想定する。 **/
	function startsWithAt(pos:Int, dest:String):Bool {
		for (c in dest) {
			if (peekPos(pos++) != c) {
				return false;
			}
		}

		return true;
	}

	/** whitespaceが続く限り `cursor` を進める。 **/
	function consumeWhitespace() {
		while (true) {
			final c = peek();
			if (c == null || ByteClass.of(c) != Whitespace) {
				return;
			}
			cursor++;
		}
	}

	/** regular byteが続く限り `cursor` を進める。 **/
	function consumeRegular() {
		while (true) {
			final c = peek();
			if (c == null || ByteClass.of(c) != Regular) {
				return;
			}
			cursor++;
		}
	}

	/** CRかLFの手前まで `cursor` を進める（CR・LFは含まない）。 **/
	function consumeUntilCROrLF() {
		while (true) {
			final c = peek();
			if (c == null || c == "\n".code || c == "\r".code) {
				return;
			}
			cursor++;
		}
	}

	/** `code` まで `cursor` を進める（`code` を含む）。
		見つからないまま範囲の終端に達したら `UNTERMINATED` を返す。 **/
	function consumeTo(code:Int):TokenFlags {
		while (true) {
			final c = peek();
			if (c == null) {
				return TokenFlags.UNTERMINATED;
			} else if (c == code) {
				cursor++;
				return TokenFlags.NONE;
			}
			cursor++;
		}
	}

	/** `()` の深さが0になるまで `cursor` を進める（末尾の `)` を含む）。
		前提: 冒頭の `(` は読み込み済み。 **/
	function consumeLiteralString():TokenFlags {
		var depth = 1;

		while (true) {
			switch (peek()) {
				case null:
					return TokenFlags.UNTERMINATED;
				case "\\".code:
					if (cursor + 1 < end) {
						cursor += 2;
					} else {
						cursor++;
						return TokenFlags.UNTERMINATED;
					}
				case "(".code:
					cursor++;
					depth++;
				case ")".code:
					cursor++;
					if (--depth == 0) {
						return TokenFlags.NONE;
					}
				default:
					cursor++;
			}
		}
	}
}
