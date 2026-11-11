# PDF意味解析パッケージ 設計ドキュメント

最終更新: 2026-11-12（実装言語をHaxeに変更: 7章。統括ドキュメント3.1節）
用途: CSTパーサパッケージの上に意味情報（参照解決・文書構造・値デコード・意味診断）を提供する単体パッケージの設計方針。今後のAI支援（実装・レビュー）における前提知識として利用する。
上位ドキュメント: `pdf-editor-overview-design.md`（全体統括。ドキュメントツリー・横断原則・性能予算はそちらが正）
下位ドキュメント: `pdf-semantics-detailed-design.md`（詳細設計。モジュール構成・型定義・シグネチャ）
関連ドキュメント: `pdf-cst-parser-design.md`（依存先）、`pdf-lsp-editor-design.md`（本パッケージに依存する）

3パッケージはモノレポ内の独立パッケージとして管理する（統括ドキュメント3章参照）。

---

## 1. 目的・位置づけ

CSTパーサが構築する「構文の木」に対し、「意味」（オブジェクト番号の解決、リビジョン構造、文書構造、トークンのデコード値）を与える層。3パッケージの直列依存の中間に位置する。

```
pdf-cst-parser …… 他のどのパッケージにも依存しない
   ↑ 依存
pdf-semantics（本ドキュメント） …… parserのみに依存
   ↑ 依存
pdf-lsp-editor …… semanticsとparser（reparse・診断型）の両方に依存
```

- LSP関連の型・パッケージには一切依存しない。診断等は独自型で表現し、LSPプロトコルへの変換はLSP層の責務とする。
- CSTは不変・ロスレスのまま一切変更しない。意味情報はCSTへの**オーバーレイ**（CSTノードを参照する別データ構造）として保持する。

---

## 2. 要件

- **error-tolerant**: `ErrorNode`・missing tokenを含むCSTでも動作する。解決できない要素は例外ではなく「解決不能」という値＋診断として表現し、解析全体を中断しない。
- **不変スナップショット**: `SemanticModel`は特定の`SyntaxTree`に対する不変のビュー。編集で木が変わったら新しいモデルを作る（parserのGreen木と同じ思想）。
- **遅延評価**: 編集のたびに全意味解析をやり直さない。eagerに構築するのは論理インデックス等の軽量な骨格のみとし、残りは初回アクセス時に計算してメモ化する。
- **インクリメンタル更新への発展余地**: Green木は構造共有されるため、編集で変わらなかったサブツリーのノード同一性を使った差分更新が将来可能な構造にしておく。v1は「eager部分の全再構築＋lazy部分の破棄」から始める（3.1節の性能目標参照）。

---

## 3. v1スコープ

**含む**: 論理インデックス、参照解決、リビジョンモデル、文書構造グラフ、値デコード、意味診断（4章）。

**含まない（v2以降）**:

- 辞書スキーマ検証（`/Type`に基づく網羅的な型チェック・必須キー欠落検証）。文書構造グラフの構築に必要な最小限の型判定（3.4節）のみv1で行う。
- object stream内オブジェクトの展開（パーサv2と連動）。
- 暗号化文字列の復号、content stream解析。

### 3.1 論理インデックス（パーサパッケージから移管）

`(オブジェクト番号, 世代番号) → IndirectObject CSTノード`の対応表。パーサ仕様書5.4節にあった「CST実測を正とする」ポリシーごと本パッケージに移管する。

- **CSTがトップダウンで実際に見つけた`IndirectObject`群を正とし、xrefの宣言オフセットは突き合わせて食い違いを診断にする**（鵜呑みにしない）。
- 重複定義: 同一`(num, gen)`が複数Segmentに存在する場合、incremental updateの意味論に従い**物理的に後（新しいリビジョン）のSegmentの定義を有効**とする。同一Segment内での重複は診断を付与し、後勝ちで解決する。
- 構築はCSTトップレベルの1走査。**性能目標: 編集1回あたりの再構築を典型ファイルで2ms以内**（統括ドキュメント5章のフレーム予算16msのうち本パッケージに配分された2msに対応。パーサ仕様書10章にあった「再構築コストが性能目標を圧迫しないか」の検討事項も本パッケージに引き継ぐ）。

### 3.2 参照解決

