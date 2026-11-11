# VS Code拡張の実行環境（JS以外の言語で動かす方法）

VS Code拡張の入口（`activate`関数）は必ずJSで、Extension Host（Node.js、Web版のVS CodeではWeb Worker）が読み込んで呼び出す。重い処理をJS以外の言語で書くには、「別プロセスに出す」か「WASMで動かす」かのどちらかになる。

## なぜ必要か

拡張の本体（rawpdfならパーサや意味解析）を、TS以外の言語（Haxeなど）で書きたい場合がある。そのとき「どこまでがJSでなければならず、どこからが自由か」を知らないと、パッケージ構成や配布方法を決められない。

## どういう仕組みか

VS Codeは拡張を、エディタ本体とは別の**Extension Host**というプロセスで動かす。Extension HostはNode.jsなので、拡張の`main`に書いたJSモジュールを`require`/`import`し、`activate(context)`を呼ぶ。この入口の部分だけは、言語を選べない。

JS以外の言語を使う方法は3つある。

| 方法 | 仕組み | 例 | 利点 | 代償 |
|---|---|---|---|---|
| 別プロセス | JSの薄いクライアントがバイナリを起動し、標準入出力でLSP（JSON-RPC）を話す | rust-analyzer, gopls, clangd | 言語を完全に自由に選べる。JSとの型の境界がメッセージ（JSON）だけになる | OS・CPUごとのバイナリと、プラットフォーム別VSIXが必要。Web版VS Codeでは動かない |
| WASM | Extension Hostの中でWebAssemblyを動かす（`@vscode/wasm-wasi`、Component Modelのバインディング） | Rust/C++をWASMに出力した拡張 | 1つのファイルで全OSとWeb版に対応できる | WASMに出力できる言語に限られる（Haxeには公式のWASMターゲットがない） |
| 宣言だけ | TextMate文法・`language-configuration.json`・スニペットをJSONで書く | 多くの言語のシンタックスハイライト拡張 | コードが要らない | できることがハイライトや括弧の対応などに限られる |

デバッガ（Debug Adapter Protocol）も、別プロセスと同じ構造をとる。

## 具体例：rawpdfを「TSクライアント＋ネイティブサーバー」にした場合

```
VS Code ──(Extension Host / Node)── client.ts（数十行：サーバーの起動と接続だけ）
                                         │ stdin/stdout（LSPのJSON-RPC）
                                         ▼
                                  rawpdf-server（Haxe → HashLink/C++のネイティブバイナリ）
                                    ├ parser
                                    ├ semantics
                                    └ LSPのハンドラ
```

- 良い点：parser・semantics・サーバーがすべてHaxeの中で完結する。HaxeからTSへの`.d.ts`の生成（[HaxeとTSの相互運用](haxe-ts-interop.md)）が要らなくなる
- 悪い点：プラットフォームごとのビルドと配布の手間がかかる。LSPの型定義（Haxe版）の追従を自分で背負う

### 落とし穴：LSPの外にある仕事はクライアントに残る

LSPが扱うのは「開いているテキスト文書についての言語機能」だけ。VS Code APIでしか書けない仕事（`FileSystemProvider`、webview、カスタムエディタ）は、Extension Host側（JS）で動く。それがパーサの結果を必要とするなら、次のどちらかを選ぶことになる。

1. **カスタムリクエストでサーバーに頼む**：例えば`readFile`を`rawpdf/project`のような独自リクエストに置き換える。境界はJSONのままだが、メッセージの型をTSとHaxeの両方に書き、同期を保つ必要がある。また、サーバーが落ちるとその機能（例えば保存）も止まる
2. **そのロジックをJSとしてもクライアントに持つ**：Haxe→JSの相互運用の問題が戻ってくる

rawpdfでは、投影層（バイナリ⇔仮想テキスト）が`FileSystemProvider`の`readFile`/`writeFile`の中で動くので、この落とし穴に当たる（`pdf-lsp-editor-design.md` 3.1節）。

### 「純Haxe」はネイティブとは限らない

サーバーをHaxe→JSにしてNode上で動かす選択肢もある。TSからHaxeを呼ぶ必要はない（HaxeからNodeを呼ぶ、整備された方向だけを使う）ので、`.d.ts`は要らない。vshaxeのJSON-RPCライブラリやLSPの型定義もそのまま使える。ネイティブにする場合、vshaxeの`vscode-json-rpc`はトランスポートがNode専用（`jsonrpc/node`、hxnodejsに依存）なので、stdioのフレーミング（`Content-Length`ヘッダ）は自分で書くことになる。

## このプロジェクトでの使われ方

- 現行の設計は、Node上のLSPサーバーがパーサをライブラリとして直接呼ぶ前提になっている（統括設計3章のツールチェーン、`pdf-lsp-editor-design.md`）。別プロセスのネイティブサーバーにするなら、設計ドキュメントの更新から始める判断になる
- VSIXのパッケージングとバンドラについては[配布形態とバンドラ](bundler-and-distribution.md)を参照

## 参考

- VS Code公式ドキュメント「Extension Host」「Language Server Extension Guide」「Using WebAssembly for Extension Development」
- rust-analyzerの`editors/code/`：TSの薄いクライアントの実例
- vshaxe（`src/`）：Haxeで書かれたVS Code拡張の実例。ただし`vscode` APIのexternsはVS Code 1.97時点で止まっている（2026-11確認）

## 関連ノート

- [HaxeとTSの相互運用](haxe-ts-interop.md)
- [配布形態とバンドラ](bundler-and-distribution.md)
