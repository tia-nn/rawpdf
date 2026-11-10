# 実装WBS

最終更新: 2026-11-11
用途: 実装の作業分解と進捗管理。設計ドキュメント（特にパーサ詳細設計10章のマイルストーン）から導いたもの。設計が変わったらこちらも追従させる。

## 使い方

- **細かさ**: パーサ（M0〜M6）はタスク単位（数時間〜1日程度）まで分けてある。意味解析（S）とLSP（L）は、パーサ実装中に設計が変わる可能性が高いため、マイルストーン単位にとどめ、着手前に細分化する。
- **タスクの中の手順は自分で決める**。着手時に「何から書くか・どの順でテストを足すか」を自分で分解し、必要ならClaudeにレビューしてもらう（`CLAUDE.md`の進め方）。
- **各タスクの項目**:
  - 完了条件: これを満たしたらチェックを付ける。基本的に「どのテストが通るか」で書いてある
  - 前提: 先に終わっている必要があるタスク
  - 参照: 関係する設計ドキュメントの節（「基本」＝`pdf-cst-parser-design.md`、「詳細」＝`pdf-cst-parser-detailed-design.md`、「統括」＝`pdf-editor-overview-design.md`）
  - 新しい概念: そのタスクで初めて出てくる概念。説明を受けたら`notes/`に残す
- **各マイルストーンの完了時**に、スナップショットテストとプロパティテストがすべてグリーンであることを確認する（詳細10章）。

---

## M0 リポジトリ基盤

- [ ] **M0-1 pnpm workspaceとパーサパッケージの雛形**
  - 完了条件: `packages/pdf-cst-parser`に`package.json`（`"type": "module"`）・`tsconfig.json`（strict, ES2022）・vitestを置き、ダミーテスト1本が`pnpm -r test`で通る。`pnpm -r build`でtscが通る
  - 前提: なし
  - 参照: 統括3章、詳細2章
  - 新しい概念: pnpm workspaces、TypeScriptのESM設定（`module`・`moduleResolution`）
- [ ] **M0-2 最小のCI**
  - 完了条件: GitHub Actionsでpush時にinstall・build・testが走り、グリーンになる
  - 前提: M0-1
  - 参照: 統括3章・8章（CIの詳細は未決定。最小構成で始める）
  - 新しい概念: GitHub Actions
- [ ] **M0-3 初期コーパス（手書きの最小PDF）**
  - 完了条件: `corpus/`に手書きのPDFを数本置き、`corpus/README.md`に各ファイルの目的を書く。最低限: 1ページの正常なPDF（LF）、同じ内容のCRLF版、incremental update（2セグメント）、ヘッダ欠落、`endobj`欠落、閉じていないliteral string
  - 前提: なし（M0-1と並行可）
  - 参照: 統括6章、基本9章
  - 新しい概念: **PDFのファイル構造**（ヘッダ・indirect object・xref・trailer・startxref・incremental update）。最初に押さえておくと以降が楽

## M1 Green/Red木＋Lexer＋dump＋スナップショット基盤

- [ ] **M1-1 SyntaxKindと分類ヘルパ**
  - 完了条件: `syntax/kind.ts`に全種別と`isTrivia`/`isToken`/`isNode`/`isKeyword`があり、unitテストが通る
  - 前提: M0-1
  - 参照: 詳細3章、基本4.5
  - 新しい概念: `const enum`を使わず「constオブジェクト＋union型」で列挙を表す理由
- [ ] **M1-2 バイト分類テーブル**
  - 完了条件: `lex/byte-class.ts`の256要素テーブルが、whitespace 6種・delimiter 10種・それ以外regularに分類されることをテストで確認
  - 前提: なし
  - 参照: 基本4.1、詳細6.1
- [ ] **M1-3 Lexer: 構造モードの基本トークン**
  - 完了条件: whitespace・コメント・`HeaderMarker`・`[` `]` `{` `}` `<<` `>>`・単独`>`（Unknown）・Name・regular run（Integer/Real/キーワード/Unknown）について、基本4.2節の各ケースのunitテストが通る
  - 前提: M1-1, M1-2
  - 参照: 基本4.2、詳細6.2
  - 新しい概念: 手書きレキサーと最長一致（maximal munch）
- [ ] **M1-4 Lexer: 文字列のサブスキャン**
  - 完了条件: literal string（括弧の深さ・エスケープ）とhex stringが切り出せ、閉じない場合は`Unterminated`フラグが立つ。それぞれunitテストあり
  - 前提: M1-3
  - 参照: 基本4.2、詳細6.2
