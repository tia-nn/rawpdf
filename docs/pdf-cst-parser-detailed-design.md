# PDF CSTパーサ 詳細設計ドキュメント

最終更新: 2026-11-12（実装言語をHaxeに変更: 0章（新設）・2章・3章・10章・11章）。2026-11-11（レビュー指摘を反映: stream本体をレキサー主導で読む方式（6.2・6.4・7.1節）、`findEndstream`の探索終端（6.4節）、強制不安定化条件の一般化と境界キャッシュの再利用条件（8章））
上位ドキュメント: `pdf-cst-parser-design.md`（基本設計。要件・文法・戦略はそちらが正）
用途: 実装直前の詳細設計。モジュール構成・型定義・関数シグネチャ・アルゴリズムの段階記述までを定める（実装コードそのものは書かない）。型定義とシグネチャはTS風の擬似表記で書く（0章）。

**前提決定**: Green木はobject-per-node表現（メモリ10倍目標超過が実測されたらSoAへ内部差し替え）／RedビューはクラスベースAPI／実装言語はターゲット非依存の純Haxe、テストはutest（統括ドキュメント3章・3.1節）。

---

## 0. 型表記の読み替え（Haxe）

本ドキュメントと意味解析詳細設計の型定義・シグネチャは、TS時代に書いたものを**言語中立の擬似表記**として残している（統括3.1節）。Haxeで実装するときは次の規則で読み替える。読み替えで設計の意図が変わる箇所（下表の「注意」）は、実装時に該当節を見直す。

| 擬似表記（TS風） | Haxe | 注意 |
|---|---|---|
| 数値constオブジェクト＋union（`SyntaxKind`） | `enum abstract SyntaxKind(Int)` | 実行時は`Int`のまま。分類ヘルパ（`isTrivia`等）は`enum abstract`のメソッドにできる |
| 文字列リテラルのunion（診断コード、`'page' \| 'pages'`等） | `enum abstract X(String)` | |
| 判別共用体（`{ type: 'ref', ... } \| ...`。`PdfValue`等） | `enum`（代数的データ型）＋`switch`のパターンマッチ | 網羅性をコンパイラが検査する |
| `interface`（データの形） | `typedef`の構造型、または`@:structInit class` | 生成数が多い型（トークン等）は`class`の方が速い（JSで形が固定されるため） |
| `class` | `class` | |
| `readonly`フィールド | `final` | |
| `readonly T[]` | `haxe.ds.ReadOnlyArray<T>` | |
| `T \| null`、`x?: T` | `Null<T>`、`?x:T` | |
| `Uint8Array` | `haxe.io.Bytes` | 部分範囲は`(bytes, start, length)`の組で渡し、コピー（`sub`）を避ける |
| `number`（オフセット・長さ・個数・インデックス） | `Int` | **`Int`は32ビット**。ファイルサイズ2GiB未満を前提とする（10章に記録） |
| `number`（PDFのInteger/Realの値） | `Float` | PDFのIntegerは10桁（xrefのオフセット等）があり得るため`Int`に入れない。意味解析詳細設計8.1節 |
| `IterableIterator<T>` | `Iterator<T>` | |
| `Map<K, V>` | `Map<K, V>` | キーがオブジェクトなら`haxe.ds.ObjectMap`になる |
| `WeakMap<K, V>` | **対応なし** | `haxe.ds.WeakMap`はJSターゲットで使えない。意味解析詳細設計8.2節の代替を参照 |
| `===`（参照の同一性） | `==`（クラスのインスタンスは参照比較） | `GreenNode`の「変更なし」判定（4章）はこれで行う |
| `export function f()` | モジュールレベル関数（Haxe 4.2以降）または`static`関数 | |
| `() => T` | `() -> T` | |
| ファイル`kind.ts` | モジュール`SyntaxKind.hx`等 | 2章の対応表 |

---

## 1. 基本設計からの追補（トークン種別）

詳細化の過程で、基本設計4.5節のリーフトークン一覧に以下を追加する。

