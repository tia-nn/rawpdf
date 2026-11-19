package rawpdf.cst.syntax;

import haxe.Exception;
import haxe.ds.ReadOnlyArray;
import rawpdf.cst.syntax.GreenNode.NodeChild;

/**
	イベント（`startNode`・`token`・`missingToken`・`finishNode`）を順に受け取って、Green木を組み立てる。
	最後に`finish`で根のノードを受け取る。1つの木を組むたびに新しく作る。

	要素（トークン・ノード）は、送った時点で開いているノードのうち最も内側のものの子になり、
	子の順番は送った順になる。どのノードも開いていない時点で送った要素を「最上位の要素」と呼ぶ。

	どのメソッドも、例外を投げた後のビルダーの状態は規定しない。例外を投げたビルダーは捨てて、以後使わない。
**/
class GreenBuilder {
	final children:Array<NodeChild>;
	final parents:Array<{kind:SyntaxKind, pos:Int}>;

	public function new() {
		children = [];
		parents = [];
	}

	/**
		種類が`kind`のノードを開く。対応する`finishNode`までに送った要素が、このノードの子になる。
		`kind`の検査は`finishNode`で行う。
	**/
	public function startNode(kind:SyntaxKind) {
		parents.push({kind: kind, pos: children.length});
	}

	/**
		引数どおりの`GreenToken`を1つ足す。
		@throws haxe.Exception `kind` が `Token` でない場合
		@throws haxe.Exception `textLength` が0未満の場合
	**/
	public function token(kind:SyntaxKind, flags:TokenFlags, leadingTrivia:ReadOnlyArray<GreenTrivia>, textLength:Int) {
		children.push(new GreenToken(kind, flags, leadingTrivia, textLength));
	}

	/**
		欠けているトークン（missing token）を1つ足す。
		種類は`kind`、フラグは`MISSING`だけ、`leadingTrivia`は空、`textLength`は0になる（`fullLength`も0）。
		@throws haxe.Exception `kind` が `Token` でない場合
	**/
	public function missingToken(kind:SyntaxKind) {
		children.push(new GreenToken(kind, TokenFlags.MISSING, [], 0));
	}

	/**
		最も内側の開いているノードを閉じて、`GreenNode`を作る。
		できたノードは、1つ外側の開いているノードの子（無ければ最上位の要素）になる。
		@throws haxe.Exception 開いているノードがない場合
		@throws haxe.Exception 閉じるノードの`startNode`に渡した`kind`が`Node`でない場合
	**/
	public function finishNode() {
		final node = parents.pop();
		if (node == null) {
			throw new Exception("GreenBuilder.finishNode: no node is open.");
		}

		final nodeChildren = children.splice(node.pos, children.length - node.pos);
		try {
			children.push(new GreenNode(node.kind, nodeChildren));
		} catch (e) {
			// 仕様にはないが一応ロールバックしておく
			for (child in nodeChildren) {
				children.push(child);
			}
			parents.push(node);
			throw e;
		}
	}

	/**
		組み立てた木の根（最上位のノード）を返す。
		@throws haxe.Exception 閉じていないノードがある場合
		@throws haxe.Exception 最上位の要素がノード1つでない場合。
			たとえば、何も送っていない、最上位でノードを2つ以上閉じた、どのノードにも入らないトークンを送った
	**/
	public function finish():GreenNode {
		if (parents.length != 0) {
			throw new Exception('GreenBuilder.finish: ${parents.length} node(s) are still open (innermost: SyntaxKind.${parents[parents.length - 1].kind}).');
		}
		if (children.length != 1) {
			throw new Exception('GreenBuilder.finish: expected exactly 1 root element, but found ${children.length}.');
		}

		final node = children.pop();
		if (node == null) {
			throw new Exception("GreenBuilder.finish: nothing was built.");
		}
		if (!node.kind.isNode()) {
			// 仕様にはないが一応ロールバックしておく
			children.push(node);
			throw new Exception('GreenBuilder.finish: root must be a node, but was SyntaxKind.${node.kind}.');
		}

		final node:Null<GreenNode> = Std.downcast((node : NodeChild), GreenNode);
		if (node == null) {
			throw new Exception("GreenBuilder.finish: root has a node kind but is not a GreenNode.");
		}
		return node;
	}
}