- [ ] **M1-5 Green層とGreenBuilder**
  - 完了条件: `GreenTrivia`/`GreenToken`/`GreenNode`と、イベント型の`GreenBuilder`（`startNode`/`token`/`missingToken`/`finishNode`/`finish`）がある。手で組んだ木で`fullLength`が子の合計になることをテストで確認
  - 前提: M1-1
  - 参照: 基本5.1、詳細4章
  - 新しい概念: **Green木**（不変・相対長・構造共有）、**イベント型ビルダー**（rowanの`GreenNodeBuilder`）
- [ ] **M1-6 TokenSource（トリビアの吸着と先読み）**
  - 完了条件: トリビアが次の実トークンの`leadingTrivia`に付くこと、ファイル末尾のトリビアが`EndOfFile`に付くこと、`peek(0..2)`が動くことをテストで確認
  - 前提: M1-3, M1-5
  - 参照: 基本4.4、詳細6.3
  - 新しい概念: leading triviaだけを使う付与規則と、幅不変条件（全要素の幅の合計＝ファイルサイズ）
- [ ] **M1-7 Red層**
  - 完了条件: `SyntaxTree`/`SyntaxNode`/`SyntaxToken`があり、`fullStart`/`start`/`end`・`children()`・`firstToken()`/`lastToken()`・`coveringElement()`・`bytes()`のテストが通る
  - 前提: M1-5
  - 参照: 基本5.1、詳細5章
  - 新しい概念: **Red木**（親ポインタと絶対位置を持つ軽量ビュー。遅延生成）、`fullStart`と`start`の区別
- [ ] **M1-8 仮パーサ（文法なし）**
  - 完了条件: 全トークンを`Document`直下に平らに並べるだけの`parse()`ができ、コーパス全ファイルで幅不変条件が成り立つ
  - 前提: M1-6, M1-7
  - 参照: 基本4.4
  - 備考: M2以降で本物の文法に置き換える。先にパイプライン全体（bytes → 木 → dump）を貫通させるための足場
- [ ] **M1-9 CSTダンプとCLI**
  - 完了条件: `dumpCst`が詳細9.2節の形式で出力し、`pdf-cst-dump <file>`で標準出力に出せる
  - 前提: M1-8
  - 参照: 詳細9.2・9.3
- [ ] **M1-10 スナップショットテストとプロパティテストの基盤**
  - 完了条件: `corpus/`の各ファイルの`dumpCst`がスナップショット比較される。fast-checkで「ランダムなバイト列でもクラッシュせず、幅不変条件が成り立つ」テストが通る
  - 前提: M1-9, M0-3
  - 参照: 基本9章、詳細10章
  - 新しい概念: スナップショットテスト、**プロパティベーステスト**（fast-check）

## M2 オブジェクトの文法

- [ ] **M2-1 Parserの骨格とスカラー値**
  - 完了条件: `Parser`クラスと`parseObjectValue`が、数値・Name・文字列・`true`/`false`/`null`を値として読める（仮パーサを置き換え始める）
  - 前提: M1-10
  - 参照: 詳細7.1
  - 新しい概念: 再帰下降パーサ
- [ ] **M2-2 Array・Dictionary・DictEntry**
  - 完了条件: ネストした配列・辞書が木になり、閉じないままEOFに達した場合はmissing token＋`missing-token`診断が出る
  - 前提: M2-1
  - 参照: 基本5.3（missing tokenの合成）、詳細7.3・9.1
  - 新しい概念: **missing token**（幅ゼロの合成トークン）、診断（Diagnostic）の型
- [ ] **M2-3 Referenceの先読みとIndirectObject**
  - 完了条件: `[1 2 R]`がReference 1つ、`[1 2 3]`がInteger 3つになる。`n g obj ... endobj`がIndirectObjectになる。トリビアを挟んだ`1 % c\n2 R`もReferenceになる
  - 前提: M2-2
  - 参照: 基本5.2.1、詳細6.3・7.1
  - 新しい概念: バックトラックなしの固定長先読み（LL(k)的な判定）
- [ ] **M2-4 ネスト深さの上限**
  - 完了条件: 深さ64を超えるネストで`nesting-too-deep`診断が出て、スタックオーバーフローしない
  - 前提: M2-2
  - 参照: 基本5.3、詳細7.1

## M3 StreamClauseと境界探索

- [ ] **M3-1 findEndstream**
  - 完了条件: 範囲終端つきの探索、直後バイト条件、直前空白の優先、フォールバック候補、bodyEndのEOL除外規則、見つからない場合のUnterminatedについてunitテストが通る
  - 前提: M1-2
  - 参照: 基本4.3、詳細6.4
  - 新しい概念: `/Length`を参照せずバイト走査で境界を決める理由と、そのトレードオフ
