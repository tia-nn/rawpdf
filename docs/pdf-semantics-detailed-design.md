# PDF意味解析 詳細設計ドキュメント

最終更新: 2026-11-11（レビュー指摘を反映: Greenキーのキャッシュに Redノードを入れない規則（8.1・8.2節）。`DictView`の内部Mapを子インデックス方式に変更）
上位ドキュメント: `pdf-semantics-design.md`（基本設計。スコープ・責務分担はそちらが正）
用途: 実装直前の詳細設計。モジュール構成・TS型定義・関数シグネチャ・アルゴリズムの段階記述までを定める（パーサ詳細設計と同じ粒度）。

**前提決定**: クラスベースAPI・vitest + tsc + ESM only（統括ドキュメント3章、パーサ詳細設計と共通）。本詳細設計での新規決定: 型付きビュー層（`DictView`等）をv1公開APIに含める／逆参照インデックスをLSP層から本パッケージへ移管／`/Encrypt`検出時は文字列のテキスト解釈を抑制する。

---

## 1. 基本設計からの追補

- **型付きビュー層（8章）を新設**: `DictView.get("Type")`のようにデコード済みNameでdictエントリを引ける薄いラッパを提供する。rust-analyzerのAST層に相当し、LSP層が生CSTを直接歩く必要をなくす。
- **逆参照インデックス（5.2節）をLSP層から移管**: 参照解決と同じ「全`Reference`走査」を共有できるため。`pdf-lsp-editor-design.md`の該当記述は修正済み。
- **暗号化PDFのテキスト解釈抑制（基本設計8章の未決定事項を解消）**: 最新リビジョンのtrailerに`/Encrypt`キーが存在する場合、文字列デコードは`bytes`のみを返し`text`を返さない（`encoding: 'suppressed'`）。表示制御はLSP層の責務。

---

## 2. パッケージ構成

```
packages/pdf-semantics/
├── src/
│   ├── model.ts           … SemanticModel・analyze/update
│   ├── object-index.ts    … 論理インデックス・xref突き合わせ
│   ├── resolve.ts         … 参照解決・逆参照インデックス
│   ├── revisions.ts       … リビジョンモデル・/Prevチェーン検証
│   ├── graph.ts           … 文書構造グラフ（catalog/page tree）
│   ├── decode/
│   │   ├── name.ts        … Name #xxデコード
│   │   ├── string.ts      … literal/hex stringデコード・テキスト解釈
│   │   └── number.ts      … Integer/Real → number
│   ├── typed/
│   │   ├── value.ts       … PdfValue union・valueOf()
│   │   └── views.ts       … DictView / ArrayView
│   ├── length-check.ts    … /Length不一致検証
│   ├── diagnostics.ts     … 意味診断コード定義（Diagnostic型はparserを再利用）
│   └── index.ts
├── tests/
└── package.json           … 依存: pdf-cst-parser のみ
```

---

## 3. 主要型とSemanticModel（`model.ts`）

```ts
export function analyze(tree: SyntaxTree): SemanticModel;
/** v1は内部的にanalyze委譲。契約は「常に正しいモデル」（基本設計5章） */
export function update(model: SemanticModel, newTree: SyntaxTree): SemanticModel;

export class SemanticModel {
  readonly tree: SyntaxTree;
  readonly objectIndex: ObjectIndex;        // eager（4章）
  readonly revisions: readonly Revision[];  // eager・骨格のみ（6章）
  get isEncrypted(): boolean;               // eager（最新trailerの/Encrypt有無）

  // 以下すべてlazy＋メモ化
  get documentGraph(): DocumentGraph;                       // 7章
  resolve(refNode: SyntaxNode): ResolveResult;              // 5章
  referencesTo(num: number, gen: number): readonly SyntaxNode[]; // 5.2節
  visibleObjectsAt(revisionIndex: number): ReadonlyMap<ObjectId, ObjectDef>;
  diagnostics(): readonly Diagnostic[];                     // 10章
  dictView(dictNode: SyntaxNode): DictView;                 // 8章
  valueOf(valueNode: SyntaxNode | SyntaxToken): PdfValue;   // 8章（name/string/number/bool/nullは裸のトークンのためSyntaxTokenも受ける）
}
```