- **`HeaderMarker`**: `%PDF-`で始まるコメントは、Commentトリビアではなく**非トリビアの実トークン**としてレキシングする。理由: 基本設計5.2節の`Header`はノードであり、ノードは実トークンを子に持つ必要がある（トリビアのままでは`Header`ノードが幅を持てず、4.4節の幅不変条件と両立しない）。副次効果として、ファイル中間に現れる2つ目以降の`%PDF-`（PDF連結などの実在ケース）も実トークンとなり、Document/Segmentレベルのエラー回復・診断の対象にできる。
- **`StreamBody`**: stream本体の不透明バイト列を表す1トークン（基本設計5.1節の記述の明文化）。
- **`LeftBrace` `{` / `RightBrace` `}`**: 基本設計4.2節で「単純な1バイトトークン」とされていたものの種別名。ファイル構造文法には登場しないため、パーサは常にエラー回復の対象として扱う。

---

## 2. パッケージ構成

```
packages/pdf-cst-parser/
├── src/rawpdf/cst/                  … Haxeのパッケージ rawpdf.cst（ターゲット非依存の純Haxe）
│   ├── syntax/
│   │   ├── SyntaxKind.hx  … SyntaxKind定義・分類ヘルパ          （旧 kind.ts）
│   │   ├── Green.hx       … Green木（不変・相対長）              （旧 green.ts）
│   │   ├── Red.hx         … Redビュー（SyntaxTree/Node/Token）    （旧 red.ts）
│   │   └── GreenBuilder.hx … GreenBuilder（イベント型構築）      （旧 builder.ts）
│   ├── lex/
│   │   ├── ByteClass.hx   … バイト分類テーブル                   （旧 byte-class.ts）
│   │   ├── Lexer.hx       … トークナイザ本体                     （旧 lexer.ts）
│   │   ├── StreamBoundary.hx … endstream探索                    （旧 stream-boundary.ts）
│   │   └── TokenSource.hx … トリビア吸着・先読みバッファ         （旧 token-source.ts）
│   ├── parse/
│   │   ├── Parser.hx      … 再帰下降本体                         （旧 parser.ts）
│   │   ├── Recovery.hx    … 同期スタック・エラー回復             （旧 recovery.ts）
│   │   └── Reparse.hx     … インクリメンタル再パース             （旧 reparse.ts）
│   ├── Diagnostics.hx     … Diagnostic型・コード定義             （旧 diagnostics.ts）
│   ├── Dump.hx            … CSTテキストダンプ                    （旧 dump.ts）
│   └── Cst.hx             … 公開APIの入口                        （旧 index.ts）
├── cli/                   … dump CLI（Node向け。ファイル読み込みのため`js.*`/hxnodejsを使ってよい層。旧 cli.ts）
├── tests/                 … utest（unit / snapshot / property）
├── haxelib.json           … ライブラリ定義（classPath: src。依存なし）
├── build.hxml             … 型検査用（全モジュールをコンパイル）
├── test.hxml              … テスト（Nodeターゲット。evalでも回せるようにする）
└── cli.hxml               … CLI（JSに出力。bin: pdf-cst-dump）
```

本文中で`syntax/kind.ts`のようにTS時代のファイル名で書いている箇所は、この表の対応するHaxeモジュールを指す。

依存: ランタイム依存ゼロ（`src/`はHaxe標準ライブラリのみ）。開発時の依存はutestと、CLIのためのhxnodejs（lixで固定。統括3章）。

---

## 3. SyntaxKind定義（`syntax/kind.ts`）

Haxeでは`enum abstract SyntaxKind(Int)`として定義する（0章）。以下はTS時代の擬似表記で、値の割り当てと分類ヘルパの仕様はそのまま有効である。

```ts
export const SyntaxKind = {
  // trivia
  Whitespace: 0, Comment: 1,
  // tokens
  Integer: 10, Real: 11, Name: 12, LiteralString: 13, HexString: 14,
  LeftBracket: 15, RightBracket: 16, LeftDoubleAngle: 17, RightDoubleAngle: 18,
  LeftBrace: 19, RightBrace: 20,
  KwTrue: 30, KwFalse: 31, KwNull: 32, KwR: 33, KwObj: 34, KwEndobj: 35,
  KwStream: 36, KwEndstream: 37, KwXref: 38, KwTrailer: 39, KwStartxref: 40,
  KwN: 41, KwF: 42,
  HeaderMarker: 50, StreamBody: 51,
  Unknown: 60, EndOfFile: 61,
  // nodes
  Document: 100, Header: 101, Segment: 102, IndirectObject: 103,
  StreamClause: 104, Array: 105, Dictionary: 106, DictEntry: 107,
  Reference: 108, XrefSection: 109, XrefSubsection: 110, XrefEntry: 111,
  TrailerClause: 112, StartxrefClause: 113, ErrorNode: 114,
} as const;
export type SyntaxKind = (typeof SyntaxKind)[keyof typeof SyntaxKind];

export function isTrivia(k: SyntaxKind): boolean;
export function isToken(k: SyntaxKind): boolean;
export function isNode(k: SyntaxKind): boolean;
export function isKeyword(k: SyntaxKind): boolean;
```

