# Issue #977: run-auto-sub: resume 時の spec phase 再ディスパッチを防止

## Overview

`scripts/run-auto-sub.sh` の spec phase gate は `phase/ready` ラベルの不在のみを再実行条件としており、Issue が spec 完了以降のどの phase (`phase/code` 等) にあっても `run-spec.sh` を再ディスパッチしてしまう。`/auto --batch --resume` など resume 経路でこの問題が発生し、Issue #963 では `/spec` セッション自身が状態を調査して exit 0 で辞退したため実害はなかったが、冗長なセッション消費とラベル巻き戻し/コメント重複投稿のリスクが残っていた。本 Spec では gate 判定を拡張し、spec 完了以降を示すラベルが存在する場合は `run-spec.sh` をディスパッチせず skip し、理由をログ出力するよう修正する。

## Reproduction Steps

1. Issue が spec 完了済み (`phase/code` ラベル付与済み、`phase/ready` は `/code` 開始時に既に除去済み) の状態で `run-auto-sub.sh <issue-number>` を実行する。
2. `scripts/run-auto-sub.sh` の spec phase gate (602行目付近、`# spec phase: run only if phase/ready label is not present` コメント直下) は `if ! echo "$LABELS" | grep -q "phase/ready"; then` のみを条件としている。`phase/code` が付与されていても `phase/ready` は不在なので条件が真になり、`run-spec.sh "$SUB_NUMBER"` が再度呼ばれる。
3. Issue #963 ではこの再ディスパッチにより `/spec` セッションが約4分+トークンを消費した後、セッション自身が「既に spec 完了済み」と判断して exit 0 で辞退した。辞退判断は LLM の防御的挙動に依存しており、ラベル巻き戻し (`phase/code` → `phase/spec`) や `## Design Complete` コメント重複投稿が起きるリスクが構造的に残っている。

## Root Cause

`scripts/run-auto-sub.sh` の spec phase gate (602-613行目) は `phase/ready` ラベルの不在のみを再実行条件としている。`docs/workflow.md` の phase label 遷移表によれば、`phase/ready` は `/spec` 完了後にのみ付与され `/code` 開始時に除去される。以後 `phase/code` → `phase/review` → `phase/merge` → `phase/verify` → `phase/done` のいずれの状態でも `phase/ready` は復元されない (`/auto` 親セッションの fix-cycle 検出 (`skills/auto/SKILL.md` Step 2a) が `phase/verify` → `phase/ready` へ明示的にリセットする経路を除くが、これは親セッション側 (`/auto` 単体 Issue パス) のロジックであり、`run-auto-sub.sh` 自身が呼ばれる resume/batch/XL sub-issue パスでは適用されない)。したがって `phase/ready` の不在だけを条件にすると、spec 完了以降のどの状態でも gate が「spec 未着手」と誤判定し、`run-spec.sh` を再ディスパッチしてしまう。

Issue 本文の Acceptance Criteria 1 (rubric) は `phase/code`/`phase/review`/`phase/verify` の3ラベルを例示するが、Acceptance Criteria 2 の文言「`phase/code` 以降のラベルで spec が実行されないこと」は spec 完了以降の全状態を指すと解釈できる。上記の phase label 遷移表が示す通り、同じ根本原因は `phase/merge`/`phase/done` にも及ぶため、本 Spec では実装・テストの両方でこの2ラベルを含む5ラベル全て (`phase/code`/`phase/review`/`phase/merge`/`phase/verify`/`phase/done`) を skip 条件に含める (詳細な判断根拠は Notes 参照)。

## Changed Files

- `scripts/run-auto-sub.sh`: spec phase gate (602-613行目付近、`# spec phase: run only if phase/ready label is not present` コメント直下) を拡張し、`phase/code`/`phase/review`/`phase/merge`/`phase/verify`/`phase/done` のいずれかのラベルが存在する場合は `run-spec.sh` をディスパッチせず skip し、skip 理由をログ出力する — bash 3.2+ compatible (既存で使用済みの `grep -E` 拡張正規表現のみ使用、連想配列・`mapfile` 等の bash 4+ 専用機能は導入しない)
- `tests/run-auto-sub.bats`: spec phase skip 分岐の positive テスト5件 (`phase/code`・`phase/review`・`phase/merge`・`phase/verify`・`phase/done` をそれぞれ単独付与した場合に `run-spec.sh` が呼ばれないこと) を追加。既存の "phase/ready present" (293行目) および "phase/ready absent" (300行目) の2テストは負のケース (spec 完了前は通常通りディスパッチされ、skip されないこと) の回帰網羅として現状のまま維持する
- `docs/migration-notes.md`: [Steering Docs sync candidate] `run-auto-sub.sh` への言及 (48-52行目: verify phase 除去の記録、554・558行目: usage メッセージ英語化の記録) を確認済み — いずれも spec phase gate の条件には触れていないため変更不要と判断 (grep 済み)
- `docs/structure.md`: [Steering Docs sync candidate] `run-auto-sub.sh` への言及 (207行目: retry-on-kill.sh 対象列挙、218行目: spawn-recovery-subagent.sh 呼び出し元、223行目: スクリプト一覧の一行説明) を確認済み — いずれも spec phase gate の条件には触れていないため変更不要と判断 (grep 済み)
- `docs/tech.md`: [Steering Docs sync candidate] `run-auto-sub.sh` への言及 (55行目: two-tier orchestration・tiered adaptive recovery の説明) を確認済み — spec phase gate の条件には触れていないため変更不要と判断 (grep 済み)
- `docs/workflow.md`: [Steering Docs sync candidate] `run-auto-sub.sh` への言及 (111行目: `--batch` の verify orchestration 説明、113行目: `--resume` の code phase resume probing 説明) を確認済み — spec phase gate の条件には触れていないため変更不要と判断 (grep 済み)
- `docs/ja/migration-notes.md` / `docs/ja/structure.md` / `docs/ja/tech.md` / `docs/ja/workflow.md`: [Steering Docs sync candidate] 上記4ファイルの日本語ミラー。英語版が変更不要なら `docs/translation-workflow.md` の同期規則により追従不要