**ObjectId**: `(num, gen)`を単一numberにパックする（`num * 65536 + gen`。genは仕様上最大65535。超過値はパース可能だが65535にクランプし診断`generation-out-of-range`を付与）。

```ts
export type ObjectId = number; // packed
export const objectId = (num: number, gen: number): ObjectId => num * 65536 + gen;
```

---

## 4. 論理インデックス（`object-index.ts`）

```ts
export interface ObjectDef {
  readonly id: ObjectId;
  readonly num: number;  readonly gen: number;
  readonly node: SyntaxNode;        // IndirectObject
  readonly segmentIndex: number;
  readonly declaredOffset?: number; // xrefが宣言していたoffset（照合済み）
}

export interface ObjectConflict {
  readonly id: ObjectId;
  readonly defs: readonly ObjectDef[]; // 物理順。最後が有効
  readonly sameSegment: boolean;       // 同一Segment内重複（診断対象）
}

export class ObjectIndex {
  get(num: number, gen: number): ObjectDef | undefined; // 有効定義（後勝ち）
  getAll(num: number, gen: number): readonly ObjectDef[];
  entries(): IterableIterator<ObjectDef>;
  conflicts(): readonly ObjectConflict[];
  readonly objectCount: number;
}
```

構築アルゴリズム（eager・CSTトップレベル1走査）:

1. `Document`直下の`Segment`を順に走査。各`Segment`直下の`IndirectObject`について、先頭2つの`Integer`トークンを`decodeInteger`し`(num, gen)`を得る（ヘッダが壊れていて数値が取れないものはインデックス対象外とし`object-header-invalid`診断）。
2. `Map<ObjectId, ObjectDef[]>`に物理順で蓄積。有効定義は配列末尾（＝最新Segment）。同一Segment内重複は`duplicate-object`診断。
3. **xref突き合わせ（リビジョン単位）**: セグメントiの`XrefSection`について`XrefSubsection`（開始番号＋件数）と`XrefEntry`（offset・gen・n/f）をデコードし、`n`エントリの宣言offsetを**そのリビジョン時点の後勝ち定義**（Segment 0..iにおける同numの最後の`ObjectDef`。6章`visibleObjectsAt`の「可視」と異なりfエントリ削除は反映しない: ここはbody実測との突き合わせが目的のため）の`node.start`と比較する。旧リビジョンのxrefが旧Segmentの定義を指すのは正常であるため、最新定義とだけ比較してはならない（誤ると更新されたオブジェクト全件で`xref-offset-mismatch`が誤検知する）。不一致は`xref-offset-mismatch`診断。宣言offsetは比較先の`ObjectDef.declaredOffset`に記録する（複数リビジョンが同一defを指す場合は最後の宣言を記録。インデックス自体はCST実測を正とする。基本設計3.1節）。可視な定義が無い`n`エントリは`xref-entry-orphan`診断。`f`エントリは原則診断対象外とし（オブジェクト0のfreeエントリ等、正常なPDFにも必ず存在するため）、**同一Segmentのbody**に同numのオブジェクトが実在する場合のみ「free宣言と実在の矛盾」として`xref-free-object-defined`診断（warning）を付与する。照合はnumのみで行う（ISO 32000-1 §7.5.4より`f`エントリの第2フィールドは「再利用時の次世代番号」であり、解放対象オブジェクトのgenとは一致しないため）。なお旧Segmentに同numの定義が実在すること自体はincremental updateによる正常な削除であり、診断しない（削除の可視性反映は6章`visibleObjectsAt`）。

性能: ステップ1〜2はオブジェクト数に線形・デコードはヘッダ整数のみ。予算2ms（基本設計6章）の主対象。

---

