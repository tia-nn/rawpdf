# lix（Haxeのバージョンとライブラリの固定）

lixは、Haxeのプロジェクトごとに「どのHaxeコンパイラと、どのライブラリのどの版を使うか」を固定するツール。設定ファイルをリポジトリにコミットしておけば、別のマシンやCIでも同じ環境を再現できる。npmでいう`package.json`の`engines`/`packageManager`とlockfileを合わせた役割を持つ。

## なぜ必要か

Haxe標準のパッケージマネージャhaxelibには、次の2つの弱点がある。

- **ライブラリがマシン全体で共有される**: AとBという2つのプロジェクトが同じライブラリの別の版を必要としても、基本的には1つの版しか有効にできない（`haxelib newrepo`でプロジェクト専用の置き場を作れるが、版の記録はされない）
- **版を記録するlockfileがない**: 「このプロジェクトはutest 1.13.2で動いていた」という情報がリポジトリに残らないので、CIや別のマシンで再現できない
- **Haxe自体の版を固定する仕組みがない**: マシンに入っている`haxe`がそのまま使われる

lixは、この3つをプロジェクトの中のファイルで解決する。

## どういう仕組みか

### 1. `.haxerc`：Haxe自体の版を固定する

プロジェクトのルートに置くJSONファイル。

```json
{ "version": "4.3.7", "resolveLibs": "scoped" }
```

- `version`: 使うHaxeの版（リリース版の番号のほか、nightlyのコミットハッシュも書ける）
- `resolveLibs: "scoped"`: ライブラリを、マシン全体ではなく、このプロジェクトの`haxe_libraries/`から解決する

lixをインストールすると、`haxe`コマンドは**シム**（本物の`haxe`の前に立つ小さな中継プログラム）になる。シムは、カレントディレクトリから上に向かって`.haxerc`を探し、書かれた版のコンパイラを起動する。そのため、モノレポではルートに1つ置けば、どのパッケージのディレクトリから実行しても同じ版になる。

### 2. `haxe_libraries/<名前>.hxml`：ライブラリごとの「lockfile兼設定」

ライブラリ1つにつき1ファイル。vshaxeの`hxnodejs.hxml`は次のようになっている（抜粋）。

```
# @install: lix --silent download "gh://github.com/HaxeFoundation/hxnodejs#ba7d9a5..." into hxnodejs/12.2.0/github/ba7d9a5...
-cp ${HAXE_LIBCACHE}/hxnodejs/12.2.0/github/ba7d9a5.../src
-D hxnodejs=12.2.0
```

- 1行目（`# @install:`）: どこから、どの版を取ってくるか。lockfileに相当する。haxelibの版のほか、GitHubのコミットも指定できる
- `-cp`: 取ってきたソースの場所をクラスパスに追加する（実体はマシン共通のキャッシュ`~/haxe/haxe_libraries/`にあり、版ごとに別ディレクトリなので衝突しない）
- `-D`: ライブラリの版をコンパイル時の定義として渡す

ビルド定義（`.hxml`）に`-lib hxnodejs`と書くと、Haxeはこのファイルを読み込む。つまり`-lib`は「`haxe_libraries/hxnodejs.hxml`の中身をここに展開する」という意味になる。

### 3. 主なコマンド

| コマンド | 意味 | npmでいうと |
|---|---|---|
| `lix scope create` | `.haxerc`を作る | `npm init` |
| `lix install haxe 4.3.7` / `lix use haxe 4.3.7` | Haxeを取ってくる／`.haxerc`の版を切り替える | `.nvmrc`を書く |
| `lix install haxelib:utest` | ライブラリを追加し、`haxe_libraries/utest.hxml`を作る | `npm install utest` |
| `lix install gh:owner/repo` | GitHubから追加する | `npm install github:owner/repo` |
| `lix download` | `haxe_libraries/`に書かれたものを全部取ってくる | `npm ci` |

## 具体例：rawpdfでの置き方

```
rawpdf/
├── package.json        … devDependenciesにlix（npm workspacesのルート）
├── .haxerc             … Haxe 4.3.7
├── haxe_libraries/
│   ├── utest.hxml
│   └── hxnodejs.hxml
└── packages/pdf-cst-parser/
    └── test.hxml       … -cp src / -cp tests / -lib utest / -main ... / -js ...
```

- lixはnpmパッケージなので、ルートの`package.json`のdevDependenciesに入れる。`npm install`のあと`npx lix download`（またはscriptに登録）でHaxeとライブラリがそろう
- 自分たちのパッケージ（parser・semantics）は外部ライブラリではないので、lixでは扱わない。`.hxml`の`-cp`で直接`src/`を指す。これが依存方向の強制にもなる（統括3章）
- `.haxerc`と`haxe_libraries/`はコミットする。キャッシュ（`~/haxe/`）はリポジトリの外にあるので、`.gitignore`は要らない

## このプロジェクトでの使われ方

- 統括設計3章のツールチェーン（「Haxe 4.3.7（lixで固定）」）
- WBSのM0-1（lixとパーサパッケージの雛形）・M0-2（CIでのinstall）
- npm経由でlixのシムが正しく動くか（`npx haxe`で`.haxerc`の版が使われるか）は、M0-1で最初に確かめる

## 参考

- lix: https://github.com/lix-pm/lix.client （2026-10に更新あり。保守されている）
- vshaxe（`.haxerc`と`haxe_libraries/`の実例）: https://github.com/vshaxe/vshaxe

## 関連ノート

- [VS Code拡張の実行環境](vscode-extension-runtime.md)