## Implementation Steps

1. `scripts/run-auto-sub.sh` の spec phase gate (602-613行目付近) を以下の形に書き換える (→ Acceptance Criteria 1):
   ```bash
   # spec phase: run only if phase/ready is absent AND the issue hasn't already progressed
   # past spec. "spec 完了以降" (spec-complete-or-later) covers phase/code, phase/review,
   # phase/merge, phase/verify, and phase/done — phase/ready is removed once /code starts
   # and is not restored on this path, so without this check every one of those states
   # would redundantly re-dispatch run-spec.sh on a resumed run (issue #977).
   LABELS=$(gh issue view "$SUB_NUMBER" --json labels -q '.labels[].name' 2>/dev/null || true)
   if echo "$LABELS" | grep -qE "phase/(code|review|merge|verify|done)"; then
     echo "${LOG_PREFIX} spec phase: skipping dispatch for issue #${SUB_NUMBER} (phase/code, phase/review, phase/merge, phase/verify, or phase/done label present; spec already completed)"
   elif ! echo "$LABELS" | grep -q "phase/ready"; then
     echo "${LOG_PREFIX} --- spec phase: issue #${SUB_NUMBER} ---"
     # Bash-side comments_consumed emit for spec phase. (Issue #705)
     _emit_comments_consumed "$SUB_NUMBER" "spec" || true
     if [[ "$SIZE" == "L" ]]; then
       "$SCRIPT_DIR/run-spec.sh" "$SUB_NUMBER" --opus
     else
       "$SCRIPT_DIR/run-spec.sh" "$SUB_NUMBER"
     fi
   fi
   ```
   既存の dispatch 本体 (`elif` 以下) のロジック・インデント対象コードは変更しない。
2. (after 1) `tests/run-auto-sub.bats` の293行目 "phase/ready present" テストの直後に5件の新規 `@test` を追加する (→ Acceptance Criteria 2): `phase/code`/`phase/review`/`phase/merge`/`phase/verify`/`phase/done` をそれぞれ単独付与した `gh` モック (300行目の "phase/ready absent" テストと同じモック構造を流用し、`echo "triaged"` の代わりに対象ラベルを `echo` する) を使って `run-auto-sub.sh 42` を実行し、`status -eq 0`・`$RUN_SPEC_LOG` が生成されないこと・出力に skip 理由の文言 (`"skipping dispatch"` 等) が含まれることを検証する。既存の293行目 (`phase/ready present`) と300行目 (`phase/ready absent`) の2テストは変更せずそのまま残し、positive/negative 両ケースの回帰網羅とする。

## Verification

### Pre-merge
- <!-- verify: rubric "scripts/run-auto-sub.sh の spec phase 実行判定が phase/ready の不在のみを条件とせず、Issue ラベルに phase/code, phase/review, phase/verify のいずれかが存在する場合は run-spec.sh をディスパッチせず skip し、skip 理由をログ出力する" --> spec phase gate が `phase/code` 以降のラベル存在時に spec を skip し、skip 理由をログ出力する
- <!-- verify: rubric "tests/ 配下に run-auto-sub.sh の spec phase skip 分岐 (phase/code 以降のラベルで spec が実行されないこと、phase/issue やラベルなしでは従来どおり実行されること) を検証する bats テストが存在する" --> spec skip 分岐の positive/negative 両ケースを検証する bats テストが追加されている

### Post-merge
- 次回 `/auto --batch --resume` で `phase/code` 以降の Issue を再開した際、spec phase が skip されることを観察 <!-- verify-type: observation event=auto-run -->
  - Expected output structure:
    - `run-auto-sub.sh` のログに spec phase skip 理由 (`phase/code`, `phase/review`, `phase/merge`, `phase/verify`, または `phase/done` ラベル存在を示す文言) が出力されている
    - `run-spec.sh` が呼ばれていない (spec phase 実行ログが出力されない)

