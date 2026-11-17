# stream境界キャッシュ（StreamBodyHint）

インクリメンタル再パースで、stream本体の終わり（`endstream`の位置）を前回の結果から再利用するための「答えのメモ」。巨大なstreamを持つオブジェクトの辞書を1文字書き換えるたびに、本体全体を走査し直すのを避ける。

## なぜ必要か

### stream本体の境界は、走査しないとわからない

このパーサは`/Length`を見ずに、`stream`の後ろから`endstream`というバイト列を探して本体の終わりを決める（基本設計4.3節）。`/Length`は間接参照（`/Length 6 0 R`）になり得て、パーサだけでは値がわからないためである。

その代わり、本体が数十MBあれば、境界を決めるたびに数十MBを走査することになる。

### 再パースは「オブジェクト1個」を単位に字句解析し直す

インクリメンタル再パース（基本設計5.5.1節）は、編集位置を含む`IndirectObject`（`n g obj … endobj`）を丸ごと字句解析し直す。オブジェクトの中にstreamがあれば、辞書の1文字を書き換えただけでも、本体の走査がもう一度走る。

```
5 0 obj
<< /Length 1000000 /Filter /FlateDecode >>   ← ここの1文字を編集
stream
……1MBのバイナリ……                           ← 再字句解析で、これを全部走査し直す
endstream
endobj
```

キー入力ごとの予算は10ms（基本設計2.3.1節）なので、数十MBの走査はそれだけで予算を超える。そこで「境界が変わり得ない編集なら、前回の答えを使う」（基本設計4.3節の実装要件(b)）。その答えを運ぶ入れ物が`StreamBodyHint`である。

## どういう仕組みか

### 渡す側（reparse）と使う側（Lexer）

```
reparse                                   Lexer
───────                                   ─────
旧木のStreamClauseごとに
「この編集で境界が変わり得ないか」を判定
  → 変わり得ないなら、旧境界を
    編集量だけずらしてヒントにする
streamBodyHints: Map<bodyStart, Hint> ──→ KwStreamを出した後、bodyStartを求める
                                          ヒントがあり、検証に通れば
                                            → その境界をそのまま使う（走査しない）
                                          無い・検証に落ちたら
                                            → findEndstreamで走査する
```

- **キーは新しい座標での`bodyStart`**（本体の開始位置）。Lexerは`stream`直後のEOLを読んだ時点で`bodyStart`を知っているので、そこで引ける
- **値は`bodyEnd`と`endstreamStart`**（どちらも新しい座標）。2つあるのは、その間に「本体から除外したEOL」（`endstream`の前のトリビア。基本設計4.3節のbodyEnd規則）があるため。両方持てば、EOL規則を計算し直さずに済む

### 「変わり得ない」の条件

編集範囲（旧座標の閉区間`[start, start + deletedLength]`）が、閉区間`[streamの開始, endstreamの終端]`に**接触も交差もしない**こと（詳細設計8章）。本体のバイトだけでなく、その外側の数バイトも境界の決定に関わるので、本体との交差を見るだけでは足りない。

| 編集した場所 | 境界が変わる理由 |
|---|---|
| `stream`の直前1バイト | `xstream`になると、キーワードとして成立しない |
| `stream`直後のEOL | 本体の開始位置が変わる |
| 本体直後のEOL | `endstream`の「直前が空白」の条件が崩れ、後ろにある別の`endstream`が選ばれ得る |
| `endstream`の直後1バイト | `endstreamX`は候補から外れる |

辞書の中（`/Length 1000000`の部分）の編集は、このどれにも触れないので、ヒントを使える。

### Lexerの防御的検査

Lexerは、ヒントを使う前に次の2点を確かめる（詳細設計6.2節）。

- `endstreamStart + 9 <= end`（字句解析の範囲内に収まる）
- `bytes[endstreamStart .. +9]`が`endstream`に一致する

条件の判定が正しければ常に通るが、reparse側のバグで間違ったヒントが渡されても、誤った木を作らずに走査に戻れる。

## 具体例

`/Length 1000000`を`/Length 999999`に書き換える（1バイト減る）。

```
旧:  … stream\n [本体 bodyStart=100 … bodyEnd=1000100] \n endstream …
                                                       ↑ endstreamStart=1000101
編集: 辞書の中、offset 30 で1バイト削除（stream より前）

ヒント（新座標＝旧座標 − 1）:
  key  = 99
  value = { bodyEnd: 1000099, endstreamStart: 1000100 }
```

Lexerは新しいバイト列で`stream\n`を読み、`bodyStart = 99`を得る。ヒントを引き、`1000100`から9バイトが`endstream`であることを確かめて、1MBを走査せずに`StreamBody`（長さ1000000）を返す。

逆に、本体直後の`\n`を消す編集は、閉区間に触れるのでヒントは作らない。Lexerは`findEndstream`で走査し直す。

## このプロジェクトでの使われ方

- 基本設計4.3節: 境界決定のアルゴリズムと、実装要件(b)（再利用の条件）
- 詳細設計6.2節: `StreamBodyHint`と`LexerOptions.streamBodyHints`の型。Lexerがヒントを使う手順
- 詳細設計8章「stream境界キャッシュ」: reparseがヒントを作る条件
- WBS: Lexerの範囲指定はM5-2、ヒントの作成と利用はM5-8。それより前（フルパースだけの段階）では、ヒントは常に空

## 関連

- [Green/Red木](green-red-tree.md) — 再パースで変わらなかった部分木を使い回す仕組み
- [バイト分類（ByteClass）](byte-class.md) — `endstream`の直前・直後のバイト条件で使う分類

## 参考

- tree-sitterの`ts_parser_parse`に旧木を渡すインクリメンタルパース（再利用の判定を旧木から行う考え方）
