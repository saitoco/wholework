# Issue #1476: verify-patterns: worktree isolation guard に拒否される形の verify command を AC 作成時に避ける指針を追加する

## Issue Retrospective

### 自動解決した曖昧点 (Auto-Resolve Log)

- **AC 3 の rubric を「確認した記録が当該 module 内の記述として残っている」に限定した** — 理由: 元の文言は「確認した記録があるか」で、記録の置き場所が未指定だった。rubric の grader は `git diff` と Issue 本文しか見ず (`modules/verify-executor.md` § Rubric Command Semantics)、Spec や Issue コメントは見られない。記録が Spec の Notes にだけ残ると、実装が正しくても UNCERTAIN になる。rubric 文中で名指しされた 2 つの module に記録を置く形にすれば、grader が証拠に届く。
  - 他の候補: rubric 文中に Spec の節を名指しする (AC は実装コードの検証であり、Spec 名指しの例外は diff-less な調査 AC 向けなので不採用) / 元の文言のまま残す (UNCERTAIN の恐れがあり不採用)

### AC 変更

- AC 3 の rubric 文言のみ変更 (上記)。AC 1・2 は変更なし。

### 確認結果

- 常時 PASS / 常時 FAIL の空撃ち: AC 1 の `grep "isolation guard"` は main で 0 件、AC 2 の `file_not_contains` は対象文字列が main に 1 件あり、どちらも実装前は FAIL になる。AC 3 の rubric も、現状では該当する記録も置換もないため PASS しない。
- AC 形式チェック (`check-ac-checkbox-format.sh`) と observation の `session=next` チェックは問題なし。
- Background の事実主張 (`test-runner.md` と `verify-executor.md` の矛盾、`verify-patterns.md` §7・§24 と `verify-executor.md` の `$(gh run list ...)` 例、`worktree-lifecycle.md` の wrapper script pattern) はコードベースで確認できた。
- `verify-patterns.md` には gh 以外の `command "test $(grep ...)"` 形の `$(...)` 例 (§1・§26・§31) もあり、AC 3 の「など」に含まれる。`/spec` では、これらも拒否されるかを確認対象に入れること。

### Consumed Comments

No new comments since last phase.