- [ ] **M3-2 Lexerのstream本体モード**
  - 完了条件: `stream`の直後のEOL 4パターン（CRLF/LF、CR単体、空白＋EOL、EOLなし）でトリビアと本体の境界が設計どおりになる。`StreamBody`が常に（長さ0でも）出る。本体先頭が`0x0A`や`0x00`でも本体に含まれる
  - 前提: M1-6, M3-1
  - 参照: 基本4.2・4.3、詳細6.2
  - 新しい概念: レキサーのモード切替（文脈自由に保つ理由）
- [ ] **M3-3 parseStreamClause**
  - 完了条件: dictの後のstreamがStreamClauseになり、`endstream`欠落時はmissing token。dictの後以外の`stream`はErrorNodeに包まれる。非準拠EOLで`stream-eol-nonconforming`診断が出る
  - 前提: M2-3, M3-2
  - 参照: 詳細7.1・9.1
- [ ] **M3-4 `/Length`非参照のテスト**
  - 完了条件: `/Length`が一致・不一致・間接参照の3パターンで境界が変わらないこと、本体中に早すぎる「空白＋`endstream`」がある場合の挙動がスナップショットで固定されている
  - 前提: M3-3
  - 参照: 基本9章

## M4 xref・trailer・Segmentとエラー回復

- [ ] **M4-1 HeaderとLeadingJunk**
  - 完了条件: 先頭の`%PDF-1.x`がHeaderになる。ヘッダ前のjunkはErrorNode＋`unexpected-token`。ヘッダが無い場合は`header-missing`を出してSegmentの解析を続ける
  - 前提: M2-3
  - 参照: 基本5.2、詳細1章
- [ ] **M4-2 XrefSection・XrefSubsection・XrefEntry**
  - 完了条件: classic xrefが木になり、20バイト形式からずれたエントリで`xref-entry-malformed`が出る（木は変わらない）
  - 前提: M2-1
  - 参照: 基本4.5（xrefエントリの表現）、詳細7.4
- [ ] **M4-3 TrailerClause・StartxrefClause**
  - 完了条件: `trailer << ... >>`と`startxref N`が木になる
  - 前提: M2-2
  - 参照: 基本5.2
- [ ] **M4-4 Segmentとincremental update**
  - 完了条件: 2セグメントのコーパスが2つのSegmentになる。xref/trailer/startxrefの欠落で`segment-section-missing`。1トークンも消費しないSegmentを作らない（進捗保証）ことをテストで確認
  - 前提: M4-1, M4-2, M4-3
  - 参照: 基本5.2
  - 新しい概念: incremental updateとSegmentの対応、ループの進捗保証
- [ ] **M4-5 同期スタックによるエラー回復**
  - 完了条件: `SyncStack`と`recoverTo`があり、`>>`が欠けたdictの後に次のオブジェクトが始まるケースなどで、未クローズの構文にmissing tokenが入り、次のオブジェクトから正しく解析が再開される
  - 前提: M4-4
  - 参照: 基本5.3、詳細7.2・7.3
  - 新しい概念: **同期トークンによるエラー回復**（panic mode recoveryと、それを階層化したスタック方式）
- [ ] **M4-6 破損コーパスでの確認**
  - 完了条件: M0-3の破損PDFすべてでスナップショットが妥当な形になり、プロパティテストもグリーン
  - 前提: M4-5

## M5 インクリメンタル再パース

- [ ] **M5-1 「常にフルパースするreparse」と等価性テスト**
  - 完了条件: `reparse(tree, edit)`が内部でフルパースするだけの実装と、ランダム編集で`dumpCst(reparse(t, e)) === dumpCst(parse(splice(bytes, e)))`を確かめるプロパティテストがある
  - 前提: M4-6
  - 参照: 基本5.5.2、詳細8章・10章
  - 備考: 先に正しさの基準（オラクル）を用意しておき、以降のタスクで最適化しても常にこのテストで検証できるようにする
  - 新しい概念: テストオラクル（遅いが正しい実装との比較）
- [ ] **M5-2 Lexerの範囲指定とboundaryDependent**
  - 完了条件: `new Lexer(bytes, { start, end })`で範囲内だけを字句解析でき、詳細6.2節の6ケースで`boundaryDependent`が正しく判定される
  - 前提: M3-2
  - 参照: 基本5.5.1、詳細6.2
- [ ] **M5-3 候補ノードの特定**
  - 完了条件: 編集範囲の両端から、最内の`IndirectObject | XrefSection | TrailerClause | StartxrefClause`を見つけられる。境界ちょうどの編集・Segmentをまたぐ編集の扱いもテストあり
  - 前提: M1-7
  - 参照: 基本5.5.1 Step 1、詳細8章 Step 2