## 5. 参照解決・逆参照（`resolve.ts`）

### 5.1 resolve

```ts
export type ResolveResult =
  | { readonly kind: 'resolved'; readonly def: ObjectDef; readonly exactGen: boolean }
  | { readonly kind: 'dangling'; readonly num: number; readonly gen: number };

// SemanticModel.resolve(refNode) の実装
function resolve(index: ObjectIndex, refNode: SyntaxNode): ResolveResult;
```

1. `Reference`ノードの`Integer` 2つをデコード（失敗 → `dangling`）。
2. `index.get(num, gen)` → あれば`exactGen: true`。
3. なければ同`num`の定義のうち**物理的に最後のもの**（最新Segment、同一Segment内では後の定義。重複解決の後勝ち規則と同一）を採用し`exactGen: false`（世代フォールバック。基本設計3.2節）。それもなければ`dangling`。

### 5.2 逆参照インデックス（lazy）

初回の`referencesTo`呼び出しで、CST全体を1回走査して構築・メモ化する。

```ts
// 内部構造: Map<ObjectId(宣言キー), SyntaxNode[](Referenceノード、物理順)>
function buildReferenceIndex(tree: SyntaxTree): Map<ObjectId, SyntaxNode[]>;
```

- グルーピングは**宣言された`(num, gen)`キー**で行う（解決先ではなく）。`referencesTo(num, gen)`は完全一致のみを返し、世代フォールバック込みの逆参照が必要な場合はLSP層が`getAll`と組み合わせる。
- この走査は`dangling-reference`・`generation-mismatch`診断の収集を兼ねる（10章。同じ走査を診断のためだけに繰り返さない）。

---

## 6. リビジョンモデル（`revisions.ts`）

```ts
export interface Revision {
  readonly index: number;              // 0 = 最古
  readonly segment: SyntaxNode;
  readonly trailerDict?: DictView;
  readonly xrefStart?: number;         // XrefSectionのstart（/Prev照合用）
  readonly startxrefValue?: number;    // StartxrefClauseの整数値
  readonly prevValue?: number;         // trailer /Prev の値（直接値のみ）
}
```

eager構築（骨格のみ）: 各Segmentからtrailer・xref・startxrefの有無と数値を取り出す。`/Prev`チェーン検証はlazy（`diagnostics()`時）:

- `revisions[i].prevValue`は`revisions[i-1].xrefStart`と一致するはず。不一致・欠落・自己参照は`prev-chain-broken`診断（i=0の`/Prev`存在も同診断）。
- 各リビジョンの`startxrefValue`は**同リビジョン自身の`xrefStart`**と一致するはず（incremental updateでは各セグメントのstartxrefが自セグメントのxrefを指す）。不一致はリビジョンごとに`startxref-mismatch`診断。

`visibleObjectsAt(i)`: Segment 0..iを物理順に畳み込んだMapをリビジョンごとにlazy構築・メモ化する。畳み込みは`ObjectDef`の後勝ちに加え、**各セグメントのxrefの`f`エントリを「同numの可視定義の削除」として反映する**（incremental updateにおける削除の意味論。fエントリを無視すると削除済みオブジェクトが可視のまま残る。以降のセグメントで再定義されれば再び可視になる）。

**linearized PDFの扱い**: linearized PDFは物理先頭のtrailerが後方のmain xrefを`/Prev`で指すため、「物理順＝古→新」「i=0に`/Prev`なし」の前提が正常なファイルでも成り立たない。先頭`IndirectObject`の辞書に`/Linearized`キーを検出した場合は`prev-chain-broken`診断を抑制する（v1は抑制のみ。linearized構造の完全な意味づけはv2）。

---

## 7. 文書構造グラフ（`graph.ts`）

