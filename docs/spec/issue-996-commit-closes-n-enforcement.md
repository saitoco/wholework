# Issue #996: auto: Issue 番号を含まない自コミットの concurrent_commit 誤検出を解消

## Overview

`scripts/run-auto-sub.sh` の `concurrent_commit_detected` 自己除外ロジック (`_self_issue_pattern="#${issue}([^0-9]|$)"`) は、commit subject 行に処理中 Issue 番号 (`#N`) が含まれることを前提に自 Issue の commit を除外している。しかし `/code` patch route の Step 11 commit テンプレートは、`(closes #$NUMBER)` を「BASE_BRANCH が main のときのみ付与するコメント上の指示」として示すのみで、実際にコピーされる `git commit -s -m` ブロック本体には `<summary>` しか現れない。この comment-vs-code の分離が、実装コミット本体から `(closes #$NUMBER)` を省略する余地を生み、Issue #979 で実際に省略が発生した (Issue 番号を含まない実装コミット `032ff82c` が `concurrent_commit_detected` として誤検出された)。

本 Issue では Option A (commit 規約側の強化) を採用する。詳細な比較検討は `## Notes` を参照。

## Changed Files

- `skills/code/SKILL.md`: Step 11 (`Commit, Push, or Create PR`) の patch route commit ブロックを変更 — `(closes #$NUMBER)` を `git commit -s -m` テンプレート本体に直接埋め込み、既存の DCO sign-off チェックと同じ形式で commit subject の `#$NUMBER` 存在を機械的に assert するガードを追加する (bash 3.2+ 互換: `[[ ]]` と `grep -q` のみ使用)
- `tests/code.bats`: 既存の `step0_section()` ヘルパーに倣った `step11_section()` を追加し、Step 11 セクションが (a) `(closes #$NUMBER)` を commit テンプレート本体に含むこと、(b) commit subject の `#$NUMBER` 存在ガードを含むことを検証する `@test` を2件追加する

## Implementation Steps

1. `skills/code/SKILL.md` Step 11 の patch route commit ブロック (485行目付近、"For patch route (commit to BASE_BRANCH)" 以下) を以下のように変更する (→ acceptance criteria AC2):

   変更前:
   ```bash
   git add <changed files>
   # If BASE_BRANCH is main: "{prefix} <summary> (closes #$NUMBER)"
   # If BASE_BRANCH is not main: "{prefix} <summary>"
   git commit -s -m "{prefix} <summary>

   Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
   ```
   ```bash
   git log -1 --format='%B' | grep -q "^Signed-off-by:" || { echo "ERROR: missing sign-off"; exit 1; }
   ```

   変更後:
   ```bash
   git add <changed files>
   # When BASE_BRANCH is main:
   git commit -s -m "{prefix} <summary> (closes #$NUMBER)

   Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
   # When BASE_BRANCH is not main, omit the "(closes #$NUMBER)" suffix instead:
   # git commit -s -m "{prefix} <summary>
   #
   # Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
   ```
   ```bash
   git log -1 --format='%B' | grep -q "^Signed-off-by:" || { echo "ERROR: missing sign-off"; exit 1; }
   if [[ "$BASE_BRANCH" == "main" ]]; then
     git log -1 --format='%s' | grep -q "#$NUMBER" || { echo "ERROR: commit subject missing #$NUMBER reference (required when BASE_BRANCH is main)"; exit 1; }
   fi
   ```

   直前の一文 (「Include `closes #N` only when the base branch is `main`」段落) に、省略してはならない旨と Issue #996 の背景を一文で補記する。

2. (after 1) `skills/code/SKILL.md` Step 12 (Code Retrospective commit, 662行目 `"Add code retrospective for issue #$NUMBER"`) は既に固定テンプレートに `#$NUMBER` を含むため変更不要であることを確認する (変更なし、確認のみ)。

