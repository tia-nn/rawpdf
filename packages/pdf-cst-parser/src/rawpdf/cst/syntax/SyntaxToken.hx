package rawpdf.cst.syntax;

import haxe.ds.ReadOnlyArray;
import haxe.io.Bytes;

/** `SyntaxToken`から見たトリビア。`GreenTrivia`に絶対位置`start`を付けたもの。 */
typedef SyntaxTrivia = {
	/** トリビアの種類（`Whitespace`・`Comment`など）。 */
	final kind:SyntaxKind;

	/** トリビアの開始位置（ファイル先頭からのバイトオフセット）。 */
	final start:Int;

	/** トリビアのバイト数。 */
	final length:Int;
}

/**
	構文木のトークン。`GreenToken`に、親と絶対位置を付けたビュー。
	`SyntaxToken`はたどるたびに新しく作られる。同じトークンかどうかは、`green`の参照（`==`）と`fullStart`で比べる。
	位置はすべて、ファイル先頭からのバイトオフセット。
	トークンは、leading trivia（直前の空白やコメント）と、本体（トークンそのもののバイト列）からなる。
**/
class SyntaxToken {
	final source:Bytes;

	/** `green.kind`と同じ。 */
	public final kind:SyntaxKind;

	/** `green.flags`と同じ。 */
	public final flags:TokenFlags;

	/** このトークンを直接の子に持つノード。 */
	public final parent:SyntaxNode;

	/** このトークンの`GreenToken`。 */
	public final green:GreenToken;

	/** leading trivia込みの開始位置。 */
	public final fullStart:Int;

	/** 本体の開始位置（leading triviaの直後）。 */
	public var start(get, never):Int;

	/**
		本体の終わりの位置（その位置を含まない）。`start + green.textLength`。
		本体が幅0のトークン（missing token・`EndOfFile`）では`start`と等しい。
	**/
	public var end(get, never):Int;

	@:allow(rawpdf.cst.syntax)
	function new(source:Bytes, green:GreenToken, parent:SyntaxNode, fullStart:Int) {
		this.source = source;
		this.kind = green.kind;
		this.flags = green.flags;
		this.green = green;
		this.parent = parent;
		this.fullStart = fullStart;
	}

	function get_start():Int {
		return fullStart + green.fullLength - green.textLength;
	}

	function get_end():Int {
		return fullStart + green.fullLength;
	}

	/**
		本体の範囲`[start, end)`を、元のバイト列をコピーせずに見せるビュー。leading triviaは含まない。
		返す`ByteSpan`の`source`は`SyntaxTree.bytes`そのもの。
	**/
	public function byteSpan():ByteSpan {
		return new ByteSpan(source, start, green.textLength);
	}

	/**
		leading triviaを前から順に、絶対位置を付けて返す。トリビアが無ければ空の配列。
		最初のトリビアの`start`は`fullStart`で、各トリビアは前のトリビアの直後から始まる。最後のトリビアの直後が`start`。
	**/
	public function leadingTrivia():ReadOnlyArray<SyntaxTrivia> {
		var tStart = fullStart;
		final arr = [];
		for (t in green.leadingTrivia) {
			arr.push({
				kind: t.kind,
				start: tStart,
				length: t.length,
			});
			tStart += t.length;
		}
		return arr;
	}
}