基本設計4.5節の`Error`トークンは`Unknown`に一本化する（区別する用途がないため。ノード側の`ErrorNode`は維持）。

---

## 4. Green層（`syntax/green.ts`）

```ts
// const enumは使わない方針（3章と同じ理由）に合わせ、constオブジェクトで定義するビットフラグ
export const TokenFlags = {
  None: 0,
  Unterminated: 1 << 0, // EOF/範囲末尾で打ち切られた（string/stream等）
  Missing: 1 << 1,      // 幅ゼロの合成トークン
} as const;
export type TokenFlags = number; // ビットORの合成値を取るためnumber

export interface GreenTrivia {
  readonly kind: SyntaxKind;   // Whitespace | Comment
  readonly length: number;
}

export interface GreenToken {
  readonly kind: SyntaxKind;
  readonly flags: TokenFlags;
  readonly leadingTrivia: readonly GreenTrivia[];
  readonly textLength: number;   // トリビアを除くトークン本体の長さ
  readonly fullLength: number;   // leadingTrivia合計 + textLength
}

export interface GreenNode {
  readonly kind: SyntaxKind;
  readonly children: readonly (GreenNode | GreenToken)[];
  readonly fullLength: number;   // 子のfullLength合計（構築時に計算・凍結）
}
```

- **絶対オフセットは持たない**（基本設計5.1節）。`fullLength`の総和＝ファイルサイズが不変条件。
- トリビアは次トークンの`leadingTrivia`（基本設計4.4節）。`EndOfFile`トークン（textLength=0）が末尾トリビアを受ける。
- ノードの共有: reparse時に変更されなかったGreenNodeは参照ごと再利用される（===比較が「変更なし」の判定に使える）。v1ではinterning（同形ノードの重複排除）は行わない。

`GreenBuilder`（`syntax/builder.ts`）はrowan流のイベント型:

```ts
export class GreenBuilder {
  startNode(kind: SyntaxKind): void;
  finishNode(): void;
  token(kind: SyntaxKind, flags: TokenFlags, trivia: GreenTrivia[], textLength: number): void;
  missingToken(kind: SyntaxKind): void;  // 幅ゼロ + Missingフラグ
  finish(): GreenNode;                   // root（Document）を返す
}
```

---

## 5. Red層（`syntax/red.ts`）

クラスベース。Redオブジェクトはアクセス時に遅延生成し、キャッシュしない（毎回生成しても軽量。同一性比較は`green`の===で行う）。

```ts
export class SyntaxTree {
  readonly bytes: Uint8Array;
  readonly root: SyntaxNode;                     // kind === Document
  readonly diagnostics: readonly Diagnostic[];
}

export class SyntaxNode {
  readonly kind: SyntaxKind;
  readonly parent: SyntaxNode | null;
  readonly green: GreenNode;
  get fullStart(): number;   // leading trivia込みの開始（親から累積計算）
  get start(): number;       // 最初の実トークンのtext開始
  get end(): number;
  children(): IterableIterator<SyntaxNode | SyntaxToken>;
  childNodes(): IterableIterator<SyntaxNode>;
  firstToken(): SyntaxToken | null;
  lastToken(): SyntaxToken | null;
  /** byteOffsetを包含する最内要素（reparse Step1・LSPの位置引きの基盤） */
  coveringElement(byteOffset: number): SyntaxNode | SyntaxToken;
}

export class SyntaxToken {
  readonly kind: SyntaxKind;
  readonly flags: TokenFlags;
  readonly parent: SyntaxNode;
  readonly green: GreenToken;  // 同一性比較・上位層のWeakMapキャッシュのキーに使う（semantics詳細設計8.1節）
  get fullStart(): number; get start(): number; get end(): number;
  /** 元バッファのsubarrayビュー（ゼロコピー） */
  bytes(): Uint8Array;
  leadingTrivia(): readonly { kind: SyntaxKind; start: number; length: number }[];
}
```

