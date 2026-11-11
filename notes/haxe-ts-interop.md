# HaxeとTSの相互運用

HaxeでJSに出力したコードをTSから使うには、「ESMとして出力する」「型定義（`.d.ts`）を用意する」「クラスの重複を避ける」の3つを解決する必要がある。Haxe界隈ではあまり整備されていない方向で、前例は少ない。

## なぜ必要か

rawpdfでparser（とsemantics）をHaxeで書き、lsp-editorをTSで書く場合、TSからHaxe製のコードをimportすることになる。ここが素直に動かないと、Haxeを選んだ利点が境界の手間で消えてしまう。

## どういう仕組みか

### 方向は2つある

- **Haxe → 既存のJS/TSライブラリを使う**: externs（外部ライブラリの型をHaxeで宣言したもの）を書く。`dts2hx`で`.d.ts`から自動変換できる。こちらが主流で、ツールも整っている
- **TS → Haxe製のコードを使う**: Haxeの出力に`.d.ts`を付ける必要がある。こちらは手薄

### TSからHaxe製のコードを使うための3つの課題

1. **モジュール形式**: Haxe標準のJS出力は基本的に1ファイルにまとまる。ESMで、かつモジュールごとに分けて出力したいなら**genes**を使う
2. **型定義**: 方法は3つある
   - genesの`-D dts`で自動生成する（DCEで消えた型を参照してしまうことがある）
   - hxtsdgenで、`@:expose`を付けたものだけ生成する（WIP）
   - 手で書く（窓口が狭ければ現実的）
3. **クラスの重複**: Haxeのビルドを2回に分けると（例：parserとsemanticsを別々にビルド）、両方のJSにparserのクラスがコピーされる。TS側でそれぞれから受け取ったオブジェクトは**別のクラス**として扱われ、`instanceof`や`Std.isOfType`が静かに偽になる

### 対策の方針

- Haxeのコードは1回のビルドでまとめて出力するか、genesでモジュールごとに出力して、互いに`import`させる
- TSに見せる**窓口（ファサード）を狭く**する。プレーンなオブジェクトや配列を返す関数を十数個用意する程度にして、Haxeの内部の型を外に出さない
- ターゲット固有のコード（`js.*`パッケージ、`untyped`など）は窓口の層に閉じ込め、parserやsemanticsの中身はターゲットに依存しないHaxe（`haxe.io.Bytes`など）で書く。こうしておくと、テストを速いターゲット（eval/HashLink）で回せるうえ、将来ネイティブのLSPサーバー（[VS Code拡張の実行環境](vscode-extension-runtime.md)）に切り替える道も残る

## 具体例：クラスの重複

```
parser.js     : class GreenNode {...}          ← ビルドA
semantics.js  : class GreenNode {...}（コピー） ← ビルドB（parserを含めてビルド）

lsp-editor(TS):
  const node = semantics.resolve(...)   // ビルドBのGreenNode
  parser.isNode(node)                   // ビルドAのGreenNodeで判定 → false
```

## このプロジェクトでの使われ方

- 2026-11-12に、parser・semantics・language serverをHaxeで書き、VS Code拡張のクライアントだけをTSで書く構成に決めた（統括設計3.1節）。**この構成では、TSからHaxeを呼ぶ方向の相互運用は発生しない**。境界はLSPのメッセージだけになる
- 投影層などVS Code APIの中でパース結果が要る処理は、カスタムリクエストでサーバーに委譲する（LSP設計3.5節）。そのため、上の3つの課題はどれも避けられている
- この構成でも残る相互運用は、Haxeから既存のJSを使う方向（hxnodejs、vshaxeの`vscode-json-rpc`）だけで、こちらは整備されている

## 参考

- genes: https://github.com/samwightt/genes
- hxtsdgen: https://github.com/nadako/hxtsdgen
- dts2hx: https://www.npmjs.com/package/dts2hx
- OpenFL（Haxe製で、npmに型定義付きで配布されている数少ない例）: https://www.npmjs.com/package/openfl

## 関連ノート

- [VS Code拡張の実行環境](vscode-extension-runtime.md)
- [配布形態とバンドラ](bundler-and-distribution.md)