- [ ] **M5-4 ミニパースと安定性検証**
  - 完了条件: 候補範囲だけを再パースし、詳細8章 Step 4の不安定条件を判定できる
  - 前提: M5-2, M5-3
  - 参照: 基本5.5.1 Step 2〜3、詳細8章 Step 3〜4
- [ ] **M5-5 Green木の部分差し替え**
  - 完了条件: 対象ノードだけを差し替え、祖先を作り直した新しいrootができる。変わっていない兄弟ノードが`===`で同一であることをテストで確認
  - 前提: M5-4
  - 参照: 基本5.5、詳細8章 Step 5
  - 新しい概念: **パスコピー**（永続データ構造で、変更箇所から根までだけを作り直す手法）
- [ ] **M5-6 範囲拡大とフォールバック**
  - 完了条件: 不安定ならSegmentに広げて再試行し、それでも駄目ならフルパースする。M5-1の等価性テストがグリーン
  - 前提: M5-5
  - 参照: 基本5.5.1 Step 4
- [ ] **M5-7 診断の継承**
  - 完了条件: 差し替え範囲の前・交差・後ろの診断が詳細8章の規則どおりに引き継がれる（等価性テストに診断も含めて検証）
  - 前提: M5-6
  - 参照: 詳細8章「診断の継承規則」
- [ ] **M5-8 stream境界キャッシュ**
  - 完了条件: 再利用条件を満たす編集では`findEndstream`が呼ばれず、満たさない編集（本体直後のEOL・`endstream`直後の1バイトの編集など）では再探索される。等価性テストがグリーン
  - 前提: M5-6
  - 参照: 基本4.3 (b)、詳細8章「stream境界キャッシュ」

## M6 ファジング・ベンチマーク・仕上げ

- [ ] **M6-1 ベンチマーク**
  - 完了条件: vitest benchでフルパース（小/中/大）と単一オブジェクト編集のreparseを計測し、トークンあたりのメモリオーバーヘッドも出せる。基本2.3.1節の目標との比較を記録する
  - 前提: M5-6
  - 参照: 基本2.3.1、統括5章
- [ ] **M6-2 カバレッジガイド付きファジング**
  - 完了条件: Jazzer.jsのハーネスでparseとreparseを一定時間回し、クラッシュしない
  - 前提: M5-6
  - 参照: 基本9章、統括3章
  - 新しい概念: カバレッジガイド付きファジング
- [ ] **M6-3 実在の破損PDFの収集**
  - 完了条件: OSSのテストスイート由来の破損PDFをライセンスを確認したうえでコーパスに追加し、スナップショット化する
  - 前提: M4-6
  - 参照: 基本9章、統括6章・8章（ライセンス確認フローは未決定）
- [ ] **M6-4 公開APIと診断の仕上げ**
  - 完了条件: `index.ts`の公開APIが基本6章と一致し、診断メッセージが揃っている。パッケージのREADMEがある
  - 前提: M5-8
  - 参照: 基本6章、詳細9.1・11章

---

## S 意味解析（`pdf-semantics`）— 着手前に細分化する

マイルストーンは意味解析詳細設計11章のとおり。

- [ ] **S0** パッケージ雛形と、依存方向のリント（dependency-cruiser）をCIに追加（統括3章）
- [ ] **S1** ObjectIndex＋Revision骨格＋semantic dump
- [ ] **S2** 値デコード一式＋型付きビュー（`DictView`/`ArrayView`）
- [ ] **S3** 参照解決＋逆参照インデックス＋文書構造グラフ
- [ ] **S4** `/Length`検証＋診断の集約（`/Length`不一致の統合テストを含む）
- [ ] **S5** プロパティテスト・ベンチマーク・ファジングの統合

## L LSP・エディタ拡張（`pdf-lsp-editor`）— 着手前に細分化する

順序はLSP設計8章のとおり。LSP層の詳細設計を書くことから始める（統括のドキュメントツリー）。

- [ ] **L0** LSP層の詳細設計を書く。VSIXのバンドル方針（統括8章）もここで決める
- [ ] **L1** 投影層を単体で完成させる（往復性テストまで）
- [ ] **L2** 診断配信でパイプライン全体（キー入力 → reparse → semantics → 投影 → 診断）を貫通させる
- [ ] **L3** ナビゲーション（definition・references）
- [ ] **L4** 構造表示（documentSymbol・foldingRange・semanticTokens・hover）
- [ ] **L5** 入力支援（completion）
- [ ] **L6** 「コーパス全ファイルを開いて無編集で保存し、バイト一致する」E2EテストをCIに置く（統括6章）