`start`/`fullStart`の区別（TSコンパイラと同じ規約）: 幅不変条件・reparseは`full*`系で扱い、診断・エディタ表示は`start`系を使う。

---

## 6. トークナイザ（`lex/`）

### 6.1 バイト分類（`byte-class.ts`）

```ts
export const BYTE_CLASS: Uint8Array; // 256要素。0=Regular, 1=Whitespace, 2=Delimiter
```

モジュール初期化時に基本設計4.1節の分類で埋める。ホットループはこのテーブル参照のみ。

### 6.2 Lexer（`lexer.ts`）

```ts
export interface RawToken {
  kind: SyntaxKind;      // トリビア種を含む
  flags: TokenFlags;
  start: number;         // バッファ絶対オフセット（レキシング時のみの一時情報）
  end: number;
}

/** reparse時の境界キャッシュ（8章）。キーは新座標のbodyStart */
export interface StreamBodyHint {
  bodyEnd: number;        // 新座標
  endstreamStart: number; // 新座標。採用されていたendstreamの開始位置
}

export interface LexerOptions {
  start?: number;  // 既定 0
  end?: number;    // 既定 bytes.length。部分レキシング（reparse用）の範囲終端
  streamBodyHints?: ReadonlyMap<number, StreamBodyHint>;
}

export class Lexer {
  constructor(bytes: Uint8Array, opts?: LexerOptions);
  next(): RawToken;      // EndOfFile到達後はEndOfFileを返し続ける
  /**
   * 部分レキシングの末尾要素の長さが範囲外（end以降）のバイトに依存し得るか。
   * EndOfFileを返した後に有効。end === bytes.length のときは常にfalse。
   * reparseの不安定判定に使う（8章 Step 4、基本設計5.5.1節）
   */
  get boundaryDependent(): boolean;
}
```

**stream本体モード（基本設計4.2・4.3節）**: stream本体の切り出しはパーサから呼ぶのではなく、**レキサーが`KwStream`を出した直後に自動で行う**（旧版の`scanStreamBody()`は廃止）。理由: `TokenSource`は最大3トークン先まで先読みするため（6.3節）、パーサが`stream`を見て切り替える時点で、本体バイトがすでに構造モードで字句解析済みになっている場合がある（回復処理の`atObjHeader()`等）。レキサー主導にすれば先読みの有無に関係なく同じトークン列になり、字句解析が文脈自由になる。`KwStream`を返した後、`next()`は次の順にトークンを返して構造モードに戻る:

1. 基本設計4.3節 Step 1の規則に一致したEOL（＋非準拠の空白列）を`Whitespace`トリビアとして1つ（一致しなければ返さない）。構造モードの空白スキャンは使わない（本体先頭の空白バイトまで取り込んでしまうため）。
2. `StreamBody`（長さ0もあり得る。パーサ側の構造を一様にするため常に返す）。境界は`streamBodyHints`に`bodyStart`のヒントがあり、`endstreamStart + 9 <= end`かつ`bytes[endstreamStart .. +9]`が`endstream`に一致すればそれを使い、そうでなければ`findEndstream(bytes, bodyStart, end)`（6.4節）。見つからなければ`end`まで＋`Unterminated`。
3. 以降は構造モード。除外されたEOLはWhitespaceトリビアとして、続く`KwEndstream`に付く。

構造モードの分岐は基本設計4.2節の通り。実装注意:

