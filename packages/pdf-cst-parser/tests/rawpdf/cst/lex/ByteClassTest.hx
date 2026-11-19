package rawpdf.cst.lex;

import haxe.Exception;
import utest.Assert;

/**
	ByteClass.ofのテスト。根拠はLexerリファレンス0章（バイトの分類）と、ByteClass.ofのdocコメント（範囲外の例外）。

	観点:
	-         正常: 0〜255の全バイト（testEveryByte）、種類ごとの個数（testCounts）
	-         境目: 該当なし（1バイトずつ分類するので、隣のバイトの影響を受けない）
	-     範囲の端: -1・256で例外（testOutOfRangeByte）。0と255はtestEveryByteに含まれる
	-     空・最小: 該当なし（入力は整数1つ）
	- 不正なバイト: 0x80・0xFF（testConfusingBytes）。範囲外の値は「範囲の端」で見る
	-       大きさ: 該当なし（表を引くだけ）
	-   仕様の細則: NUL・VT・数値やNameに出る記号・`\`（testConfusingBytes）
**/
class ByteClassTest extends utest.Test {
	/**
		期待値。表とは別の書き方（switch）で、Lexerリファレンス0章の表をそのまま写す。
		表の組み立てを間違えたとき、同じ間違いがここに入らないようにするため。
	**/
	static function expected(b:Int):ByteClass {
		return switch b {
			case 0x00 | 0x09 | 0x0A | 0x0C | 0x0D | 0x20: Whitespace;
			case "(".code | ")".code | "<".code | ">".code | "[".code | "]".code | "{".code | "}".code | "/".code | "%".code: Delimiter;
			case _: Regular;
		}
	}

	/** [Lexerリファレンス0章] 0〜255の全バイトが、表のとおりに分類される。 */
	function testEveryByte() {
		for (b in 0...256) {
			Assert.equals(expected(b), ByteClass.of(b), 'byte=$b');
		}
	}

	/** [ByteClass.ofのdocコメント] 0〜255の範囲外（-1・256）は例外。 */
	function testOutOfRangeByte() {
		Assert.raises(() -> ByteClass.of(-1), Exception);
		Assert.raises(() -> ByteClass.of(256), Exception);
	}

	/** [Lexerリファレンス0章 表の「個数」の列] whitespace 6・delimiter 10・regular 240。 */
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
		[Lexerリファレンス0章 表と注記（`#`・`.`・`+`・`-`はregular、0x80〜0xFFもregular）] 間違えやすいバイト。
		期待値の写し間違いがあっても、ここで気づけるように個別に書く。
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
}
