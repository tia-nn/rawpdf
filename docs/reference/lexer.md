# Lexer リファレンス

## 0. バイトの分類

Lexerは、トークンの切れ目をバイトの分類で決める。0〜255の各バイトは、次の3つのどれか1つに分類される（ISO 32000-2 7.2節。PDFの全バージョン共通）。分類は`lex/ByteClass.hx`の`ByteClass.of`が返す。

| 分類 | バイト | 個数 |
|---|---|---|
| whitespace | `NUL`(0x00)・`HT`(0x09)・`LF`(0x0A)・`FF`(0x0C)・`CR`(0x0D)・`SP`(0x20) | 6 |
| delimiter | `(`(0x28)・`)`(0x29)・`<`(0x3C)・`>`(0x3E)・`[`(0x5B)・`]`(0x5D)・`{`(0x7B)・`}`(0x7D)・`/`(0x2F)・`%`(0x25) | 10 |
| regular | 上の16バイト以外のすべて。0x80〜0xFFも含む | 240 |

- 以下の章の「regular byte」はregularに分類されるバイト、「regular run」はregular byteが1個以上続く並びを指す
- 改行（CR・LF・CRLF）は独立した分類ではなく、whitespaceに含まれる。コメントの終わり（1章）だけはCR・LFを個別に見る
- 大文字・小文字やASCIIかどうかは分類に関係しない。たとえば`#`・`.`・`+`・`-`はregularで、Nameや数値の一部になり得る

## 1. 構造モードのトークン

先頭バイトで分岐する。「範囲の終端」はLexerOptionsの`end`（既定は`bytes.length`）を指す。

| 種別 | 値 | 区分 | 始まりの条件 | どこまで読むか | 例 | フラグ |
|---|---|---|---|---|---|---|
| `Whitespace` | 0 | trivia | whitespace 6種 | whitespaceが続く限り | `␠\r\n` | – |
| `Comment` | 1 | trivia | `%`（直後が`PDF-`でない） | 行末の手前まで（CR/LFは含めない） | `%%EOF` | – |
| `HeaderMarker` | 50 | token | `%`の直後が`PDF-`（その後ろのバイトに条件は付けない。位置も問わない。バージョン番号の検査は意味解析で行う） | 行末の手前まで | `%PDF-1.7`、`%PDF-abc` | – |
| `LeftBracket` / `RightBracket` | 15/16 | token | `[` / `]` | 1バイト | | – |
| `LeftBrace` / `RightBrace` | 19/20 | token | `{` / `}` | 1バイト | | – |
| `LeftDoubleAngle` | 17 | token | `<`の次も`<` | 2バイト | `<<` | – |
| `RightDoubleAngle` | 18 | token | `>`の次も`>` | 2バイト | `>>` | – |
| `Name` | 12 | token | `/` | `/`を含め、regular byteが続く限り。`#xx`は解釈しない | `/Type`、`/`（空のName） | – |
| `Integer` | 10 | token | regular byte | regular run（2章の分類規則） | `0`、`-12`、`+3`、`007` | – |
| `Real` | 11 | token | 同上 | 同上 | `3.14`、`-.5`、`4.`、`.5` | – |
| `Kw*`（13種） | 30–42 | token（keyword） | 同上 | 同上。バイト列が完全に一致したとき（大文字・小文字を区別） | 2章の表 | – |
| `Unknown` | 60 | token | (a) `>`の次が`>`でない（範囲の終端を含む）<br>(b) 単独の`)`（リテラル文字列の外）<br>(c) 数値にもキーワードにも当たらないregular run | (a)(b) 1バイト<br>(c) regular run全体 | `>`、`)`、`123e5`、`1-2`、`+`、`12.34.56`、`Obj` | – |
| `LiteralString` | 13 | token | `(` | 括弧の深さが0に戻る`)`まで。エスケープされた括弧は深さに数えない | `(a(b)c)` | 範囲の終端で打ち切ったら`UNTERMINATED`。`\`が範囲の最後の1バイトなら、`\`まで含めて`UNTERMINATED` |
| `HexString` | 14 | token | `<`の次が`<`でない（範囲の終端を含む） | `>`まで。不正な文字があっても止めない | `<48 65>` | 範囲の終端で打ち切ったら`UNTERMINATED` |
| `EndOfFile` | 61 | token | カーソルが範囲の終端にある | 幅0。何度呼ばれても返し続ける | | – |

## 2. regular runの分類

regular byteが続く限り（最長一致で）切り出し、内容で次の順に分類する。

1. **数値**: 先頭に1個以下の符号（`+`/`-`）、続いて数字と`.`だけが並び、数字が1個以上、`.`は1個以下。`.`があれば`Real`、無ければ`Integer`（ISO 32000-2 7.3.3節）
   - `.`は先頭・末尾・途中のどこでもよい: `4.`・`.5`・`-.002`は`Real`
   - 先頭の`0`は禁じられていない: `007`・`-0`は`Integer`
   - 数値にならない例: 数字を含まない列（`+`・`-`・`.`・`+.`）、符号が2個以上・途中にある列（`--1`・`1-2`）、`.`が2個以上の列（`12.34.56`。分けずにrun全体を1つの`Unknown`にする）、指数表記・基数表記（`123e5`・`16#FF`。7.3.3節で禁止）
   - 値の範囲（整数が32ビットに収まるか等。ISO 32000-2 付録C）はLexerでは見ない。意味解析で扱う