```ts
export interface DocumentGraph {
  readonly catalog?: { readonly def: ObjectDef; readonly dict: DictView };
  readonly pageTreeRoot?: PageTreeNode;
  pages(): readonly PageInfo[];   // ツリーの葉（Page）を文書順に列挙。lazy
  pageAt(i: number): PageInfo | undefined; // pages()のインデックスアクセス（基本設計5章）
}

export type PageTreeNode = {
  readonly kind: 'pages' | 'page' | 'invalid';
  readonly def?: ObjectDef;
  readonly dict?: DictView;
  readonly kids?: readonly PageTreeNode[];  // kind === 'pages' のみ
};

export interface PageInfo { readonly pageIndex: number; readonly node: PageTreeNode; }
```

構築（lazy）: 最新リビジョンの`trailerDict.get("Root")` → resolve → catalog。`catalog.dict.get("Pages")`から再帰下降:

- **visited setは`GreenNode`の===同一性**で管理し、再訪問は`page-tree-cycle`診断＋`invalid`ノード化（再帰しない）。
- 型判定は`/Type`の値（`Pages`/`Page`）と`/Kids`の有無のみ。`/Type`欠落は`/Kids`があれば`pages`とみなし`page-tree-type-missing`診断（warning）。
- `Root`欠落・dangling → `root-missing`診断＋`catalog: undefined`（部分グラフ。基本設計3.4節）。

---

## 8. 値デコード・型付きビュー（`decode/`, `typed/`）

### 8.1 デコード関数

すべてWeakMap（キー: `GreenToken`）でメモ化。Greenの構造共有により、reparse後も変更のないトークンのキャッシュが自然に生き残る。

**Greenキーのキャッシュの規則（本章・7章を含むパッケージ全体）**: Greenノード／トークンをキーとするキャッシュ（世代をまたいで生き残るもの）の値には、**位置に依存しない情報だけ**を入れる。具体的には、デコード済みのバイト列・文字列・数値、および子要素のインデックス（Green上の位置）は可。**Redノード（`SyntaxNode`/`SyntaxToken`）・絶対オフセット・`SyntaxTree`への参照は不可**。reparse後に再利用されたGreenノードは、絶対位置（編集箇所より後ろならシフトしている）とRed側の親チェーン（新しい木）が旧世代と異なる。Redノードをキャッシュすると、旧世代の位置・旧世代の木を指したまま返すことになる。Redノードが必要なAPIは、キャッシュしたインデックスから、呼び出し時点のRedノードを起点に毎回生成する（Redは軽量。パーサ詳細設計5章）。モデル（`SemanticModel`）が自分の木だけを対象に持つキャッシュ（`ObjectIndex`・逆参照インデックス等）はこの規則の対象外（モデルと同じ世代で破棄されるため）。

```ts
// decode/name.ts
export interface DecodedName {
  readonly key: string;        // #xx解決後バイト列のlatin1正規形（Dict引き・比較用のキー）
  readonly bytes: Uint8Array;  // #xx解決後の生バイト
  readonly invalidEscape: boolean; // 不正な#列があった（生バイトのまま残した）
}
export function decodeName(token: SyntaxToken): DecodedName;

// decode/string.ts
export type StringEncoding = 'utf16be' | 'utf8' | 'pdfdoc' | 'suppressed';
export interface DecodedString {
  readonly bytes: Uint8Array;  // エスケープ/hex解決後
  readonly text?: string;      // 解釈できた場合のみ。suppressed時はundefined
  readonly encoding: StringEncoding;
  readonly unterminated: boolean;
}
export function decodeLiteralString(token: SyntaxToken, encrypted: boolean): DecodedString;
export function decodeHexString(token: SyntaxToken, encrypted: boolean): DecodedString;

// decode/number.ts
export interface DecodedNumber { readonly value: number; readonly precisionLoss: boolean; }
export function decodeInteger(token: SyntaxToken): DecodedNumber;
export function decodeReal(token: SyntaxToken): DecodedNumber;
```

デコード規則の詳細:

