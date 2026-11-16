# corpus/

パッケージ横断で共有するテストコーパス（統括設計6章）。パーサのスナップショット、意味解析の診断検証、LSPの往復性テストが同じファイルを使う。

- ファイルはバイト列そのものが正。`.gitattributes`で`binary`扱いにして、gitの改行変換を止めている
- 破損ファイルは「壊れ方を1つだけ」にしてある。壊した箇所以外（xrefのオフセット・`startxref`・`/Length`）は、そのファイルの実際のバイト位置に合わせて計算し直してある
- どのファイルも2行目に非ASCIIバイトのコメント行（`%\xe2\xe3\xcf\xd3`）がある（バイナリファイルであることを示す慣習。ISO 32000-1 7.5.2）
- xrefエントリは20バイト固定。LF版は`… n \n`（空白＋LF）、CRLF版は`… n\r\n`

## 正常系

| ファイル | 目的 |
|---|---|
| `minimal-lf.pdf` | 1ページの最小PDF。改行はすべてLF。オブジェクトは Catalog(1) / Pages(2) / Page(3) / Contents stream(4) / Font(5) |
| `minimal-crlf.pdf` | `minimal-lf.pdf`と同じ内容で、改行をすべてCRLFにしたもの（stream本体の中も）。EOLトリビアの扱いと、`stream`直後のCRLFの扱いを見る |
| `incremental-update.pdf` | incremental update。`minimal-lf.pdf`の後ろに、オブジェクト4（本文）を差し替える2つ目のセグメント（object＋xref＋trailer＋startxref＋`%%EOF`）を追記。2つ目のxrefは`0 1`と`4 1`の2サブセクション、trailerに`/Prev`。Segmentが2つになることを確認する（WBS M4-4） |

## 破損系

| ファイル | 壊れ方 | 見たいこと |
|---|---|---|
| `missing-header.pdf` | 先頭の`%PDF-1.7`行とバイナリコメント行が無く、いきなり`1 0 obj`から始まる | ヘッダ欠落でもオブジェクト以降を読めるか（パーサ基本5.2節） |
| `missing-endobj.pdf` | オブジェクト3（Page）の`endobj`が無い。直後に`4 0 obj`が続く | `n g obj`を同期点として次のオブジェクトから回復できるか。missing token＋診断 |
| `unterminated-literal-string.pdf` | オブジェクト6（`/Info`）の`/Title (Hello (rawpdf) >>`が閉じていない（入れ子の`(`が1つ残る）。trailerから`/Info 6 0 R`で参照 | 閉じないliteral stringがEOFまで飲み込み、`Unterminated`フラグが立つか。xref・trailer・startxrefも文字列の中に入ってしまう |

## 追加するときの約束

- 1ファイル＝1つの目的。破損系は壊し方を1つに絞る
- この表に1行追記する
- 実在PDF（OSSのテストスイート由来）を入れるときはライセンスを確認し、出典をこの表に書く（統括設計 未決事項、WBS後半）
