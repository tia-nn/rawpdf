import utest.Assert;

/** M0-1用のダミーテスト。テストの実行経路（utest・Node・eval）を確かめるためだけのもの。M1で本物のテストが入ったら消す。 */
class DummyTest extends utest.Test {
	function testArithmetic() {
		Assert.equals(2, 1 + 1);
	}
}