## Notes

- **skip 対象ラベルを Issue AC の3件から5件へ拡張した判断根拠**: Issue 本文 Acceptance Criteria 1 の rubric 文言は `phase/code`/`phase/review`/`phase/verify` の3ラベルを例示するが、(a) Purpose 文の「spec 完了以降の phase」という一般的な表現、(b) Acceptance Criteria 2 の「`phase/code` **以降**のラベルで spec が実行されないこと」という文言、(c) `docs/workflow.md` の phase label 遷移表が示す実際の状態遷移 (`phase/ready` は `/code` 開始時に除去されて以降 `phase/merge`/`phase/done` でも復元されない) の3点から、根本原因は5ラベル全てに及ぶと判断した。3ラベルのみの実装は Issue の一般的な意図 (Purpose・AC2 の「以降」) を部分的にしか満たさず、`phase/merge`/`phase/done` 状態での再ディスパッチという同型の不具合を未修正のまま残すリスクがある。5ラベルへの拡張は既存3ラベルの skip 挙動を包含するスーパーセットであり、Acceptance Criteria 1 の rubric 判定 (3ラベルでの skip 確認) と矛盾しない。`/issue` (What) で確定した要件を変更するものではなく、`/spec` (How) の範囲内で gate 判定の実装精度を高める判断と位置付ける。
- **Steering Docs sync candidate 8件は変更不要の見込み**: `docs/migration-notes.md`/`docs/structure.md`/`docs/tech.md`/`docs/workflow.md` と日本語ミラー4件は `run-auto-sub.sh` に言及するが、いずれも spec phase gate の具体的な条件(何のラベルで skip するか)には踏み込んでおらず、変更不要と判断した (grep 済み、内容は Changed Files 各エントリに記載)。`/code` フェーズでの実読による最終確認を経ても変更不要と判断される可能性が高い。
- **`skills/auto/SKILL.md` は変更不要**: 304行目付近に「`run-auto-sub.sh` checks each sub-issue's `phase/ready` and auto-runs spec if not set」という簡略な説明があるが、これは XL route 全体の要約であり本修正後も方向性として正確 (`phase/ready` チェックは主条件のまま維持される)。同ファイルは Steering Docs sync candidate の grep 対象 (`docs/*.md`/`docs/ja/*.md`) 外であり、スコープ外と判断した。
- **親オーケストレーター (`/auto` 単体 Issue パス) は影響を受けない**: `skills/auto/SKILL.md` の Step 2a (fix-cycle 検出) は単体 Issue パス向けに既に `phase/code`/`phase/review`/`phase/spec` ラベルの不在を確認する同種のガードを持っており、本 Issue の対象である `run-auto-sub.sh` (resume/batch/XL sub-issue パス) とは別経路である。本 Spec のスコープが `run-auto-sub.sh` に閉じていることを相互確認した。
- 資格情報・シークレット管理に関わる変更ではないため、credential/security policy alignment check は該当なし。
- UI を伴わない backend スクリプト修正のため、UI Design phase (Figma 連携) は該当なし。
- Issue 本文の Background 記述 (spec phase gate は `phase/ready` ラベルの不在のみを条件としている) を実装コードと突き合わせ、記述通りであることを確認した。矛盾は検出しなかった。
- **Post-merge AC に Expected output structure を追加**: `modules/verify-classifier.md` の observation 型ガイダンスと照らし、Issue 本文の Post-merge AC (`event=auto-run`) が Option A (2-part structure) の "Expected output structure" サブビュレットを欠いていたため、Issue 本文・Spec の両方に同一内容を追加した (`gh-issue-edit.sh` で更新済み)。観測イベント自体 (次回 resume 時に spec phase が skip される) は変更していない。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — implementation matches the Spec's Implementation Steps exactly (5-label gate extension, same code block, same test structure).

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implemented the gate exactly as specified in the Spec's Implementation Steps: `elif` branch preserved for the `phase/ready`-absent dispatch path, new `if` branch added ahead of it for the 5-label skip condition (`phase/code|review|merge|verify|done`).
- Added 5 new positive-case bats tests (one per skip label) immediately after the existing "phase/ready present" test, each asserting `status -eq 0`, no `run-spec.sh` invocation, and the `"skipping dispatch"` log substring — matching the Spec's test placement and mock-reuse instructions.

### Deferred Items
- Post-merge observation AC (next `/auto --batch --resume` run against a `phase/code`-or-later Issue) is left for post-merge verification, per the Spec's Post-merge section.

### Notes for Next Phase
- Full `bats tests/` suite (1147 tests) passes; behavioral-change detection triggered the full-suite run because `tests/auto-sub-observability.bats` and `tests/run-code.bats` also reference `run-auto-sub.sh`.
- Both pre-merge rubric ACs were graded PASS against the git diff and Issue body; checkboxes updated on the Issue.
