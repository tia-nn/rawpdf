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

	public function new(bytes:Bytes, ?options:LexerOptions) {
		this.bytes = bytes;
		start = options?.start ?? 0;
		end = options?.end ?? bytes.length;
		streamBodyHints = options?.streamBodyHints ?? new Map();

		cursor = start;
	}

	inline function peek():Null<Int> {
		return peekPos(cursor);
	}

	inline function peekPos(pos:Int) {
		return if (pos >= end) null else return bytes.get(pos);
	}

	function startsWithAt(pos:Int, dest:String):Bool {
		for (c in dest) {
			if (peekPos(pos++) != c) {
				return false;
			}
		}

		return true;
	}

	function consumeWhitespace() {
		while (true) {
			final c = peek();
			if (c == null || ByteClass.of(c) != Whitespace) {
				return;
			}
			cursor++;
		}
	}

	function consumeRegular() {
		while (true) {
			final c = peek();
			if (c == null || ByteClass.of(c) != Regular) {
				return;
			}
			cursor++;
		}
	}

	/** `CR` か `LF` が現れるまで `cursor` を進める。 `CR`,`LF` の手前まで進む。 **/
	function consumeUntilCROrLF() {
		while (true) {
			final c = peek();
			if (c == null || c == "\n".code || c == "\r".code) {
				return;
			}
			cursor++;
		}
	}

	/** `code` が現れるまで `cursor` を進める。 `code` の位置を含む。
		`end` まで現れなかったら `TokenFlags.UNTERMINATED` を返す。 **/
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

	/** 先頭が `Delimiter` なことがわかっている時に `cursor` を進めて `RawToken` を作成する。
		先頭が `Delimiter` 以外の場合は `Unknown` トークンになる。 **/
	function nextDelimiter(tokenStart:Int, lastC:Int):RawToken {
		var kind:SyntaxKind = Unknown;
		var flags:TokenFlags = TokenFlags.NONE;

		switch lastC {
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
				// TODO: Literal String
		}

		return {
			kind: kind,
			flags: flags,
			start: tokenStart,
			end: cursor,
		};
	}

	/** 先頭が `Regular` なことがわかっている時に `cursor` を進めて `RawToken` を作成する。
		先頭が `Regular` 以外の場合は `Unknown` トークンになる。 **/
	function nextRegular(tokenStart:Int):RawToken {
		consumeRegular();

		final c = bytes.get(tokenStart);

		if ((c == "+".code || c == "-".code || c == ".".code || (c >= "0".code && c <= "9".code))) {
			return {
				kind: classifyNumber(tokenStart, cursor - tokenStart),
				flags: TokenFlags.NONE,
				start: tokenStart,
				end: cursor,
			};
		}
		return {
			kind: classifyKeyword(tokenStart, cursor - tokenStart),
			flags: TokenFlags.NONE,
			start: tokenStart,
			end: cursor,
		};
	}

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

	function classifyKeyword(tokenStart:Int, len:Int):SyntaxKind {
		switch len {
			case 1:
				if (startsWithAt(tokenStart, "R")) {
					return KwR;
				}
				if (startsWithAt(tokenStart, "n")) {
					return KwN;
				}
				if (startsWithAt(tokenStart, "f")) {
					return KwF;
				}
			case 3:
				if (startsWithAt(tokenStart, "obj")) {
					return KwObj;
				}
			case 4:
				if (startsWithAt(tokenStart, "true")) {
					return KwTrue;
				}
				if (startsWithAt(tokenStart, "null")) {
					return KwNull;
				}
				if (startsWithAt(tokenStart, "xref")) {
					return KwXref;
				}
			case 5:
				if (startsWithAt(tokenStart, "false")) {
					return KwFalse;
				}
			case 6:
				if (startsWithAt(tokenStart, "endobj")) {
					return KwEndobj;
				}
				if (startsWithAt(tokenStart, "stream")) {
					return KwStream;
				}
			case 7:
				if (startsWithAt(tokenStart, "trailer")) {
					return KwTrailer;
				}
			case 9:
				if (startsWithAt(tokenStart, "endstream")) {
					return KwEndstream;
				}
				if (startsWithAt(tokenStart, "startxref")) {
					return KwStartxref;
				}
		}
		return Unknown;
	}

	public function next():RawToken {
		final tokenStart = cursor;

		final nc = peek();
		final c:Int = if (nc == null) { // EOF
			return {
				kind: EndOfFile,
				flags: TokenFlags.NONE,
				start: tokenStart,
				end: tokenStart,
			}
		} else {
			cursor++;
			nc;
		};
		final bc = ByteClass.of(c);

		switch bc {
			case Whitespace:
				consumeWhitespace();
				return {
					kind: Whitespace,
					flags: TokenFlags.NONE,
					start: tokenStart,
					end: cursor,
				}
			case Delimiter:
				return nextDelimiter(tokenStart, c);
			case Regular:
				return nextRegular(tokenStart);
		}

		return {
			kind: Unknown,
			flags: TokenFlags.NONE,
			start: tokenStart,
			end: cursor,
		}
	}
}