- regular runの分類は「数値判定 → 長さ別キーワード完全一致 → Unknown」の順。キーワード照合は長さでswitchしてからバイト比較（ハッシュ不要）。
- `%`開始のコメントは、直後が`PDF-`なら`HeaderMarker`、それ以外は`Comment`トリビア（1章）。行末（CR/LF）は含まない。
- サブスキャン（literal string / hex string / stream本体）が`end`に達して終了した場合は必ず`Unterminated`フラグを立てる（reparseの安定性判定が依存。基本設計5.5.1節）。
- `boundaryDependent`は、`end < bytes.length`のとき、最後に返した要素について次のいずれかが成り立てばtrue（基本設計5.5.1節の列挙の実装）。どれも「`end`で打ち切らなければ`bytes[end]`を読んで続きを消費していた」かの判定であり、`bytes[end]`の1バイトを見るだけで決まる:
  - `Unterminated`フラグ付きのトークン
  - regular run（数値・キーワード・`Unknown`）が`end`に接し、`bytes[end]`がregular byte
  - 単独の`>`が`end`に接し`bytes[end] === '>'`、または`<`で始まるトークンが`end - 1`から始まっている
  - コメントが`end`に接し、`bytes[end]`がCR/LFでない
  - `EndOfFile`がleading triviaを持つ（範囲末尾にトリビアが残った）
  - `KwEndstream`が`end`に接している（直後バイト条件の判定に`bytes[end]`が要る）

  `end === bytes.length`（フルパース）では範囲外が存在しないため常にfalse。

### 6.3 TokenSource（`token-source.ts`）

トリビアを次の実トークンへ吸着し、パーサに「実トークンの列」を見せる。

```ts
export interface CookedToken {
  kind: SyntaxKind; flags: TokenFlags;
  trivia: GreenTrivia[]; textLength: number;
  start: number; // 一時情報（builderには渡さない）
}

export class TokenSource {
  constructor(lexer: Lexer);
  peek(n?: number): CookedToken;  // n=0..2。トリビア透過の先読み（リングバッファ3枠）
  bump(): CookedToken;
  /** Integer Integer obj / Integer Integer R のパターン先読み（基本設計5.2.1節） */
  atObjHeader(): boolean;
  atReference(): boolean;
  /** peek(0)のトリビアに%%EOFパターンのCommentが含まれるか（同期トークン用） */
  hasEofCommentInTrivia(): boolean;
}
```

### 6.4 stream境界（`stream-boundary.ts`）

```ts
export type EndstreamMatch =
  | { found: true; bodyEnd: number; wsPreceded: boolean }
  | { found: false };  // Unterminated

/** 探索は [bodyStart, end) に限る。end はレキサーの範囲終端（フルパースでは bytes.length） */
export function findEndstream(bytes: Uint8Array, bodyStart: number, end: number): EndstreamMatch;
```

アルゴリズム（基本設計4.3節の実装）:

1. `bodyStart`から`end`までの範囲で`endstream`の出現を順次探索する。`end`を越える出現は見ない（範囲を越えて本体が伸びたことを`Unterminated`として検出するため。基本設計4.3節 Step 2）。探索プリミティブは環境判定で選ぶ: `Buffer.isBuffer`可用なら`[bodyStart, end)`の`subarray`をBufferビューにして`indexOf`（ネイティブ。`indexOf`は終端を取らないため、ビュー側で範囲を切る）、そうでなければBoyer-Moore-Horspool風のスキップテーブル付き手書き探索（ブラウザfallback）。
2. 各出現で「直後バイトがwhitespace/delimiter、または出現の終端が`end`に一致」を検査し、不成立なら次の出現へ。出現の終端が`end`に一致する場合（`end < bytes.length`）は直後バイトが範囲外で確定できないが、候補として採用してよい。その場合`KwEndstream`が`end`に接するため、`Lexer.boundaryDependent`により再レキシング結果は不安定と判定される（6.2節）。
3. 成立した出現のうち「直前バイトがwhitespace6種」の最初のものを採用。1パス目で見つからなければ、記録しておいた「直後条件のみ成立の最初の出現」を採用。実装は1パスで両候補を同時に追跡する（再走査しない）。
4. `bodyEnd`は基本設計4.3節のbodyEnd規則に従い、採用した`endstream`の直前にEOL（CRLF・LF・CR、高々1つ）があればそれを本体から除外した位置とする（除外分はWhitespaceトリビアとして`KwEndstream`に付く）。

---

## 7. パーサ（`parse/parser.ts`, `parse/recovery.ts`）

### 7.1 本体構造

