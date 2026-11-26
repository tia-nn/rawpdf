package rawpdf.cst.syntax;

import haxe.Exception;
import haxe.io.Bytes;
import utest.Assert;

/** コンストラクタが例外を投げるかどうかを確かめるケース（`GreenNodeTest`の`ConstructCase`と同じ形）。 */
private typedef ConstructCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final make:() -> Void;
	final throws:Bool;
}

/** `get(i)`の結果を確かめるケース。`expected`が`null`なら例外を期待する。 */
private typedef GetCase = {
	/** 失敗したときのメッセージに出す、ケースの説明。 */
	final name:String;

	final span:ByteSpan;
	final i:Int;
	final expected:Null<Int>;
}

/**
	`ByteSpan`のテスト。根拠は`ByteSpan`のクラスと各メンバーのdocコメント。
	`@throws`に挙がっていない呼び出し方は例外を投げない、と読む。
	元のバイト列は`abcd`（`0x61 0x62 0x63 0x64`）を基本にする。
**/
class ByteSpanTest extends utest.Test {
	static inline function abcd() {
		return Bytes.ofString("abcd");
	}

	static final CONSTRUCT_CASES:Array<ConstructCase> = [
		{name: "全体（0, 4） → 作れる", make: () -> new ByteSpan(abcd(), 0, 4), throws: false},
		{name: "途中（1, 2） → 作れる", make: () -> new ByteSpan(abcd(), 1, 2), throws: false},
		{name: "末尾までちょうど（3, 1） → 作れる", make: () -> new ByteSpan(abcd(), 3, 1), throws: false},
		{name: "末尾の位置で長さ0（4, 0） → 作れる", make: () -> new ByteSpan(abcd(), 4, 0), throws: false},
		{name: "空のsourceで（0, 0） → 作れる", make: () -> new ByteSpan(Bytes.alloc(0), 0, 0), throws: false},
		{name: "末尾を1超える（3, 2） → 例外", make: () -> new ByteSpan(abcd(), 3, 2), throws: true},
		{name: "startがsource.lengthより大きい（5, 0） → 例外", make: () -> new ByteSpan(abcd(), 5, 0), throws: true},
		{name: "startが負（-1, 1） → 例外", make: () -> new ByteSpan(abcd(), -1, 1), throws: true},
		{name: "lengthが負（0, -1） → 例外", make: () -> new ByteSpan(abcd(), 0, -1), throws: true},
		{name: "start + lengthがIntの上限を超える（1, 0x7FFFFFFF） → 例外", make: () -> new ByteSpan(abcd(), 1, 0x7FFFFFFF), throws: true},
	];

	/**
		[ByteSpan.newのdocコメント] `start`か`length`が0未満、または`start + length`が`source.length`より大きいと例外。
		観点:
		-         正常: 全体、途中の範囲
		-         境目: `start + length`が`source.length`と等しい（作れる）と1大きい（例外）
		-     範囲の端: `start`が`source.length`ちょうどで長さ0（作れる）、`source.length`より大きい（例外）
		-     空・最小: 長さ0、空の`source`
		- 不正なバイト: 該当なし（中身を読まない）
		-       大きさ: `start + length`が`Int`の上限を超える組み合わせ（例外。溢れて通らないこと）
		-   仕様の細則: 負の`start`・`length`
	**/
	function testConstruct() {
		for (c in CONSTRUCT_CASES) {
			if (c.throws) {
				Assert.raises(c.make, Exception, c.name);
			} else {
				try {
					c.make();
					Assert.pass(c.name);
				} catch (e:Exception) {
					Assert.fail('${c.name}: unexpected exception: ${e.message}');
				}
			}
		}
	}

	/** [ByteSpan.source・start・lengthのdocコメント] 作るときに渡した値がそのまま読める（`source`はコピーせずに参照する）。 */
	function testFields() {
		final source = abcd();
		final span = new ByteSpan(source, 1, 2);
		Assert.isTrue(span.source == source, "source should be the given Bytes itself");
		Assert.equals(1, span.start, "start");
		Assert.equals(2, span.length, "length");
	}

	// testGetで使う範囲
	static final bc = new ByteSpan(abcd(), 1, 2);
	static final high = new ByteSpan(Bytes.ofHex("00ff80"), 1, 2);
	static final empty = new ByteSpan(abcd(), 2, 0);

	static final GET_CASES:Array<GetCase> = [
		{
			name: "\"bc\"のget(0) → 0x62（sourceの先頭のaではない）",
			span: bc,
			i: 0,
			expected: 0x62
		},
		{
			name: "\"bc\"のget(1) → 0x63",
			span: bc,
			i: 1,
			expected: 0x63
		},
		{
			name: "\"bc\"のget(2)（length） → 例外（後ろのdは読まない）",
			span: bc,
			i: 2,
			expected: null
		},
		{
			name: "\"bc\"のget(-1) → 例外（前のaは読まない）",
			span: bc,
			i: -1,
			expected: null
		},
		{
			name: "長さ0の範囲のget(0) → 例外",
			span: empty,
			i: 0,
			expected: null
		},
		{
			name: "0xFFのバイト → 255",
			span: high,
			i: 0,
			expected: 0xFF
		},
		{
			name: "0x80のバイト → 128",
			span: high,
			i: 1,
			expected: 0x80
		},
	];

	/**
		[ByteSpan.getのdocコメント] 範囲の先頭から`i`番目のバイト。`i`が0未満か`length`以上なら例外。
		観点:
		-         正常: 範囲の先頭・末尾のバイト
		-         境目: `i == length`（例外。範囲のすぐ外に`source`のバイトがあっても読まない）
		-     範囲の端: `i == -1`（例外。範囲のすぐ前に`source`のバイトがあっても読まない）
		-     空・最小: 長さ0の範囲の`get(0)`（例外）
		- 不正なバイト: 0x80以上のバイト（そのまま0〜255の値で返る）
		-       大きさ: 該当なし
		-   仕様の細則: `i`は範囲の先頭からの位置で、`source`の先頭からではない
	**/
	function testGet() {
		for (c in GET_CASES) {
			final expected = c.expected;
			if (expected == null) {
				Assert.raises(() -> c.span.get(c.i), Exception, c.name);
			} else {
				Assert.equals(expected, c.span.get(c.i), c.name);
			}
		}
	}

	/**
		[ByteSpan.toBytesのdocコメント] 範囲のバイト列をコピーして返す。返した`Bytes`は`source`と共有しない。
		観点:
		-         正常: 途中の範囲の中身
		-         境目: 該当なし
		-     範囲の端: 該当なし（範囲は作るときに検査済み。testConstruct）
		-     空・最小: 長さ0の範囲（長さ0の`Bytes`）
		- 不正なバイト: 該当なし（中身を解釈しない）
		-       大きさ: 該当なし
		-   仕様の細則: 共有しない（返した`Bytes`を書き換えても`source`は変わらない）
	**/
	function testToBytes() {
		final source = abcd();
		final copied = new ByteSpan(source, 1, 2).toBytes();
		Assert.equals("bc", copied.toString(), "\"bc\"の範囲 → bc");
		Assert.equals(0, new ByteSpan(source, 2, 0).toBytes().length, "長さ0の範囲 → 長さ0");

		copied.set(0, "z".code);
		Assert.equals("abcd", source.toString(), "返したBytesを書き換えても、sourceは変わらない");
	}
}