- `resolve(referenceNode)` → 有効な`IndirectObject` または「解決不能」（dangling診断付き）。
- 世代番号の扱い: 実世界のビューア実装には世代番号を無視して番号のみで解決するものが多い。**`(num, gen)`完全一致を優先し、番号一致・世代不一致しかない場合はそれにフォールバック解決したうえで診断を付与する**（壊れたファイルでもナビゲーションが機能することを優先）。
- `resolve`自体は1段のみ。多段の解決（参照チェーン）を行う文書構造グラフ側でvisited setにより循環を防護する。

### 3.3 リビジョンモデル

- CSTの`Segment`列を`Revision`列として意味づけする（物理順＝古→新）。各Revisionはtrailer・xref・startxref・`/Prev`値への参照を持つ。
- `/Prev`チェーンとファイル物理順の突き合わせを行い、不整合（チェーン切れ・順序矛盾・自己参照）を診断にする。
- 「Revision N時点で可視なオブジェクト集合」を返すAPIを持つ（エディタの「この版では」表示用途。xrefの`f`エントリによる削除を反映する。詳細設計6章）。v1では最新リビジョンのビューを主とし、過去リビジョンのビューはlazyに構築する。
- linearized PDFは物理先頭のtrailerが後方のmain xrefを`/Prev`で指すため、「物理順＝古→新」の前提が正常なファイルでも成り立たない。`/Linearized`辞書の検出時は`/Prev`チェーン診断を抑制する（詳細設計6章。linearized構造の完全な意味づけはv2）。

### 3.4 文書構造グラフ

- 最新リビジョンのtrailer `/Root` → Catalog → `/Pages`ツリー → ページ列挙、という骨格グラフを構築する。
- **visited setによる循環検出を必須とする**（page treeの循環は実在する破損パターンとして頻出）。
- ここで行う型判定は`/Type /Pages`・`/Type /Page`・`/Kids`配列の識別など、グラフ構築に必要な最小限のみ。網羅的なスキーマ検証はv2。
- Catalog欠落・`/Root`がdangling等の場合も、到達できた範囲の部分グラフ＋診断を返す（error-tolerant要件）。

### 3.5 値デコード

パーサのトークンはテキストを持たず、生バイト範囲（Redビューの`{ kind, start, length }`アクセサ）のみで表現される（パーサ仕様書5.1節）。その「意味値」へのデコードを本パッケージが担う。

- **Name**: `#xx`の解決。不正な`#`列は生バイトのまま＋診断フラグ。
- **LiteralString**: エスケープ（`\n` `\t` `\(` `\)` `\\` `\ddd` 行継続）の解決。Unterminatedなトークンも読めた範囲でデコードする。
- **HexString**: 空白除去、奇数桁は末尾0詰め（仕様通り）。
- **文字列のテキスト解釈**: バイト列（常に返す）とテキスト（解釈できた場合のみ）を分離して返す。テキスト解釈はUTF-16BE BOM／UTF-8 BOM（PDF 2.0）／それ以外はPDFDocEncodingの順で判定。
- **Integer/Real**: JS numberへの変換。精度落ち・桁あふれは診断フラグ付き。
- **遅延＋メモ化**: デコードは要求時に行い、greenトークンをキーとするWeakMapでキャッシュする（モデル再構築をまたいで、変わらなかったトークンのキャッシュが自然に生き残る）。

### 3.6 `/Length`不一致診断（パーサパッケージから移管）

パーサ仕様書4.3節で「v1必須」とされた安全網。`/Length`は間接参照になり得るため、解決には3.2節の参照解決機構が必要であり、実装先として本パッケージが適切（パーサは実測stream長とdictのCSTを提供するのみ）。

- `/Length`値（直接値、または参照解決後の値）とCST実測のstream長を比較し、不一致を診断にする。
- `/Length`自体が解決不能（dangling・非数値）な場合はその旨の別診断とする。
- **v1必須**という位置づけはパーサ仕様書から引き継ぐ（`endstream`早期一致という意図的トレードオフの検知手段であるため）。

---

## 4. 診断

- `Diagnostic`型はパーサパッケージが定義する`{ code, severity, start, length, message, data? }`（パーサ詳細設計9.1節）をそのまま共有する（semanticsがparserからimportする。逆依存なし）。LSP層が両層の診断を一括でLSP形式へ変換できるようにする。
- **層の役割分担**: 字句・構文レベル（Unterminated、missing token、ヘッダ欠落等）はパーサ層、参照・構造・値レベル（下記）は意味解析層。同じ事象を二重に報告しない。
- v1診断コード: `xref-offset-mismatch` / `xref-entry-orphan` / `xref-free-object-defined` / `duplicate-object` / `object-header-invalid` / `dangling-reference` / `generation-mismatch` / `generation-out-of-range` / `prev-chain-broken` / `startxref-mismatch` / `page-tree-cycle` / `page-tree-type-missing` / `root-missing` / `length-mismatch` / `length-unresolvable` / `name-invalid-hex-escape` / `string-invalid-hex` / `number-precision-loss`（一覧の正は詳細設計10章）