3. (after 1) `tests/code.bats` に以下を追加する (→ acceptance criteria AC3):

   ```bash
   # Extract Step 11 section: from "### Step 11:" to the next "### " heading
   step11_section() {
       awk '/^### Step 11:/{found=1} found && /^### / && !/^### Step 11:/{exit} found{print}' "$1"
   }

   @test "Step 11 patch route commit template includes closes NUMBER inline" {
       run step11_section "$SKILL_FILE"
       [[ "$output" == *'(closes #$NUMBER)'* ]]
   }

   @test "Step 11 patch route includes commit subject issue-number guard" {
       run step11_section "$SKILL_FILE"
       [[ "$output" == *'missing #$NUMBER reference'* ]]
   }
   ```

   両 `@test` とも `*'...'* ` の単一引用符区間で `$NUMBER` の bash 展開を防ぐこと (二重引用符のみで書くと `$NUMBER` が空文字に展開され、意図しない緩い一致になる)。

## Verification

### Pre-merge

- <!-- verify: rubric "docs/spec/ の対応 Spec が Option A (commit 規約側) と Option B (検出ロジック側) を比較検討し、採用方針と理由を記録している" --> 対処方針の比較検討結果が Spec に記録されている
- <!-- verify: rubric "採用方針に基づき、Issue 番号を含まない自 Issue コミットが concurrent_commit_detected として誤検出されない実装または規約変更が行われている (skills/code/SKILL.md の commit 規約変更、または scripts/run-auto-sub.sh の自己除外ロジック拡張のいずれか)" --> 誤検出を防ぐ実装/規約変更が行われている
- <!-- verify: rubric "tests/ 配下に、Issue 番号を含まない自 Issue コミットが誤検出されないこと (採用方針に応じた検証方法) を確認するテストまたは規約準拠チェックが追加されている" --> regression テストまたは規約準拠チェックが追加されている

### Post-merge

- 次回 `/auto --batch` の patch route 実行で `concurrent_commit_detected` の自己検出 false-positive が 0 件であることを観察 <!-- verify-type: observation event=auto-run -->

## Consumed Comments

No new comments since last phase.

## Notes

### Option A vs Option B 比較検討 (AC1 対応)

**Option A (採用): commit 規約側 — `/code` patch route の commit テンプレートを強化**

- 内容: `skills/code/SKILL.md` Step 11 の patch route commit ブロックで `(closes #$NUMBER)` を `git commit -s -m` 本体に直接埋め込み、既存の DCO sign-off チェック (`grep -q "^Signed-off-by:"`) と同型の機械的ガード (`grep -q "#$NUMBER"`) を追加する。
- 根拠:
  1. **既に規約は存在していた**: Step 11 は元々 "Include `closes #N` only when the base branch is `main`" と明記しており、#979 のケースは規約の欠如ではなく、テンプレートの comment (指示) と実際の `git commit -s -m` ブロック (LLM がコピーする実体) が分離していたことによる実装時の見落としだった (Code Retrospective 自身が「Deviations from Design」として記録している)。Option A はこの分離を解消し、既存の sign-off チェックと同じ「機械的 assert で hard-fail させる」パターンを流用するだけで済む、最小の変更で根本原因に直接対処できる。
  2. **影響範囲が正確にスコープと一致する**: 誤検出が実際に発生したのは patch route の実装コミット (Step 11 の `<summary>` は LLM が自由記述する唯一の箇所) のみ。Step 12 の retrospective commit (`"Add code retrospective for issue #$NUMBER"`) は固定テンプレートで既に `#$NUMBER` を含み、pr route の実装コミット (feature branch へ push、`origin/main` を対象にした `concurrent_commit_detected` の検出対象にそもそも入らない) や review/merge phase (PR タイトル `Issue #N: ...` 由来で `#N` を常に含む固定書式、および `merge` skill の `Add merge phase handoff for issue #$NUMBER` 固定テンプレート) も同様に自由記述の隙がない。したがって Option A は「Step 11 の1箇所」を直すだけで、報告された false-positive のクラスを過不足なくカバーする。
  3. **テスト容易性**: `tests/code.bats` に既に `skills/code/SKILL.md` の特定セクションを awk 抽出して文言を assert する前例 (`step0_section()` + `@test "Step 0 section contains ..."`) があり、同型の `step11_section()` を追加するだけで AC3 の regression test を実現できる。

