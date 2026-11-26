package rawpdf.cst.syntax;

import haxe.Exception;
import haxe.io.Bytes;

/**
	バイト列`source`の範囲`[start, start + length)`のビュー。
	`ByteSpan`は`source`を複製しないため、呼び出し元で`source`を変更しない。
**/
class ByteSpan {
	/** 元のバイト列。 **/
	public final source:Bytes;

	/** 範囲の開始位置（`source`の先頭からのバイトオフセット）。 **/
	public final start:Int;

	/** 範囲のバイト数。 **/
	public final length:Int;

	/**
		@throws haxe.Exception `start`か`length`が0未満の場合
		@throws haxe.Exception `start + length`が`source.length`より大きい場合
	**/
	public function new(source:Bytes, start:Int, length:Int) {
		// `start + length`は大きな値で溢れ得るので、引き算で比べる
		if (start < 0 || length < 0 || source.length - start < length) {
			throw new Exception('ByteSpan.new: the span (start: $start, length: $length) is out of the source [0, ${source.length}).');
		}

		this.source = source;
		this.start = start;
		this.length = length;
	}

	/**
		範囲の先頭から`i`番目のバイト。
		@throws haxe.Exception `i`が0未満か、`length`以上の場合
	**/
	public function get(i:Int) {
		if (i < 0 || length <= i) {
			throw new Exception('ByteSpan.get: i should be in [0, $length), but was $i.');
		}
		return source.get(start + i);
	}

	/** 範囲のバイト列をコピーして返す。 **/
	public function toBytes() {
		return source.sub(start, length);
	}
}
