package rawpdf.cst.syntax;

import haxe.Exception;
import haxe.ds.ReadOnlyArray;

interface NodeChild {
	final kind:SyntaxKind;
	final fullLength:Int;
}

class GreenNode implements NodeChild {
	public final kind:SyntaxKind;
	public final children:ReadOnlyArray<NodeChild>;
	public final fullLength:Int;

	/**
		`fullLength` は `children[...].fullLength` の合計で決まる。
		`children` は複製せずにそのまま持つ。呼び出し側は、渡した配列を以後変更しない
		（変更すると、作った時点で決めた `fullLength` と中身が食い違う）。
		@throws haxe.Exception `kind` が `Node` でない場合
	**/
	public function new(kind:SyntaxKind, children:ReadOnlyArray<NodeChild>) {
		if (!kind.isNode()) {
			throw new Exception('GreenNode.new: SyntaxKind.${kind} is not Node.');
		}

		this.kind = kind;
		this.children = children;
		fullLength = 0;
		for (c in children) {
			fullLength += c.fullLength;
		}
	}
}
