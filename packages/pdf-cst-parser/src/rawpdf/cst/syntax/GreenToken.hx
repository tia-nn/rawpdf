package rawpdf.cst.syntax;

import haxe.Exception;
import haxe.ds.ReadOnlyArray;

class GreenToken implements GreenNode.GreenNodeChild {
	public final kind:SyntaxKind;
	public final flags:TokenFlags;
	public final leadingTrivia:ReadOnlyArray<GreenTrivia>;
	public final textLength:Int;
	public final fullLength:Int;

	/**
		`fullLength` は textLength + sum(leadingTrivia[...].length) で決まる。
		`leadingTrivia` は複製せずにそのまま持つ。呼び出し側は、渡した配列を以後変更しない
		（変更すると、作った時点で決めた `fullLength` と中身が食い違う）。
		@throws haxe.Exception `kind` が `Token` でない場合
		@throws haxe.Exception `textLength` が0未満の場合
	**/
	public function new(kind:SyntaxKind, flags:TokenFlags, leadingTrivia:ReadOnlyArray<GreenTrivia>, textLength:Int) {
		if (!kind.isToken()) {
			throw new Exception('GreenToken.new: SyntaxKind.${kind} is not Token.');
		}
		if (textLength < 0) {
			throw new Exception('GreenToken.new: textLength should not be negative, but was $textLength.');
		}

		this.kind = kind;
		this.flags = flags;
		this.leadingTrivia = leadingTrivia;
		this.textLength = textLength;
		fullLength = textLength;
		for (t in leadingTrivia) {
			fullLength += t.length;
		}
	}
}
