package rawpdf.cst.lex;

import haxe.Exception;
import haxe.ds.Vector;
import rawpdf.cst.syntax.GreenTrivia;
import haxe.ds.ReadOnlyArray;
import rawpdf.cst.syntax.TokenFlags;
import rawpdf.cst.syntax.SyntaxKind;

using StringTools;

/**
	`TokenSource`が返す実トークン。直前のトリビアをまとめて持つ。
**/
class CookedToken {
	/** トークンの種類。トリビアの種類にはならない。 **/
	public final kind:SyntaxKind;

	/** Lexerが付けたフラグ。 **/
	public final flags:TokenFlags;

	/** このトークンの直前にあるトリビア。ファイルの中の順に並ぶ。無ければ空。 **/
	public final trivia:ReadOnlyArray<GreenTrivia>;

	/** トークン本体のバイト数。`trivia`の分は含まない。 **/
	public final textLength:Int;

	/** トークン本体の開始位置（トリビアの後ろ）。`TokenSource`の中でだけ使う。 **/
	@:allow(rawpdf.cst.lex.TokenSource)
	final start:Int;

	/**
		`rawToken`の種類・フラグ・位置と長さを写し、`trivia`を直前のトリビアとして持つ。
		`trivia`は複製せずにそのまま持つ。呼び出し側は、渡した配列を以後変更しない。
	**/
	public function new(rawToken:RawToken, trivia:ReadOnlyArray<GreenTrivia>) {
		kind = rawToken.kind;
		flags = rawToken.flags;
		this.trivia = trivia;
		textLength = rawToken.end - rawToken.start;
		start = rawToken.start;
	}
}

/**
	`Lexer`のトークン列を、トリビアを読み飛ばした実トークンの列として見せる。
	トリビアは、すべて直後の実トークンの`trivia`に付く。ファイル末尾のトリビアは、幅0の`EndOfFile`に付く。
	3つ先の実トークンまで先読みできる。
**/
class TokenSource {
	final lexer:Lexer;

	// ポインタは tail のみで、初期化時にすべて埋めておく。
	final tokenRingBuffer:Vector<CookedToken>;
	var tail:Int;

	static inline final LOOK_AHEAD = 3;

	/**
		`lexer`の現在位置から読み始める。作った時点で、3つ先の実トークンまで`lexer`を進める。
		呼び出し側は、以後`lexer`を直接進めない。
	**/
	public function new(lexer:Lexer) {
		this.lexer = lexer;
		tokenRingBuffer = new Vector(LOOK_AHEAD);

		// リングバッファは事前に埋めておく
		tail = 0;
		pushNextToken();
		pushNextToken();
		pushNextToken();
	}

	function nextCookedToken() {
		final leadingTrivia:Array<GreenTrivia> = [];
		while (true) {
			final rawToken = lexer.next();
			if (rawToken.kind.isTrivia()) {
				leadingTrivia.push(new GreenTrivia(rawToken.kind, rawToken.end - rawToken.start));
			} else {
				return new CookedToken(rawToken, leadingTrivia);
			}
		}
	}

	/** リングバッファに次の CookedToken を詰める **/
	function pushNextToken() {
		tokenRingBuffer.set(tail, nextCookedToken());
		tail = (tail + 1) % LOOK_AHEAD;
	}

	/**
		トリビアを読み飛ばして、`n`個先の実トークンを返す。消費はしない。
		`n`は0〜2（0が次に`next`で返るトークン）。`EndOfFile`より先を見ると、`EndOfFile`が返る（`next`と同じく、`trivia`は空）。
		@throws haxe.Exception `n` が0〜2の範囲外の場合
	**/
	public function peek(n:Int = 0):CookedToken {
		if (n < 0 || LOOK_AHEAD <= n) {
			throw new Exception('TokenSource.peek: n should be in 0..${LOOK_AHEAD - 1}, but was $n.');
		}
		return tokenRingBuffer[(tail + n) % LOOK_AHEAD];
	}

	/**
		次の実トークン（`peek(0)`と同じもの）を返し、消費する。
		ファイル末尾では、`EndOfFile`を返し続ける。ファイル末尾のトリビアが付くのは最初の`EndOfFile`だけで、2回目以降の`EndOfFile`の`trivia`は空。
	**/
	public function next():CookedToken {
		final t = peek(0);
		pushNextToken();
		return t;
	}

	/**
		`peek(0..2)`が`Integer Integer obj`の並びか。間のトリビアは問わない。
	**/
	public function atObjHeader():Bool {
		return peek(0).kind == Integer && peek(1).kind == Integer && peek(2).kind == KwObj;
	}

	/**
		`peek(0..2)`が`Integer Integer R`の並びか。間のトリビアは問わない。
	**/
	public function atReference():Bool {
		return peek(0).kind == Integer && peek(1).kind == Integer && peek(2).kind == KwR;
	}

	/**
		`peek(0)`のトリビアに、`%%EOF`の形のCommentが含まれるか。
		`%%EOF`の形とは、`%%EOF`で始まり、残りのバイトがすべてwhitespace（6種）であること（`%%EOF`ちょうども含む）。
		Commentが行のどこにあるかは問わない。
	**/
	public function hasEofCommentInTrivia():Bool {
		final t = peek(0);
		var start = t.start;
		var i = t.trivia.length - 1;
		while (i >= 0) {
			final tt = t.trivia[i--];
			start -= tt.length;
			if (isEofComment(tt, start)) {
				return true;
			}
		}
		return false;
	}

	/** 位置`start`から始まるトリビア`tt`が、`%%EOF`の形（`hasEofCommentInTrivia`）か。 **/
	function isEofComment(tt:GreenTrivia, start:Int) {
		var pos = start;
		final end = pos + tt.length;

		for (c in "%%EOF") {
			if (lexer.peekPos(pos++) != c) {
				return false;
			}
		}
		while (pos < end) {
			final c = lexer.peekPos(pos++);
			if (c == null) { // トリビアはLexerの範囲内にあるので通らない
				throw new Exception('TokenSource.isEofComment: position ${pos - 1} is outside the lexer range.');
			}
			if (ByteClass.of(c) != Whitespace) {
				return false;
			}
		}

		return true;
	}
}