```ts
export function parse(bytes: Uint8Array): SyntaxTree;

class Parser {
  private src: TokenSource;
  private builder: GreenBuilder;
  private diags: Diagnostic[];
  private sync: SyncStack;
  private depth: number;          // dict/arrayネスト深さ

  parseDocument(): void;          // LeadingJunk? Header? Segment+ TrailingJunk?
  parseHeader(): void;            // HeaderMarkerを消費してHeaderノード化
  parseSegment(): boolean;        // 1トークンも消費しなければfalse（進捗保証）
  parseIndirectObject(): void;
  parseObjectValue(): void;       // dispatch: dict/array/string/number/name/ref/keyword
  parseDictionary(): void;
  parseDictEntry(): void;
  parseArray(): void;
  parseStreamClause(): void;      // KwStream + StreamBody + KwEndstream(またはmissing)。StreamBodyはレキサーが必ずKwStreamの直後に出す（6.2節）。dictの後以外に現れたKwStream+StreamBodyはErrorNodeに包む
  parseXrefSection(): void;
  parseXrefSubsection(): void;
  parseXrefEntry(): void;         // Integer Integer (KwN|KwF)。妥当性は7.4節
  parseTrailerClause(): void;
  parseStartxrefClause(): void;
}
```

- `parseObjectValue`冒頭で`depth`検査: `MAX_NEST_DEPTH = 64`超過時は`LeftBracket`/`LeftDoubleAngle`をErrorNodeに包んで平坦に消費し、ネストせず継続（基本設計5.3節。値64は初期値、10章）。
- Reference/objヘッダ判定は`TokenSource.atObjHeader()/atReference()`（3トークン先読み・バックトラックなし）。

### 7.2 同期スタックとエラー回復（`recovery.ts`）

```ts
// const enumは使わない方針（3章）に合わせたconstオブジェクト＋union型
// EolBoundary: Xrefエントリ階層用。次トークンのleading triviaにEOLを含むWhitespaceがあるかで一致判定（基本設計5.3節「EOLトリビア境界」）
export const SyncPattern = { ObjHeader: 0, EofComment: 1, EolBoundary: 2 } as const;
export type SyncPattern = (typeof SyncPattern)[keyof typeof SyncPattern];

export interface SyncSet {
  kinds: ReadonlySet<SyntaxKind>;
  patterns: readonly SyncPattern[];
}

export class SyncStack {
  push(set: SyncSet): void;  pop(): void;
  /** 現在のトークンがどの階層の同期集合に一致するか。無一致ならnull */
  matchDepth(src: TokenSource): number | null;
}

/** 一致階層まで、途中トークンをErrorNodeへ包みながらスキップ。
    未クローズノードにはmissing tokenを挿入して閉じる（基本設計5.3節） */
function recoverTo(parser: Parser, targetDepth: number): void;
```

各parse規則は開始時に自分の同期集合をpushし、finallyでpopする。EOF到達（`EndOfFile`）はスキップ対象にせず、その場でmissing token挿入→全階層クローズ。

### 7.3 missing token挿入箇所の規約

- 期待トークン不在で回復する経路はすべて`builder.missingToken(expectedKind)`を通す。対象: `RightDoubleAngle` / `RightBracket` / `KwEndobj` / `KwEndstream` / `EndOfFile`前の未クローズ全般。
- missing tokenには対応する診断（`missing-token`、期待種別をdataに持つ）を必ず対で発行する。

### 7.4 xrefエントリの妥当性検査

`parseXrefEntry`は通常トークン列（Integer Integer KwN/KwF）として構築したうえで、次を検査して診断のみ発行する（木は変えない）:

- offsetのtextLength===10、generationのtextLength===5
- 区切りトリビアが「SP 1個」であること、行末が「SP+LF or SP+CR or CRLF」（20バイト固定形式）であること

違反は`xref-entry-malformed`1コード＋詳細メッセージに集約する（コードを細分しない。10章）。

---

## 8. インクリメンタル再パース（`parse/reparse.ts`）

```ts
export interface Edit {
  start: number;
  deletedLength: number;
  insertedBytes: Uint8Array;
}

/** 常に正しい完全な木を返す。局所差し替え不能時は内部でフルパース */
export function reparse(tree: SyntaxTree, edit: Edit): SyntaxTree;
```

段階（基本設計5.5.1節の実装）:

