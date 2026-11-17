package rawpdf.cst.syntax;

import utest.Assert;

class TokenFlagsTest extends utest.Test {
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
}
