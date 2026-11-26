package rawpdf.cst.syntax;

import haxe.Exception;
import haxe.io.Bytes;
import rawpdf.cst.syntax.GreenNode.GreenNodeChild;

/** `SyntaxNode` の子要素 **/
enum SyntaxNodeChild {
	Node(node:SyntaxNode);
	Token(token:SyntaxToken);
}

/**
	構文木のノード。`GreenNode`に、親と絶対位置を付けたビュー。
	`SyntaxNode`はたどるたびに新しく作られる。同じ要素かどうかは、`green`の参照（`==`）と`fullStart`で比べる。
	位置はすべて、ファイル先頭からのバイトオフセット。
**/
class SyntaxNode {
	final source:Bytes;

	/** `green.kind`と同じ。 **/
	public final kind:SyntaxKind;

	/** 親のノード。根なら`null`。 **/
	public final parent:Null<SyntaxNode>;

	/** 対応する`GreenNode`。 **/
	public final green:GreenNode;

	/** leading trivia込みの開始位置。 **/
	public final fullStart:Int;

	/**
		leading triviaを除いた開始位置。`firstToken()`の`start`。
		部分木にトークンが無いときは`fullStart`。
	**/
	public var start(get, never):Int;

	/**
		終わりの位置（その位置を含まない）。`lastToken()`の`end`。
		部分木にトークンが無いときは`fullStart`。
	**/
	public var end(get, never):Int;

	@:allow(rawpdf.cst.syntax)
	function new(source:Bytes, green:GreenNode, parent:Null<SyntaxNode>, fullStart:Int) {
		this.source = source;
		this.kind = green.kind;
		this.green = green;
		this.parent = parent;
		this.fullStart = fullStart;
	}

	function get_start():Int {
		return firstToken()?.start ?? fullStart;
	}

	function get_end():Int {
		return fullStart + green.fullLength;
	}

	/** 子（ノードとトークン）を前から順に返す。 **/
	public function children():Iterator<SyntaxNodeChild> {
		final arr = [];
		var fs = fullStart;
		for (c in green.children) {
			arr.push(makeChild(c, fs));
			fs += c.fullLength;
		}
		return arr.iterator();
	}

	function makeChild(c:GreenNodeChild, childFullStart:Int):SyntaxNodeChild {
		if (c.kind.isNode()) {
			return Node(new SyntaxNode(source, cast(c, GreenNode), this, childFullStart));
		} else if (c.kind.isToken()) {
			return Token(new SyntaxToken(source, cast(c, GreenToken), this, childFullStart));
		} else {
			throw new Exception('SyntaxNode.makeChild: a child must be a node or a token, but was SyntaxKind.${c.kind}.');
		}
	}

	/** 子のうちノードだけを前から順に返す（`children()`からトークンを除いたもの）。 **/
	public function childNodes():Iterator<SyntaxNode> {
		final arr = [];
		var fs = fullStart;
		for (c in green.children) {
			if (c.kind.isNode()) {
				arr.push(new SyntaxNode(source, cast(c, GreenNode), this, fs));
			}
			fs += c.fullLength;
		}
		return arr.iterator();
	}

	/**
		子孫のトークンのうち、最初のもの。幅0のトークン（missing token・`EndOfFile`）も含む。
		返るトークンの`parent`は、そのトークンを直接の子に持つノード。
		部分木にトークンが無いとき（子が無いノード、トークンを持たないノードだけを子に持つノードなど）は`null`。
	**/
	public function firstToken():Null<SyntaxToken> {
		return searchFirstToken(this);
	}

