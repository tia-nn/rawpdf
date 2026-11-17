package rawpdf.cst.lex;

import haxe.Exception;
import utest.Assert;

/** ByteClass.ofのテスト（パーサ基本設計4.1節・詳細設計6.1節）。 */
class ByteClassTest extends utest.Test {
	/**
		期待値。表とは別の書き方（switch）で、基本設計4.1節の分類をそのまま写す。
		表の組み立てを間違えたとき、同じ間違いがここに入らないようにするため。
	**/
	static function expected(b:Int):ByteClass {
		return switch b {
			case 0x00 | 0x09 | 0x0A | 0x0C | 0x0D | 0x20: Whitespace;
			case "(".code | ")".code | "<".code | ">".code | "[".code | "]".code | "{".code | "}".code | "/".code | "%".code: Delimiter;
			case _: Regular;
		}
	}

	/** 0〜255の全バイトが期待どおりに分類される。 */
	function testEveryByte() {
		for (b in 0...256) {
			Assert.equals(expected(b), ByteClass.of(b), 'byte=$b');
		}
	}

	/** -1,256でthrowされる */
	function testOutOfRangeByte() {
		Assert.raises(() -> ByteClass.of(-1), Exception);
		Assert.raises(() -> ByteClass.of(256), Exception);
	}

	/** 完了条件（WBS M1-2）の個数: whitespace 6種・delimiter 10種・残り240個がregular。 */
	function testCounts() {
		var whitespace = 0;
		var delimiter = 0;
		var regular = 0;
		for (b in 0...256) {
			switch ByteClass.of(b) {
				case Whitespace:
					whitespace++;
				case Delimiter:
					delimiter++;
				case Regular:
					regular++;
			}
		}
		Assert.equals(6, whitespace);
		Assert.equals(10, delimiter);
		Assert.equals(240, regular);
	}

	/**
		間違えやすいバイト。期待値の写し間違いがあっても、ここで気づけるように個別に書く。
	**/
	function testConfusingBytes() {
		// NULは空白に入る
		Assert.equals(ByteClass.Whitespace, ByteClass.of(0x00));
		// VT(0x0B)は多くの言語では空白だが、PDFでは空白に入らない
		Assert.equals(ByteClass.Regular, ByteClass.of(0x0B));
		// 数値・Nameの中に現れる記号はregular（`-1.5`・`/A#20B`・`+3`が1トークンになる）
		Assert.equals(ByteClass.Regular, ByteClass.of("-".code));
		Assert.equals(ByteClass.Regular, ByteClass.of("+".code));
		Assert.equals(ByteClass.Regular, ByteClass.of(".".code));
		Assert.equals(ByteClass.Regular, ByteClass.of("#".code));
		// `\`は文字列の中でだけ意味を持ち、分類上はregular
		Assert.equals(ByteClass.Regular, ByteClass.of("\\".code));
		// 高位バイトはregular
		Assert.equals(ByteClass.Regular, ByteClass.of(0x80));
		Assert.equals(ByteClass.Regular, ByteClass.of(0xFF));
	}

	function testIsRegular() {
		Assert.isTrue(ByteClass.Regular.isRegular());
		Assert.isFalse(ByteClass.Whitespace.isRegular());
		Assert.isFalse(ByteClass.Delimiter.isRegular());
	}

	function testIsWhitespace() {
		Assert.isFalse(ByteClass.Regular.isWhitespace());
		Assert.isTrue(ByteClass.Whitespace.isWhitespace());
		Assert.isFalse(ByteClass.Delimiter.isWhitespace());
	}

	function testIsDelimiter() {
		Assert.isFalse(ByteClass.Regular.isDelimiter());
		Assert.isFalse(ByteClass.Whitespace.isDelimiter());
		Assert.isTrue(ByteClass.Delimiter.isDelimiter());
	}
}
