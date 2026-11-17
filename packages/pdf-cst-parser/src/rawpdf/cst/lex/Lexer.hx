package rawpdf.cst.lex;

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

	public function new(bytes:Bytes, ?options:LexerOptions) {
		this.bytes = bytes;
		this.start = options?.start ?? 0;
		this.end = options?.end ?? bytes.length;
		this.streamBodyHints = options?.streamBodyHints ?? new Map();
	}
}