- **Name**: `#`+16進2桁を1バイトに解決。16進として不正な`#`列はそのまま残し`invalidEscape: true`（`name-invalid-hex-escape`診断は10章の走査で付与）。
- **LiteralString**: `\n \r \t \b \f \( \) \\`、8進`\ddd`（1〜3桁）、`\`+実EOL（行継続、消える）、未定義エスケープは`\`を落とし後続バイトをそのまま。ネスト括弧はバイトとして保持。
- **HexString**: whitespace除去→16進ペア化。奇数桁は末尾`0`補い。非16進バイトは読み飛ばして`string-invalid-hex`診断対象としてマーク。
- **テキスト解釈**: `encrypted`なら常に`suppressed`。それ以外はUTF-16BE BOM（FE FF）→ UTF-8 BOM（EF BB BF）→ PDFDocEncoding（変換テーブルを`string.ts`に内蔵）の順。
- **キャッシュ**: bytesレベルのデコード結果をWeakMapに載せる。`text`は文字列長が小さいため都度計算（`encrypted`フラグでキャッシュを分けない）。

### 8.2 PdfValueと型付きビュー

```ts
// typed/value.ts
export type PdfValue =
  | { readonly type: 'dict';   readonly view: DictView }
  | { readonly type: 'array';  readonly view: ArrayView }
  | { readonly type: 'name';   readonly name: DecodedName;  readonly token: SyntaxToken }
  | { readonly type: 'string'; readonly value: DecodedString; readonly token: SyntaxToken }
  | { readonly type: 'number'; readonly value: DecodedNumber; readonly token: SyntaxToken }
  | { readonly type: 'bool';   readonly value: boolean; readonly token: SyntaxToken }
  | { readonly type: 'null';   readonly token: SyntaxToken }
  | { readonly type: 'ref';    readonly node: SyntaxNode; readonly resolve: () => ResolveResult }
  | { readonly type: 'error';  readonly node: SyntaxNode | SyntaxToken }; // ErrorNode等

export function valueOf(node: SyntaxNode | SyntaxToken, model: SemanticModel): PdfValue;

// typed/views.ts
export class DictView {
  readonly node: SyntaxNode; // Dictionary
  get(key: string): PdfValue | undefined;  // keyはDecodedName.key形式。重複キーは後勝ち
  has(key: string): boolean;
  entries(): IterableIterator<readonly [DecodedName, PdfValue]>;
  readonly size: number;
}
export class ArrayView {
  readonly node: SyntaxNode; // Array
  at(i: number): PdfValue | undefined;
  readonly length: number;
  [Symbol.iterator](): Iterator<PdfValue>;
}
```

- `DictView.get`は内部で`Map<string, number>`（キー: `DecodedName.key`、値: dictの`GreenNode.children`における`DictEntry`の子インデックス）をlazy構築しWeakMap（キー: dictの`GreenNode`）にメモ化する。`get`の呼び出し時に、`DictView.node`（現在の世代のRedノード）からそのインデックスの子`DictEntry`を生成して値を取り出す。旧版の`Map<string, DictEntryノード>`は、Redノードをキャッシュに入れるため不可（8.1節の規則。reparse後にGreenが再利用されると、編集箇所より後ろのdictで旧世代の位置・旧世代の木を返す）。ErrorNodeを含むdictでも読めるエントリだけでMapを作る。
- `PdfValue`（`token`・`node`にRedを持つ）はキャッシュせず、`valueOf`・`DictView.get`・`ArrayView.at`の呼び出しごとに生成する（デコード結果自体は8.1節のGreenキーのキャッシュに載るため、再生成のコストはRedの生成程度）。
- `ref`の`resolve`はサンクとし、循環参照でもビュー構築自体は停止しない（多段解決を自動では行わない。基本設計3.2節）。

---

## 9. /Length検証（`length-check.ts`）

```ts
function checkStreamLengths(model: SemanticModel): Diagnostic[];
```

`objectIndex.entries()`のうち`StreamClause`を持つ定義について:

1. dictの`Length`を`DictView.get`で取得。`number`なら直接値、`ref`なら1段resolveして参照先の値（それも`number`でなければ解決不能）。
2. 解決不能（dangling・非数値・キー欠落）→ `length-unresolvable`（warning）。
3. 解決値 ≠ `StreamBody`トークンの`textLength` → `length-mismatch`（warning。実測値と宣言値をdataに含める）。
4. パーサが`unterminated-stream`を出している場合は1〜3をスキップ（二重報告回避）。

なお実測長`textLength`は、パーサのbodyEnd規則（パーサ基本設計4.3節: `endstream`直前のEOL 1つ分を本体に含めない）により仕様準拠ファイルでは`/Length`とそのまま一致する。本検証側でEOL分の許容誤差は設けない。

`diagnostics()`のlazyパス内で実行（v1必須機能。基本設計3.6節）。

---

## 10. 診断の集約（`diagnostics.ts`）

```ts
export type SemanticDiagnosticCode =
  | 'xref-offset-mismatch' | 'xref-entry-orphan' | 'xref-free-object-defined'
  | 'duplicate-object' | 'object-header-invalid'
  | 'dangling-reference' | 'generation-mismatch' | 'generation-out-of-range'
  | 'prev-chain-broken' | 'startxref-mismatch'
  | 'page-tree-cycle' | 'page-tree-type-missing' | 'root-missing'
  | 'length-mismatch' | 'length-unresolvable'
  | 'name-invalid-hex-escape' | 'string-invalid-hex' | 'number-precision-loss';
