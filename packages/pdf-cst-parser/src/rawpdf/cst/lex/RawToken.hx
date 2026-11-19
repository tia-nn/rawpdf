package rawpdf.cst.lex;

import rawpdf.cst.syntax.TokenFlags;
import rawpdf.cst.syntax.SyntaxKind;

@:structInit
class RawToken {
	public final kind:SyntaxKind;
	public final flags:TokenFlags;
	public final start:Int;
	public final end:Int;
}
