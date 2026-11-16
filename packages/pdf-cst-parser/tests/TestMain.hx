/** テストの入口。テストクラスを足したら、ここの配列に加える。 */
class TestMain {
	public static function main() {
		utest.UTest.run([new DummyTest()]);
	}
}