1. `newBytes`を構築（`spliceBytes(old, edit)`。1回のallocateとcopyWith x3）。
2. 候補特定: `coveringElement`は単一オフセットを取るため、編集範囲の両端（`edit.start`と`edit.start + edit.deletedLength`）それぞれの`coveringElement`の最小共通祖先を起点に、祖先方向へ最内の`IndirectObject | XrefSection | TrailerClause | StartxrefClause`を探す。境界ちょうど（`edit.start`が候補の`fullStart`または`end`に一致）は隣接要素も含む範囲に拡大。包含不能（Segment境界またぎ・Header/LeadingJunk領域）→ 即フルパース。
3. 再レキシング＋再パース: 候補のバイト範囲（編集適用後の対応範囲）に`new Lexer(newBytes, { start: from, end: to, streamBodyHints })`＋該当規則のみのミニパースを実行。`streamBodyHints`は下記「stream境界キャッシュ」で作る。
4. 安定性検証。**不安定条件は次のいずれか**:
   - 先頭・末尾トークンの意味的境界が変化（`obj`で始まらない／`endobj`で終わらない等）
   - `lexer.boundaryDependent === true`（末尾要素の長さが範囲外のバイトに依存し得る。Unterminatedだけでなく、範囲終端に接するregular run・`>`・コメント・残ったトリビア・`endstream`を含む。6.2節、基本設計5.5.1節）
   - ミニパースが範囲を消費し尽くさなかった／不足した
5. 安定 → Green差し替え: 対象GreenNodeを置換し、祖先の`fullLength`をO(深さ)で再計算した新rootを作る（兄弟は参照共有）。不安定 → 親Segment範囲でStep 3をやり直し、それでも不安定ならフルパース。

**診断の継承規則**: `SyntaxTree.diagnostics`（絶対オフセット保持）はreparse時に次のように更新する。差し替え範囲より前で完結する旧診断はそのまま引き継ぎ、差し替え範囲と交差する旧診断は破棄してミニパースの新診断で置換し、差し替え範囲より後ろの旧診断は`insertedBytes.length - deletedLength`分オフセットをシフトして引き継ぐ。フルパースフォールバック時は全診断を再収集する。

**stream境界キャッシュ**（基本設計4.3節の実装要件(b)）: 候補範囲内の各`StreamClause`について、編集範囲（旧座標の閉区間`[edit.start, edit.start + edit.deletedLength]`）が閉区間`[KwStream.start, KwEndstream.end]`（旧座標）に**接触も交差もしない**場合に限り、旧境界を新座標へシフトした`StreamBodyHint`（`bodyEnd`・`endstreamStart`）を、新座標の`bodyStart`をキーとして`streamBodyHints`に入れる。旧`StreamBody`のバイト範囲との交差だけで判定してはならない。境界決定は本体の外側のバイト（`stream`直前1バイト・直後のEOL、本体直後のEOL、`endstream`の直後1バイト）にも依存するためである（基本設計4.3節）。`KwEndstream`がmissingの（Unterminatedの）StreamClauseはヒントを作らない。レキサーはヒントを使う前に、新位置の9バイトが`endstream`に一致し範囲内に収まることを検査し、不一致なら`findEndstream`に戻る（6.2節。防御的検査であり、上の条件が正しければ常に一致する）。

---

## 9. 診断・ダンプ・CLI

### 9.1 Diagnostic（`diagnostics.ts`）

```ts
export type DiagnosticSeverity = 'error' | 'warning' | 'info';

// codeは各層で拡張するため（意味解析層が独自コードunionを入れる。基本設計6章）ジェネリックにする
export interface Diagnostic<C extends string = string> {
  code: C;                       // 本パッケージではDiagnostic<ParserDiagnosticCode>として使う
  severity: DiagnosticSeverity;
  start: number;                 // バイトオフセット
  length: number;
  message: string;               // 英語。表示言語化はLSP層の将来課題
  data?: Record<string, unknown>; // 例: { expected: SyntaxKind }
}

export type ParserDiagnosticCode =
  | 'missing-token'          // error
  | 'unexpected-token'       // error（ErrorNode化したトークン列）
  | 'unterminated-string'    // error
  | 'unterminated-stream'    // error
  | 'header-missing'         // warning
  | 'segment-section-missing' // warning（Segmentのxref/trailer/startxref欠落。dataに欠落種別。基本設計5.2節）
  | 'nesting-too-deep'       // error
  | 'xref-entry-malformed'   // warning
  | 'stream-eol-nonconforming'; // warning（streamキーワード直後がCR単体等）
```