**Option B (不採用): 検出ロジック側 — `run-auto-sub.sh` の自己除外を commit message 非依存にする**

- 内容: commit subject の `#N` 一致に頼らず、phase 実行中に作成された commit を SHA レベルで識別する (例: `worktree-merge-push.sh` が push した commit SHA 一覧を per-phase の一時ファイルに記録し、`run-auto-sub.sh` がそれを読んで自己判定に使う)。
- 不採用の理由:
  1. **同根クラスの再発パターン**: #895 (自己除外ロジックの導入、message ベース) → #974 (`_EXTRA_SELF_ISSUE` で review/merge phase に拡張、同じく message ベース) → 本 Issue、と同じ「message-content 依存の検出ロジックを都度パッチする」アプローチを3回目も繰り返すことになり、将来 `#N` を含まない commit を生成する新しい呼び出し箇所が増えるたびに同種の false-positive が再発するリスクが構造的に残る。
  2. **実装コストが Size S に見合わない**: commit SHA を親プロセス (`run-auto-sub.sh`) に確実に伝搬するには、`worktree-merge-push.sh` (patch route) 側での SHA 記録・一時ファイルの命名衝突回避 (`--batch` 並行実行を考慮)・読み取り後のクリーンアップ設計が必要になり、`scripts/run-auto-sub.sh` と `scripts/worktree-merge-push.sh` の複数ファイルにまたがる新しい状態受け渡し機構の新設が要る。light spec (Size S、実装ステップ上限5) の枠を超え、triage 時点の Size 判定とも整合しない。
  3. **Issue 本文の Option B 案自体が示唆する複雑さ**: Issue 本文の Option B 案 ("push 元 branch や committer 情報等で識別する") は具体的な識別手段を明示しておらず、author/timestamp だけでは同一マシン上で並行実行される他 Issue の phase と区別がつかない (`--batch` 実行では同一 git identity が複数 Issue の commit を作る) ため、実際には SHA 追跡以上の設計が必要になる。

**結論**: Option A を採用。Option B が示す「message 非依存化」という方向性自体は将来 message ベース検出が3度目の再発を超えて構造的限界に達した場合の setpoint として `## Related Issues` の同根クラス (#895 → #974 → 本 Issue) に追記する価値はあるが、本 Issue のスコープでは Size S に見合う Option A で十分に根本原因を解消できる。

### 適用範囲の確認

- ガードは `BASE_BRANCH == main` の場合のみ発動する。`BASE_BRANCH` が main 以外 (release branch 等) の patch route では、`concurrent_commit_detected` の検出自体が `git log origin/main --since=...` で `origin/main` のみを対象にしているため、release branch 上の commit はそもそも検出対象に入らず false-positive リスクが存在しない。ガード範囲を `closes #N` の既存条件 (BASE_BRANCH=main) と一致させることで、規約と検出ロジックの前提が揃う。

### Steering Docs sync candidate 判定

- `skills/code/SKILL.md` 変更に伴い `modules/doc-checker.md` の手順でキーワード `code` を `docs/*.md docs/ja/*.md` に grep したところ 17ファイルがヒットしたが、いずれも "code" という一般的な部分文字列への一致であり、本変更が触れる Step 11 の commit message 書式という粒度の詳細を記述している箇所はない。`docs/workflow.md` の `closes #N` 関連記述 (「Standard Flow via `closes #N`」節など) は PR route の PR body に対するものであり、本変更が対象とする patch route の commit subject 書式とは別の記述対象のため、sync candidate には含めない。`modules/skill-dev-doc-impact.md` の Change Type 表も確認したが、「Skill addition, change, or deletion」は README.md/docs/workflow.md の skill 一覧・phase 説明レベルの変更を指し、本変更のような skill 内部の commit テンプレート強化はこれに該当しないと判断した。

## Related Issues

- 同根クラス: #895 (code-patch 自己除外の導入)、#974 (merge/review フェーズへの適用)、本 Issue (#996、commit 規約側での解消)
- 検出元 Issue: #979 (get-config-value パース修正 — 誤検出の発生現場)
- 参考: #668 (icebox — 並行 commit と Issue 結果の相関分類)