	function searchFirstToken(current:SyntaxNode):Null<SyntaxToken> {
		// 最初のトークンより前にあるのは、トークンを持たない部分木だけで、その幅は0（幅はトークンだけが持つ）。
		// そのため、途中のノードも見つかるトークンも、開始位置は常にこのノードの`fullStart`になる。
		for (c in current.green.children) {
			if (c.kind.isNode()) {
				final n = searchFirstToken(new SyntaxNode(source, cast(c, GreenNode), current, fullStart));
				if (n != null) {
					return n;
				}
			} else if (c.kind.isToken()) {
				return new SyntaxToken(source, cast(c, GreenToken), current, fullStart);
			}
		}
		return null;
	}

	/**
		子孫のトークンのうち、最後のもの。幅0のトークン（missing token・`EndOfFile`）も含む。
		返るトークンの`parent`は、そのトークンを直接の子に持つノード。
		部分木にトークンが無いときは`null`（条件は`firstToken()`と同じ）。
	**/
	public function lastToken():Null<SyntaxToken> {
		return searchLastToken(this);
	}

	function searchLastToken(current:SyntaxNode):Null<SyntaxToken> {
		// 最後のトークンより後ろにあるのは、トークンを持たない部分木だけで、その幅は0（幅はトークンだけが持つ）。
		// そのため、潜っていく途中のノード`current`の終わりは、常にこのノードの終わりと等しい。そこから子の幅を引いて位置を出す。
		var cFullStart = fullStart + green.fullLength;
		var i = current.green.children.length;
		while (--i >= 0) {
			final c = current.green.children[i];
			cFullStart -= c.fullLength;

			if (c.kind.isNode()) {
				final n = searchLastToken(new SyntaxNode(source, cast(c, GreenNode), current, cFullStart));
				if (n != null) {
					return n;
				}
			} else if (c.kind.isToken()) {
				return new SyntaxToken(source, cast(c, GreenToken), current, cFullStart);
			}
		}

		return null;
	}

	/**
		`byteOffset`を含む最も内側の要素。
		各要素は、leading trivia込みの半開区間`[fullStart, fullStart + 幅)`を占めるとみなす。
		そのため、トリビアの中の位置はそのトリビアを持つトークンを返し、トークンの境界ちょうどの位置は後ろのトークンを返す。
		幅0のトークン（missing token等）は、どの位置も含まない。
		`byteOffset`が`end`と等しいときは`lastToken()`を返す（ファイル末尾の位置では`EndOfFile`になる）。
		部分木にトークンが無いときは、このノード自身を返す。
		@throws haxe.Exception `byteOffset`が`fullStart`未満か、`end`より大きい場合
	**/
	public function coveringElement(byteOffset:Int):SyntaxNodeChild {
		final end = fullStart + green.fullLength;
		if (byteOffset < fullStart || end < byteOffset) {
			throw new Exception('SyntaxNode.coveringElement: byteOffset should be in [$fullStart, $end], but was $byteOffset.');
		}

		if (byteOffset == end) {
			final last = lastToken();
			return last == null ? Node(this) : Token(last);
		}
		return Token(searchCoveringElement(byteOffset, this));
	}

	/** `current.fullStart <= byteOffset < current.fullStart + current.green.fullLength`を前提に、`byteOffset`を含むトークンを探す。 **/
	function searchCoveringElement(byteOffset:Int, current:SyntaxNode):SyntaxToken {
		var childFullStart = current.fullStart;
		for (c in current.green.children) {
			final childEnd = childFullStart + c.fullLength;
			// 幅0の子は childFullStart == childEnd なので、この条件に当てはまらず飛ばされる
			if (childFullStart <= byteOffset && byteOffset < childEnd) {
				if (c.kind.isNode()) {
					return searchCoveringElement(byteOffset, new SyntaxNode(source, cast(c, GreenNode), current, childFullStart));
				}
				return new SyntaxToken(source, cast(c, GreenToken), current, childFullStart);
			}
			childFullStart = childEnd;
		}
		// 子の幅の合計はノードの幅と等しいので、前提が成り立てばここには来ない
		throw new Exception('SyntaxNode.searchCoveringElement: no child covers $byteOffset.');
	}
}
