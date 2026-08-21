# Issue #1427: auto: concurrent_commit_detected が自セッションの issue 番号なし中間 commit を誤検知する (#895 再発)

## Overview

`scripts/run-auto-sub.sh` の `run_phase_with_recovery()` にある `concurrent_commit_detected` 自己除外ロジック (`_self_issue_pattern="#${issue}([^0-9]|$)"`, L725-736) は、commit subject に `#<issue番号>` が含まれる場合のみ自セッションの commit と判定する。`/code` patch route の Step 8 が作る中間 (WIP) commit は issue 番号を含まない書式が許容されているため、同一フェーズ自身が作った中間 commit が `concurrent_commit_detected` として誤検知される。検出ロジックを、commit subject に「別の issue 番号」が明示的に含まれるかどうかで判定する 3-way 分類に変更し、issue 番号が一切含まれない commit は自セッションの中間 commit と推定して除外する。

## Reproduction Steps

1. `/auto --batch` セッション `91663-1787272961` (2026-08-21) が Issue #1245 (code-patch route) を処理。
2. `/code` の Step 8 (「commit after each step completes」) が中間 commit を2件作成:
   - `3d54461a` `Fix bare bracket assertion in new precondition test`
   - `1b272de5` `Add code-pr precondition test: Spec missing but Size XS`
   いずれも subject に `#1245` を含まない (最終 commit のみ issue 番号を含む形だった)。
3. `run_phase_with_recovery()` がフェーズ終了後に `git log origin/main --since="@${PHASE_START}"` で新規 commit を走査し、上記2件の subject が `_self_issue_pattern="#1245([^0-9]|$)"` にマッチしないため、`concurrent_commit_detected` イベントとして誤って emit した。
4. L3 session retrospective (`docs/sessions/91663-1787272961-2026-08-21/session.md`) の Concurrent Sessions Detected セクションに両 SHA が記録されたが、`git log` で直接確認した結果、実際には他セッションの並行稼働は存在しなかった。

## Root Cause

`_self_issue_pattern` による自己除外は「このフェーズが作る commit の subject には必ず `#<issue番号>` が入る」という前提に立っている。しかし `skills/code/SKILL.md` の commit 規約はこの前提を満たしていない:

- **Step 11 (最終 commit)**: `(closes #$NUMBER)` を commit テンプレート本体に直接埋め込み、`BASE_BRANCH == main` の場合は `git log -1 --format='%s' | grep -q "#$NUMBER"` で機械的に assert している (Issue #996 で導入)。
- **Step 8 (中間 commit)**: 「Commit after each step completes」とあるのみで、subject に issue 番号を含める規約もガードも存在しない。実際の中間 commit ("Fix bare bracket assertion in new precondition test" 等) は issue 番号を含まない自由記述。

#996 は「patch route の実装コミットのうち LLM が自由記述するのは Step 11 の `<summary>` のみ」という前提で Option A (commit 規約側の強化) を Step 11 にのみ適用したが、Step 8 の中間 commit も同じく自由記述であり、この前提が不完全だった。本 Issue はその見落とされた経路 (Step 8) が誤検知の原因になっているケース。

## Changed Files

- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` の `concurrent_commit_detected` ブロック (L725-736 付近) の per-commit 判定を 2-way (self-pattern match / それ以外は全て concurrent) から 3-way (self-pattern match → self; 別 issue 番号の明示参照 → concurrent; issue 番号の参照が一切ない → self と推定) に変更 — bash 3.2+ 互換 (`[[ ]]` の拡張正規表現のみ使用、既存の `_self_issue_pattern` と同じ記法)
- `tests/run-auto-sub.bats`: issue 番号なし中間 commit が誤検知されないことを確認する回帰テストを追加し、既存の `"concurrent_commit_detected: emit_event called when git log returns commits"` テストの `git log -1` mock (`abc1234`) を明示的な別 issue 番号を含む subject に更新 (新しい 3-way 分類のもとでも true-positive として意味を持つテストであり続けるようにするため)

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` 内、`concurrent_commit_detected` ブロックの per-commit 判定 (現状: `if [[ "$_subject" =~ $_self_issue_pattern ]]; then continue; fi` のみで、マッチしなければ即 emit) を、次の 3-way 分岐に置き換える (→ acceptance criteria AC1):
   - (a) `$_subject` が `$_self_issue_pattern` にマッチ → 自セッションの commit (`continue`, 既存動作を維持)
   - (b) (a) が不一致かつ、`$_subject` が汎用パターン `#[0-9]+([^0-9]|$)` (何らかの issue 番号への参照) にマッチ → 別 issue の commit である明示的な証拠があるため、真の concurrent commit として `emit_event "concurrent_commit_detected" ...` を実行 (既存動作を維持)
   - (c) (a)・(b) いずれにも不一致 (issue 番号への参照が commit subject に一切ない) → 同一フェーズ自身が作った中間 commit と推定し `continue` (emit しない) — これが本 Issue の修正対象
   `_self_issue_pattern` の生成ロジック (review/merge phase 向けの `_EXTRA_SELF_ISSUE` 対応を含む) は変更しない。
2. (after 1) `tests/run-auto-sub.bats` に新規 `@test` を追加する (→ acceptance criteria AC2): 既存の `"concurrent_commit_detected: self-issue-only commit is not emitted"` と同型の git mock を使い、origin/main 上の1コミットの `git log -1` 出力を issue 番号を一切含まない subject (例: `"Fix bare bracket assertion in new precondition test"`) にし、`concurrent_commit_detected` が emit されないことを assert する。テスト名に `issue #1427` を含める。
3. (after 1) `tests/run-auto-sub.bats` の既存テスト `"concurrent_commit_detected: emit_event called when git log returns commits"` の `git log -1` mock を更新する (→ acceptance criteria AC2): 現状 `abc1234` に対する `git log -1` mock が存在せず subject が空文字になり、ステップ1の (c) に該当して新しい分類のもとでは emit されなくなる (テストの `skip` フォールバックが常時発火し、true-positive の検証として機能しなくなる)。`abc1234` の `git log -1` mock を追加し、明示的な別 issue 番号を含む subject (例: `"chore: fix (closes #99)"`) を返すようにして、3-way 分類の (b) 経路を通る true-positive テストとして意味を保たせる。
4. (after 1, 2, 3) `bats tests/run-auto-sub.bats` を実行し、新規・更新した2テストを含む全テストが PASS することを確認する。既存の `"concurrent_commit_detected: other-issue commit is emitted while self-issue commit is excluded"` および `"an unrelated commit is still detected during review/merge phase"` (いずれも明示的な別 issue 番号を使用) が後退なく PASS することを確認する。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の concurrent_commit_detected 検出ロジックが、commit subject の issue 番号マッチのみに依存せず、同一フェーズ自身が作成した issue 番号なし中間 commit を誤検知しないように修正されている" --> scripts/run-auto-sub.sh の self-commit 除外ロジックが、issue 番号を含まない中間 commit も自セッションの commit として正しく除外するように修正されている
- <!-- verify: rubric "issue 番号を含まない中間 commit が concurrent_commit_detected の誤検知対象にならないことを検証する bats テストが追加されており、既存の他 issue commit 検出テストが引き続き PASS する" --> tests/run-auto-sub.bats に回帰テストが追加されており、既存の他 issue commit 検出テスト (true-positive 系) が後退なく通過する

### Post-merge

- 次回 `/auto --batch` または `/auto N` の code-patch route 実行で、同一フェーズが複数 commit を作成した場合に `concurrent_commit_detected` が誤検知されないことを観察 <!-- verify-type: observation event=auto-run -->
  - 期待される出力構造:
    - 該当実行の `.tmp/auto-events.jsonl` (または生成された場合は L3 session retrospective) に、当該フェーズの中間 commit に起因する `concurrent_commit_detected` イベントが記録されていないこと
    - 真の並行 commit (別セッションによる他 issue の commit) が存在した場合は、引き続き `concurrent_commit_detected` イベントとして正しく検出されること

## Consumed Comments

| login | authorAssociation | trust tier | 内容要約 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/issue` フェーズの Issue Retrospective コメント (triage 結果: Type=Bug, Size=S, Value=3, Theme=concurrency の判定根拠、および Ambiguity 自動解決ログ・AC の Pre-merge/Post-merge 構造修正の記録)。内容は既に現在の Issue body に反映済みであり、本 Spec 作成にあたって追加のアクションは不要と判断。 | https://github.com/saitoco/wholework/issues/1427#issuecomment-5371380417 |

## Notes

### Option A (本 Issue で採用) vs Option B (SHA 追跡) の再検討 — 先例 #996 との関係

`_self_issue_pattern` による message-content 依存の自己除外は #895 (導入) → #974 (`_EXTRA_SELF_ISSUE` で review/merge に拡張) → #996 (Step 11 最終 commit の `#N` 欠落を規約側で修正) と3回パッチされてきた。#996 の Notes は「message ベース検出が3度目の再発を超えて構造的限界に達した場合、SHA 追跡ベースの Option B (`worktree-merge-push.sh` が push した commit SHA をフェーズ・issue スコープの一時ファイルに記録し、`run-auto-sub.sh` がそれを読んで自己判定に使う) を検討する」という setpoint を明示的に残していた。本 Issue (#1427) はこの数え方では4回目のパッチだが、内容を精査すると **#996 が想定した「構造的限界」には未到達** と判断した:

- #996 は「patch route で LLM が自由記述する commit subject は Step 11 の `<summary>` のみ」と分析したが、これは不正確だった — Step 8 の中間 commit も同じく自由記述であり、#996 のスコープから漏れていた。本 Issue はその見落とされた経路を埋める修正であり、message ベース判定そのものが原理的に破綻したケースではない。
- 本 Issue で採用する 3-way 分類 (「issue 番号への参照が一切ない commit は自セッションと推定する」) は、Step 8 と Step 11 の両方、および将来 `/code` や他スキルに追加されうる自由記述 commit 全般に汎用的に適用できるルールであり、#895/#974/#996 のような「特定の commit 生成箇所を1つずつ塞ぐ」パッチとは性質が異なる。同種の false-positive が今後 別の commit 生成箇所で発生しても、本ルールなら自動的にカバーされる可能性が高い。
- Option B (SHA 追跡) は `scripts/worktree-merge-push.sh` 側での push 済み SHA 記録・`--batch` 並行実行を考慮した一時ファイルの命名衝突回避・読み取り後のクリーンアップ設計が必要であり、#996 の見積もり通り複数ファイルにまたがる新しい状態受け渡し機構の新設を要する。Size S / light spec (実装ステップ上限5) のスコープを超えるため、今回も見送る。
- 残存する限界 (許容): 本ルールは「issue 番号を含まない commit を、真に別セッションが同時に作った場合」との判別ができない (どちらも「参照なし」に分類され self 扱いになる)。ただし同一マシン上の同一 git identity による並行 `--batch` 実行では、そもそも author 名でも判別できない (#996 の Option B 不採用理由と同じ制約)。この残存限界は、今後 message ベース判定が真に構造的限界に達したと判断される材料が蓄積した場合に、Option B 再検討のトリガーとして引き続き有効とする。

### Steering Docs sync candidate 判定

`modules/doc-checker.md` の手順に従い、変更対象 `scripts/run-auto-sub.sh` から抽出したキーワード `run-auto-sub.sh` で `docs/ tests/ scripts/ modules/` を grep したところ 278 ファイルがヒットし、識別力フィルタ (8ファイル超過) によりスキップした。他に高優先度キーワード (新規 config key・marker・function 名) は本変更で導入していないため、Steering Docs sync candidate は無し。`README.md`/`docs/workflow.md`/`CLAUDE.md` に `concurrent_commit_detected`/`_self_issue_pattern`/self-commit の記述がないことも grep で確認済み (ドキュメント更新不要)。

### Fail-safe critical script判定

`concurrent_commit_detected` ブロックはテレメトリ (イベント emit) のみを行い、マージ可否やフェーズ続行可否を左右するゲート・バリデータではない。`skills/spec/SKILL.md` の Fail-safe critical 判定基準 (a)(b)(c) のいずれにも該当しないため、edge case (空文字・特殊文字等) の詳細な期待動作記述は不要と判断した。

### 観測型 AC の 2-part 構造化

Issue body の Post-merge AC (`verify-type: observation event=auto-run`) が「期待される出力構造」のサブ箇条書きを欠いていたため、`modules/verify-classifier.md` の Option A 形式で補記し、Issue body 側も `gh-issue-edit.sh` で同期した (要求内容自体の変更ではなく、既存の記述を構造化しただけ)。
