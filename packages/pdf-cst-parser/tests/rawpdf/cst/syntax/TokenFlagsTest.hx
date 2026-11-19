package rawpdf.cst.syntax;

import utest.Assert;

class TokenFlagsTest extends utest.Test {
	/**
		[TokenFlags.hasのdocコメント] `a`のフラグをすべて含むかを判定する。`NONE`を渡すと常に`true`。
		観点:
		-         正常: 値4つ（NONE・UNTERMINATED・MISSING・両方）と引数4つの全組み合わせ
		-         境目: 該当なし（ビットの集合で、切れ目を持たない）
		-     範囲の端: 該当なし（値は定義済みのフラグの組み合わせだけ）
		-     空・最小: NONEの値、NONEを渡す（常に`true`）
		- 不正なバイト: 該当なし（バイト列を受け取らない）
		-       大きさ: 該当なし（固定長）
		-   仕様の細則: 一部だけ含む場合は`false`（UNTERMINATEDだけの値にMISSING|UNTERMINATEDを渡す）
	**/
	function testHas() {
		final none = TokenFlags.NONE;
		final unterminated = TokenFlags.UNTERMINATED;
		final missing = TokenFlags.MISSING;
		final unterminatedMissing = TokenFlags.UNTERMINATED | TokenFlags.MISSING;

		Assert.isTrue(none.has(TokenFlags.NONE));
		Assert.isFalse(none.has(TokenFlags.UNTERMINATED));
		Assert.isFalse(none.has(TokenFlags.MISSING));
		Assert.isFalse(none.has(TokenFlags.MISSING | TokenFlags.UNTERMINATED));

		Assert.isTrue(unterminated.has(TokenFlags.NONE));
		Assert.isTrue(unterminated.has(TokenFlags.UNTERMINATED));
		Assert.isFalse(unterminated.has(TokenFlags.MISSING));
		Assert.isFalse(unterminated.has(TokenFlags.MISSING | TokenFlags.UNTERMINATED));

		Assert.isTrue(missing.has(TokenFlags.NONE));
		Assert.isFalse(missing.has(TokenFlags.UNTERMINATED));
		Assert.isTrue(missing.has(TokenFlags.MISSING));
		Assert.isFalse(missing.has(TokenFlags.MISSING | TokenFlags.UNTERMINATED));

		Assert.isTrue(unterminatedMissing.has(TokenFlags.NONE));
		Assert.isTrue(unterminatedMissing.has(TokenFlags.UNTERMINATED));
		Assert.isTrue(unterminatedMissing.has(TokenFlags.MISSING));
		Assert.isTrue(unterminatedMissing.has(TokenFlags.MISSING | TokenFlags.UNTERMINATED));
	}

	/**
		[TokenFlags.isNoneのdocコメント] フラグが`NONE`かを判定する（`NONE`のときだけ`true`）。
		観点:
		-         正常: NONEだけが`true`、ほかの3つは`false`
		-         境目: 該当なし（ビットの集合で、切れ目を持たない）
		-     範囲の端: 該当なし（値は定義済みのフラグの組み合わせだけ）
		-     空・最小: NONE
		- 不正なバイト: 該当なし（バイト列を受け取らない）
		-       大きさ: 該当なし（固定長）
		-   仕様の細則: 該当なし
	**/
	function testIsNone() {
		final none = TokenFlags.NONE;
		final unterminated = TokenFlags.UNTERMINATED;
		final missing = TokenFlags.MISSING;
		final unterminatedMissing = TokenFlags.UNTERMINATED | TokenFlags.MISSING;

		Assert.isTrue(none.isNone());
		Assert.isFalse(unterminated.isNone());
		Assert.isFalse(missing.isNone());
		Assert.isFalse(unterminatedMissing.isNone());
	}

	/**
		[TokenFlags.orのdocコメント] どちらかに立っているフラグを、すべて立てた値（和集合）。
		片方だけの値との比較は`==`で、両方を含む値は`has`で確かめる（`has`は`testHas`で別に確かめている）。
		観点:
		-         正常: UNTERMINATED | MISSING は両方を含む
		-         境目: 該当なし（ビットの集合で、切れ目を持たない）
		-     範囲の端: 該当なし（値は定義済みのフラグの組み合わせだけ）
		-     空・最小: NONE | NONE は NONE、NONE との和は相手のまま（左右どちらでも）
		- 不正なバイト: 該当なし（バイト列を受け取らない）
		-       大きさ: 該当なし（固定長）
		-   仕様の細則: 同じフラグどうしの和は変わらない、左右を入れ替えても同じ値
	**/
	function testOr() {
		final none = TokenFlags.NONE;
		final unterminated = TokenFlags.UNTERMINATED;
		final missing = TokenFlags.MISSING;

		Assert.isTrue((none | none).isNone(), "NONE | NONE → NONE");
		Assert.isTrue((none | unterminated) == unterminated, "NONE | UNTERMINATED → UNTERMINATED");
		Assert.isTrue((missing | none) == missing, "MISSING | NONE → MISSING");
		Assert.isTrue((unterminated | unterminated) == unterminated, "UNTERMINATED | UNTERMINATED → UNTERMINATED");

		final both = unterminated | missing;
		Assert.isTrue(both.has(unterminated), "UNTERMINATED | MISSING はUNTERMINATEDを含む");
		Assert.isTrue(both.has(missing), "UNTERMINATED | MISSING はMISSINGを含む");
		Assert.isFalse(both.isNone(), "UNTERMINATED | MISSING はNONEでない");
		Assert.isTrue((missing | unterminated) == both, "MISSING | UNTERMINATED → UNTERMINATED | MISSING と同じ値");
	}
}
