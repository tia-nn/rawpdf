package rawpdf.cst.lex;

import haxe.Exception;
import haxe.ds.ReadOnlyArray;

enum abstract ByteClass(Int) {
	var Regular;
	var Whitespace;
	var Delimiter;

	public inline function isRegular() {
		return abstract == Regular;
	}

	public inline function isWhitespace() {
		return abstract == Whitespace;
	}

	public inline function isDelimiter() {
		return abstract == Delimiter;
	}

	/** 基本設計4.1節の分類。添字はバイト値（0〜255） **/
	static final TABLE:ReadOnlyArray<ByteClass> = {
		final table = [for (_ in 0...256) Regular];
		for (b in [0x00, 0x09, 0x0A, 0x0C, 0x0D, 0x20]) {
			table[b] = Whitespace;
		}
		for (b in [
			"(".code, ")".code, "<".code, ">".code, "[".code, "]".code, "{".code, "}".code, "/".code, "%".code
		]) {
			table[b] = Delimiter;
		}
		table;
	};

	public static function of(b:Int) {
		if (0 > b || b > 255) {
			throw new Exception('ByteClass.of: $b is out of 0..255 range.');
		}
		return TABLE[b];
	}
}