2. **キーワード**: 下の表と完全に一致すれば、対応する`Kw*`
3. **どちらでもない**: `Unknown`

| 長さ | バイト列 → 種別 |
|---|---|
| 1 | `R`→`KwR`、`n`→`KwN`、`f`→`KwF` |
| 3 | `obj`→`KwObj` |
| 4 | `true`→`KwTrue`、`null`→`KwNull`、`xref`→`KwXref` |
| 5 | `false`→`KwFalse` |
| 6 | `endobj`→`KwEndobj`、`stream`→`KwStream`（3章のstream本体モードに入る） |
| 7 | `trailer`→`KwTrailer` |
| 9 | `endstream`→`KwEndstream`、`startxref`→`KwStartxref` |

## 3. stream本体モードのトークン

`KwStream`を返した直後に、Lexerは次の順にトークンを返し、構造モードに戻る。stream本体の終わりは`/Length`を見ずに、`endstream`のバイト列を探して決める。

| 順 | 種別 | 内容 | フラグ |
|---|---|---|---|
| 1 | `Whitespace`（出ない場合もある） | `stream`の直後の改行（下の「本体の始まり」）。構造モードの空白の読み方（whitespaceが続く限り）は使わない | – |
| 2 | `StreamBody`（値51） | 本体。長さ0でも必ず出す | `endstream`が見つからなければ`UNTERMINATED` |

**本体の始まり**: `stream`の直後の次のどれか1つだけを表の1番目の`Whitespace`にし、それより後ろのバイトは空白であっても本体に含める。

- `CRLF`または`LF` → その改行だけ（ISO 32000-2に準拠した書き方）
- `CR`だけ → その`CR`だけ
- `SP`・`HT`が続き、その直後に改行がある（`stream  \r\n`など） → 空白の並びと改行
- どれにも当たらない → `Whitespace`を出さず、本体は`stream`の直後から始まる

**本体の終わり**: 本体の始まりから範囲の終端までで`endstream`のバイト列を探す。

- 候補にするのは、直後のバイトがwhitespace・delimiterであるか、範囲の終端である出現だけ（`endstreamX`のようにregular byteが続くものは候補にしない）
- 候補のうち、直前のバイトがwhitespaceである最初の出現を採る。無ければ、直前のバイトを問わず最初の候補を採る
- 採った`endstream`の直前に改行（`CRLF`・`LF`・`CR`のどれか）があれば、その改行1つだけを本体に含めない。この改行は通常の`Whitespace`として、次の`KwEndstream`の前に出る
- 候補が無ければ、本体は範囲の終端までとし、`UNTERMINATED`を付ける

本体のバイナリの中に偶然「whitespace＋`endstream`」の並びがあると、`/Length`が示す本来の位置より手前で本体が終わる。

## 4. Lexerが出さないもの

- ノード種別（値100以上）すべて
- `MISSING`フラグ付きのトークン。これはパーサが作る幅ゼロの合成トークン
