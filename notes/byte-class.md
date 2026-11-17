# バイト分類（ByteClass）

PDFの字句解析は、全256バイトを Whitespace / Delimiter / Regular の3種に分けた表から始まる。トークンの「どこで切れるか」は、ほぼこの3分類だけで決まる。

## なぜ必要か

PDFのトークンには区切り記号の規則がほとんど無い。`/Type/Page`は空白なしで2つのName、`obj<<`は`obj`と`<<`、`123 0 R`は空白で3つに切れる。これらを「バイトの種類が変わったところで切る」という1つの規則で扱うために、バイトの種類を先に決めておく。

## どういう仕組みか

ISO 32000（全バージョン共通）の分類:

| 種類 | バイト |
|---|---|
| Whitespace（6個） | `0x00` `0x09` `0x0A` `0x0C` `0x0D` `0x20` |
| Delimiter（10個） | `(` `)` `<` `>` `[` `]` `{` `}` `/` `%` |
| Regular | 上記16個以外すべて（`0x80`〜`0xFF`、`#` `-` `.` も含む） |

これを256要素の配列にしておき、`table[b]`の1回の参照で種類を得る。16個の値と比較する`if`の連鎖をホットループ（全バイトを1回ずつ通るループ）から追い出すのが目的。分類の定義が1か所に集まるので、「空白は何か」の判断がレキサーのあちこちでずれることも防げる。

## 具体例

`1 0 obj<</Type/Page>>` をレキサーが読むとき:

```
1        Regular run → 次の' '(Whitespace)で終わる → Integer
' '      Whitespace run
0        Regular run → Integer
' '      Whitespace
obj      Regular run → '<'(Delimiter)で終わる → KwObj
<<       Delimiterで分岐 → 1バイト先読みで '<<'
/Type    '/'で分岐 → Regularを貪欲に消費 → 次の'/'(Delimiter)で終わる
/Page    同上。'>'で終わる
>>
```

`/Type/Page`が2つのNameになるのは、`/`がDelimiterだから。逆に`-1.5`や`/A#20B`が1つのトークンになるのは、`-` `.` `#`がRegularだから。

## このプロジェクトでの使われ方

- 実装: `lex/ByteClass.hx`（パーサ詳細設計6.1節）。分類の定義はパーサ基本設計4.1節。WBS M1-2
- 先頭バイトの分岐: Delimiterなら記号ごとの分岐、Regularならregular runサブスキャン（基本設計4.2節）
- 終端の判定: Whitespace run・Name・regular runの「どこまで続くか」
- 16進文字列: 中の空白を読み飛ばす（基本設計4.2節）
- `endstream`の候補判定: 直後がWhitespace・DelimiterかEOF、直前がWhitespaceかを見る（基本設計4.3節）。`endstreamXYZ`はキーワードとして成立しないので候補にしない

## 関連

- [SyntaxKindと`enum abstract`](syntax-kind-enum-abstract.md)
- [Haxeの`inline`](haxe-inline.md) — `isWhitespace(b)`のような1行の判定関数に使える
