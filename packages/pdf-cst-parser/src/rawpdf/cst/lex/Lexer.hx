package rawpdf.cst.lex;

import rawpdf.cst.syntax.SyntaxKind;
import rawpdf.cst.syntax.TokenFlags;
import haxe.io.Bytes;

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

	// EOF の場合は null を返す
	function peek():Null<Int> {
		if (cursor >= end) {
			return null;
		} else {
			return bytes.get(cursor);
		}
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

	/** CR か LF が現れるまで cursor を進める。 CR,LF の手前まで進む。 **/
	function consumeToCROrLF() {
		while (true) {
			final c = peek();
			if (c == null || c == "\n".code || c == "\r".code) {
				return;
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
				kind = if (cursor + 3 < end && bytes.getString(cursor, 4, UTF8) == "PDF-") HeaderMarker else Comment;
				consumeToCROrLF();
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
					// TODO: Hex String
				}
			case ">".code:
				if (peek() == ">".code) {
					cursor++;
					kind = RightDoubleAngle;
				} else {
					// Unknown
				}
			case "/".code:
				// TODO: Name
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
				final d = nextDelimiter(tokenStart, c);
				if (d != null) {
					return d;
				}
			case Regular:
		}

		return {
			kind: Unknown,
			flags: TokenFlags.NONE,
			start: tokenStart,
			end: cursor,
		}
	}
}
