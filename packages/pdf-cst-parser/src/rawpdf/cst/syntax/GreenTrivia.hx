package rawpdf.cst.syntax;

import haxe.Exception;

class GreenTrivia {
	public final kind:SyntaxKind;
	public final length:Int;

	/**
		@throws haxe.Exception `kind` が `Trivia` でない場合
		@throws haxe.Exception `length` が1未満の場合
	**/
	public function new(kind:SyntaxKind, length:Int) {
		if (!kind.isTrivia()) {
			throw new Exception('GreenTrivia.new: SyntaxKind.${kind} is not Trivia.');
		}
		if (length < 1) {
			throw new Exception('GreenTrivia.new: length should be at least 1, but was $length.');
		}

		this.kind = kind;
		this.length = length;
	}
}
