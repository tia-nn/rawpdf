package rawpdf.cst.syntax;

import haxe.io.Bytes;

/**
	1つのファイルの構文木。元のバイト列と、根の`SyntaxNode`を持つ。
	`SyntaxNode`・`SyntaxToken`は、`root`からたどって得る。
**/
class SyntaxTree {
	/** 元のバイト列（ファイル全体）。複製せずにそのまま参照するので、木を使う間は変更しない。 */
	public final bytes:Bytes;

	/** 根。`kind`は`Document`（パーサが保証する）。`fullStart`は0、`parent`は`null`。 */
	public final root:SyntaxNode;

	// TODO: diagnostics（Diagnostic型はM1以降。詳細設計9.1節）

	/**
		`bytes`と、そのファイル全体を表す根の`GreenNode`である`rootGreen`から木を作る。
		`rootGreen.fullLength`は`bytes.length`と等しいこと（呼び出し側が保証する。検査しない）。
	**/
	public function new(bytes:Bytes, rootGreen:GreenNode) {
		this.bytes = bytes;
		this.root = new SyntaxNode(bytes, rootGreen, null, 0);
	}
}
