# Taskfileと終了コード

テストの成否は「プロセスの終了コード（0＝成功、0以外＝失敗）」で上へ伝わる。Task（go-task）は、コマンドが0以外で終わった時点でそのタスクを打ち切り、自分も失敗として終わる。

## なぜ必要か

CIやシェルは、テストの出力を読まずに終了コードだけで成否を判断する。どこか1段で終了コードが握りつぶされると、テストが落ちてもCIは緑のままになる。

## どういう仕組みか

終了コードは次の鎖で伝わる。

```
utest → (node | haxe --interp) → npm exec → Task → シェル / CI
```

1. **utest**: `UTest.run`の既定レポート（`PlainTextReport.complete`）が、全部通れば`exit(0)`、1つでも落ちれば`exit(1)`を呼ぶ。JSでは`process.exit`、evalでは`Sys.exit`。
2. **node / `haxe --interp` / `npm exec`**: 子の終了コードをそのまま返す。コンパイルエラーも0以外になる。
3. **Task**:
   - `cmds`は上から順に実行し、**0以外が出たらそこで止まる**。後続のコマンドは実行されない。
   - `- task: 別タスク`の呼び出しも同じ。呼んだ先が失敗すれば呼び出し元も止まる。
   - `deps`は並列実行。どれかが失敗すればタスクは失敗。
   - `task`自身の終了コードは、既定では**Task独自のコード**（タスク実行失敗は`201`）。失敗したコマンドの終了コードそのものを返させたいときは`task -x`（`--exit-code`）。
   - 失敗しても続けたいコマンドには`ignore_error: true`を付ける。ただしその失敗は**全体の終了コードに反映されなくなる**。

## 具体例

```yaml
test-all:
  cmds:
    - task: test-node    # ここで落ちると…
    - task: test-interp  # …ここは実行されない
```

- 「最初の失敗で止める」なら上のままでよい（`set -e`と同じ考え方）。
- 「両方の結果を見たいが、全体は失敗にしたい」なら`ignore_error`では足りない（成功扱いになる）。`deps`で並列にする、または両方実行してから失敗を集計するシェル1行にする、などの工夫が要る。

確認方法: `task test-all; echo $?` で0かどうかを見る。わざと落ちるテストを1つ入れて試すと確実。

## このプロジェクトでの使われ方

ルートの`Taskfile.yml`の`test-run-cst-*`。テストはNodeターゲットが正、evalでも回せるようにする（CLAUDE.md「技術スタック」）。PRのCIはこの終了コードで成否を判断する。

## 参考

- Task公式: Exit codes（taskfile.dev/reference/cli の exit codes 節）、`ignore_error`
- utest: `src/utest/ui/text/PlainTextReport.hx` の `complete`

関連: [lix](lix.md)
