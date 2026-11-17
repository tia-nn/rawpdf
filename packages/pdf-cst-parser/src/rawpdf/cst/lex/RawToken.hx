package rawpdf.cst.lex;

import rawpdf.cst.syntax.TokenFlags;
import rawpdf.cst.syntax.SyntaxKind;

@:structInit
class RawToken {
	public final kind:SyntaxKind;
	public final flags:TokenFlags;
	public final start:Int;
	public final end:Int;

	public function new(kind:SyntaxKind, flags:TokenFlags, start:Int, end:Int) {
		this.kind = kind;
		this.flags = flags;
		this.start = start;
		this.end = end;
	}
}