この型を意味解析パッケージが共有する（codeのunionは各層で拡張。基本設計6章）。

### 9.2 CSTダンプ（`dump.ts`）

```ts
export function dumpCst(tree: SyntaxTree, opts?: { trivia?: boolean }): string; // 既定 trivia: true
```

形式（スナップショットの正）: 1行1要素、インデント2スペース、`Kind@fullStart..end`、トークンは内容を最大32バイトまで表示（非印字バイトは`\xNN`）、フラグは`[unterminated]`等を後置。末尾に`--- diagnostics ---`セクションで診断を列挙。

```
Document@0..120
  Header@0..8
    HeaderMarker@0..8 "%PDF-1.4"
  Segment@8..120
    IndirectObject@8..44
      Integer@8..10 "1" (leading: Whitespace 1)
      ...
```

### 9.3 CLI（`cli.ts`）

`pdf-cst-dump <file> [--no-trivia]`。標準出力にダンプ。ファジング・目視デバッグ・スナップショット生成の共用入口（基本設計7章）。

---

## 10. テスト構成・実装順序

```
tests/
├── LexerTest.hx           … トークン単位のunit（utest）
├── SnapshotTest.hx        … corpus/ の各ファイル → dumpCst をスナップショット比較
├── __snapshots__/         … スナップショットの保存先（更新はフラグ付きで実行したときだけ）
├── ReparseTest.hx         … 「reparse結果 === フルパース結果」の等価性検証（最重要プロパティ）
├── PropertyTest.hx        … ランダムバイト列でクラッシュなし・幅不変条件成立
├── support/               … 自作のテストヘルパー（スナップショット比較、ランダム入力の生成器）
└── bench/                 … フルパース／単一オブジェクト編集reparseの計時（Nodeターゲット）
```

- reparse等価性（`dumpCst(reparse(t, e)) === dumpCst(parse(splice(bytes, e)))`）をランダム編集で回すことをプロパティテストの柱とする。
- スナップショット比較とランダム入力の生成器は自作する（統括3章）。最低限の機能: 生成器はシード値を指定して再現でき、失敗時にシード値と入力を報告する。失敗した入力を小さくする縮小（shrinking）は、必要になってから足す。
- テストはNodeターゲットで実行することを正とする（本番と同じ実行環境）。開発中はevalターゲット（`--interp`）でも回せるようにしておく。
- カバレッジガイド付きファジング（Jazzer.js）はM6で導入（基本設計9章）。Haxeが出力したJSに対してハーネスを書く。

**実装マイルストーン**: M1 Green/Red＋Lexer＋dump＋スナップショット基盤 → M2 object文法（dict/array/値・Reference先読み） → M3 StreamClause＋境界探索 → M4 xref/trailer/Segment＋エラー回復一式 → M5 reparse → M6 ファジング・ベンチ・診断仕上げ。各M完了時点でスナップショットが常にグリーンであることを維持する。

---

## 11. 実装時判断に委ねる事項

- `MAX_NEST_DEPTH = 64`の妥当性（実PDFコーパスでの最大ネスト実測後に調整。公開オプション化はしない）
- `TokenSource`のリングバッファ枠数（先読み最大3で足りる想定。Reference判定の詳細次第で+1）
- xref-entry-malformedの検査をどこまで細分した診断メッセージにするか
- `findEndstream`の探索実装。純HaxeのBoyer-Moore-Horspoolで開始し、M6のベンチマークで予算（基本設計2.3.1節）に届かなければ、この関数の中だけJSターゲット向けに`Buffer.indexOf`へ条件コンパイルで切り替える（基本設計4.3節）
- `Int`が32ビットであることによる、ファイルサイズ2GiB未満という前提（0章）。超えるファイルは開く時点で拒否する（LSP層）か、オフセット型を変えるかは、必要になったら決める
- dumpのトークン内容表示の打ち切り長（32バイト仮置き）