```

`Diagnostic`型・severity型はパーサパッケージから再利用する（codeは各層のunionで拡張。基本設計4章）。

`diagnostics()`の構成: **eager蓄積分**（インデックス構築時のduplicate/xref系）＋**lazyパス**（①逆参照走査のdangling/gen系、②/Prevチェーン、③documentGraph構築時のgraph系、④length検証、⑤名前・文字列の不正エスケープおよび数値精度損失（`number-precision-loss`）の走査）。初回呼び出しで①〜⑤を強制評価し、結果全体をメモ化する。パーサ診断は含まない（マージはLSP層）。

---

## 11. semantic dump・テスト構成

```ts
export function dumpSemantics(model: SemanticModel): string;
```

スナップショットの正となるテキスト形式。セクション構成: `=== objects ===`（num gen → CST範囲・stream有無・conflictマーク）、`=== revisions ===`（trailer/xref/startxref/prev整合）、`=== pages ===`（ツリーのインデント表示）、`=== diagnostics ===`。

```
tests/
├── object-index.test.ts   … unit（重複・後勝ち・xref突き合わせ）
├── resolve.test.ts        … unit（genフォールバック・dangling）
├── decode.test.ts         … unit + fast-checkプロパティ（往復性）
├── snapshot/              … corpus/ → dumpSemantics スナップショット
├── update.test.ts         … 「update結果 === 新規analyze結果」等価性（ランダム編集）
└── bench/                 … eager部分の構築時間 vs オブジェクト数（超過ライン計測。基本設計6章）
```

パーサと同じく「破損コーパスで例外ゼロ」をファジング目標とする（Jazzer.jsはパーサ経由で本パッケージまで貫通させる）。

**実装マイルストーン**: S1 ObjectIndex＋Revision骨格＋dump → S2 decode一式＋typed views → S3 resolve＋逆参照＋documentGraph → S4 length検証＋診断集約 → S5 プロパティテスト・ベンチ・ファジング統合。

---

## 12. 実装時判断に委ねる事項

- `DecodedName.key`のlatin1正規形で実用上問題ないか（UTF-8名の表示はLSP層で`bytes`から別途解釈）
- `DictView`の内部Map構築をsizeいくつから行うか（小さいdictは線形探索の方が速い可能性）
- `visibleObjectsAt`のメモ化を全リビジョン分持つか、直近アクセスのみか
- `update`の差分化（基本設計8章）着手時の、逆参照インデックス・graphの部分無効化の設計
- `startxref-mismatch`・`xref-entry-orphan`・`xref-free-object-defined`のseverity（暫定warning）
