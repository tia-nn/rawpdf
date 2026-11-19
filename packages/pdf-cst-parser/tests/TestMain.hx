/** テストの入口。テストクラスを足したら、ここの配列に加える。 */
class TestMain {
	public static function main() {
		utest.UTest.run([
			new rawpdf.cst.syntax.SyntaxKindTest(),
			new rawpdf.cst.syntax.TokenFlagsTest(),
			new rawpdf.cst.syntax.GreenNodeTest(),
			new rawpdf.cst.syntax.GreenBuilderTest(),
			new rawpdf.cst.lex.ByteClassTest(),
			new rawpdf.cst.lex.LexerTest()
		]);
	}
}