---

## 5. 公開API（LSP層向け）

詳細は実装時に確定。

- `analyze(tree: SyntaxTree): SemanticModel` — 新規解析
- `update(model: SemanticModel, newTree: SyntaxTree): SemanticModel` — 再解析。v1は内部的に`analyze`相当でよいが、契約として「常に正しいモデルを返す」ことを保証（parserの`reparse`と同じ思想。差分化は内部最適化）
- `model.objectIndex` — `get(num, gen)` / `entries()` / `conflicts()`（重複・食い違い一覧）
- `model.resolve(refNode)` — 参照解決
- `model.revisions` / `model.visibleObjectsAt(revision)`
- `model.documentGraph` — catalog / `pages()` / `pageAt(i)`（各ノードは対応するCSTノードへの参照を持つ）
- `decodeName(token)` / `decodeLiteralString(token, encrypted)` / `decodeHexString(token, encrypted)` / `decodeInteger(token)` / `decodeReal(token)`（シグネチャの正は詳細設計8.1節）
- `model.diagnostics()` — 意味診断の列挙（パーサ診断とマージするのはLSP層の責務）

詳細設計（`pdf-semantics-detailed-design.md`）での追補: **型付きビュー層**（`DictView`/`ArrayView`/`PdfValue`。デコード済みNameでdictを引けるアクセサ）と**逆参照インデックス**（`referencesTo`。LSP層から移管）をv1公開APIに追加した。

---

## 6. 性能目標（暫定値。実測で調整）

- eager部分（論理インデックス＋リビジョン骨格）の構築: 典型的な1MBファイルで**2ms以内**。編集のたびに実行されることを前提とする。コストはオブジェクト数に線形であるため、**何オブジェクトで予算を超過するかをベンチマークの明示的な計測点とし**、超過ラインが実用域（数万オブジェクト級のファイル）に入る場合は差分更新（8章）の前倒しを判断する。
- lazy部分（文書構造グラフ）の初回構築: 典型ファイルで10ms以内。2回目以降はメモ化。
- メモリ: eager部分はオブジェクト数に線形。CSTのバイト範囲を参照するのみで、バイト列のコピーはデコード結果のキャッシュ以外に持たない。
- パーサ仕様書2.3.1節と同じ方式でベンチマークをCIに組み込む。

---

## 7. テスト戦略

- **semantic dumpのスナップショットテスト**: オブジェクト表・リビジョン構造・ページツリー・診断一覧をテキストダンプし、パーサのCSTダンプと同様にスナップショット比較する。
- **破損コーパスの共有**: パーサ仕様書9章の実PDF破損コーパスをそのまま入力し、「診断は出るが例外・クラッシュは発生しない」ことをファジングで検証する。
- **値デコードのプロパティテスト**: エンコード→デコードの往復性（utestと自作の生成器。統括ドキュメント3章の標準ツールチェーンに従う）。
- **リビジョン意味論のfixture**: 多段incremental update・`/Prev`破損・重複定義の後勝ち解決を明示的なテストケースにする。
- **`/Length`不一致診断**: パーサ仕様書9章の3パターン（一致・不一致・間接参照）に対応する診断側のテストを持ち、特に`endstream`早期一致ケースで必ず発火することを検証する。

---

## 8. 未決定事項・今後の検討事項

- 辞書スキーマ検証（v2）の導入時期とスキーマデータの表現形式。LSP層の補完用静的キー辞書（`pdf-lsp-editor-design.md`参照）とデータソースを共用できるかを含めて検討
- `update`の差分化（Greenノード同一性を利用した論理インデックスの差分更新）の要否 — v1実測後に判断
- 過去リビジョンビュー（`visibleObjectsAt`）のAPI詳細と構築コスト
- object stream対応（パーサv2）時の論理インデックスへの統合方法
- ~~暗号化PDF（trailerに`/Encrypt`が存在する場合）で文字列のテキスト解釈を抑制するか~~ → **抑制する**と決定（bytesのみ返し`encoding: 'suppressed'`。表示制御はLSP層。詳細設計8.1節）
