# Issue #1015: run-auto-sub: Spec 未作成段階の recovery 記録による Spec 分裂を解消

## Consumed Comments

No new comments since last phase.

## Overview

`run-auto-sub.sh` の `_write_manual_recovery_to_spec()` は、`--write-manual-recovery` 実行時に `docs/spec/issue-N-*.md` の glob が空だと `docs/spec/issue-N-recovery.md` という stub Spec を新規作成する (`scripts/run-auto-sub.sh` 147-153行目)。この stub 作成は、triage/spec phase 中の kill → recovery のように「Spec がまだ存在しない段階」で発生し、後続の spec phase が別名 (`issue-N-<short-title>.md`) で正式 Spec を作成すると、`issue-N-*.md` glob が2ファイルにマッチする分裂状態を引き起こす。

本 Issue の Purpose で示された2方式のうち、**(b) `_write_manual_recovery_to_spec()` が Spec 不在時は stub を作らず recoveries log + イベントのみに記録する** を採用する (判断根拠は Notes 参照)。stub 作成分岐を削除し、Spec 未作成時は early return して `docs/reports/orchestration-recoveries.md` (既に無条件で書き込み済み) と `manual_intervention` イベントのみを記録先とする。Spec 側への反映は、後続の spec phase が正式 Spec を作成した後、`/verify` Step 12 の既存ルール (`## Auto Retrospective` に記録が無ければ notable content として Verify Retrospective に記録する) が自然にカバーする。

## Reproduction Steps

1. Issue N に対して `docs/spec/issue-N-*.md` が1件も存在しない状態 (triage/spec phase 中の kill など) で `run-auto-sub.sh --write-manual-recovery N <phase> <recovery_type> [exit_code]` を実行する。
2. `_write_manual_recovery_to_spec()` (`scripts/run-auto-sub.sh` 141-153行目) が glob 結果の空を検出し、`docs/spec/issue-N-recovery.md` を新規作成して `## Auto Retrospective` / `### Manual recovery (phase)` エントリを書き込み、commit + push する。
3. その後 `/spec N` (このスキル自身) が実行され、Step 10 でタイトル由来の別名 `docs/spec/issue-N-<short-title>.md` を新規作成する — stub の存在を関知しない。
4. `docs/spec/issue-N-*.md` の glob が2ファイルにマッチする分裂状態になる。`modules/retro-proposals.md` Step 2 の Glob と `/verify` Step 12 の Spec 読み込みがどちらのファイルを正とするか曖昧になり、`/verify` Step 12 の「`## Auto Retrospective` に記録済みか」判定が stub 側にしかない記録を見落とし得る。

実例: `docs/spec/issue-1007-recovery.md` が issue phase kill で作成され、正式 Spec `docs/spec/issue-1007-fix-issues-processed-pr-leak.md` と分裂した。`/verify 1007` で手動統合・stub 削除して解消したが機構的な保証はなかった。`docs/spec/issue-961-recovery.md` は現在も `docs/spec/issue-961-worktree-merge-push-checkout.md` と分裂したまま残っており (当時の `/spec` は統合せず「別ファイルのまま残す」と Notes に明記して意図的に split 状態を容認した)、`/spec` 側の判断が実行のたびに揺れていたことを示す。

## Root Cause

`_write_manual_recovery_to_spec()` (`scripts/run-auto-sub.sh`) は、`docs/spec/issue-${issue}-*.md` の glob が空の場合に「この Issue にはまだ Spec が存在しない」ことを理由に `issue-${issue}-recovery.md` という新規 Spec ファイルを作成する (147-153行目)。しかし glob が空である理由は「まだ spec phase が実行されていない (これから正式 Spec が作られる)」場合と「本当に Spec が存在しない」場合を区別しておらず、前者のケースでは stub がその後の正式 Spec 作成と衝突し、恒久的な2ファイル分裂を生む。`/spec` スキル (`skills/spec/SKILL.md`) 側にも既存の `issue-N-recovery.md` stub を検出・統合するロジックがなく、過去の実行例 (#1007, #961) でも都度アドホックに (verify 側で手動統合 / spec 側で意図的に容認) 異なる対応がなされており、再発防止の機構がなかった。

## Changed Files

- `scripts/run-auto-sub.sh`: `_write_manual_recovery_to_spec()` (127-182行目) の stub 作成分岐 (147-153行目、`if [[ -z "$spec_file" ]]; then ... fi` で `issue-${issue}-recovery.md` を新規作成する部分) を削除し、Spec 未作成時は早期 return (stderr に理由を1行出力してその後の Auto Retrospective 追記・commit・push をスキップ) に置き換える。Spec が既に存在する場合の分岐は変更しない — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: 既存テスト `"run-auto-sub: manual recovery: commits when spec file is untracked"` (1958行目付近) を、stub 自動作成ではなく事前に (untracked な) 正式 Spec ファイルを配置する形に更新し、untracked git status 分岐のカバレッジを維持する。加えて新規テストを追加し、Spec が一切存在しない場合に `docs/spec/issue-42-recovery.md` が作成されないこと・`--write-manual-recovery` が exit 0 で終了することを確認する
- `modules/orchestration-fallbacks.md`: `## manual-recovery-spec-write` セクション (559-590行目、特に576行目の箇条書きと585行目の Rationale) および `### Manual path: Spec Auto Retrospective write` セクション (617-627行目) の記述を、新しい条件付き Spec 書き込み挙動 (正式 Spec が既存の場合のみ追記。未存在時は recoveries log + event のみ) に更新する
- `docs/tech.md` (Steering Docs sync candidate): 56行目「... it records the recovery via `run-auto-sub.sh --write-manual-recovery` ... which writes to the sub-issue Spec, `docs/reports/orchestration-recoveries.md`, and a `manual_intervention` event」の記述を新しい条件付き挙動に合わせて確認・更新する
- `docs/ja/tech.md` (Steering Docs sync candidate, 日本語ミラー): 47行目の対応する記述を `docs/translation-workflow.md` の Sync Procedure に従って同期する

**Steering Docs sync candidate として検出したが変更不要と判断したファイル (grep `run-auto-sub.sh` 実施済み):**

- `docs/structure.md` / `docs/ja/structure.md`: `run-auto-sub.sh` への言及は Scripts 一覧の1行役割説明のみで、`_write_manual_recovery_to_spec()` の内部挙動には触れていない
- `docs/workflow.md` / `docs/ja/workflow.md`: 119行目付近の「External kill respawn」節は `--write-manual-recovery` の呼び出し方法を説明するのみで、Spec 書き込みが無条件かどうかには言及していない
- `docs/migration-notes.md` / `docs/ja/migration-notes.md`: `run-auto-sub.sh` の verify phase 削除という別マイグレーションの記録であり、本修正の対象外

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `_write_manual_recovery_to_spec()` を修正する。現状の (147-153行目)
   ```bash
   if [[ -z "$spec_file" ]]; then
     local title
     title=$(gh issue view "$issue" --json title -q '.title' 2>/dev/null || echo "Issue #${issue}")
     mkdir -p "$spec_dir"
     spec_file="$spec_dir/issue-${issue}-recovery.md"
     printf '%s\n' "# Issue #${issue}: ${title}" > "$spec_file"
   fi
   ```
   を、次の内容に置き換える:
   ```bash
   if [[ -z "$spec_file" ]]; then
     echo "[#${issue}] Spec not yet created for issue #${issue}; skipping spec-side manual recovery record (preserved via recoveries log + manual_intervention event; spec phase will fold this into the formal Spec once created)." >&2
     return 0
   fi
   ```
   これにより、以降の `## Auto Retrospective` 追記・commit・push 処理は Spec が既存の場合のみ到達する (→ acceptance criteria 1)
2. `tests/run-auto-sub.bats` の `"run-auto-sub: manual recovery: commits when spec file is untracked"` (1958行目付近) を、`mkdir -p "$BATS_TEST_TMPDIR/docs/spec"` のみで終えず `echo "# Issue #42: test spec" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"` を事前作成するよう更新し (既存の `"writes Auto Retrospective to spec file"` テストと同じ配置)、git status mock の `"?? docs/spec/issue-42-recovery.md"` を `"?? docs/spec/issue-42-test.md"` に合わせて修正する (untracked 状態のまま正式 Spec に追記されるケースを検証する形に変更)。加えて新規テスト `"run-auto-sub: manual recovery: skips spec write entirely when no spec exists (no stub created)"` を追加し、`docs/spec/` にファイルが一切ない状態で `--write-manual-recovery 42 code push-only` を実行した際に `[ "$status" -eq 0 ]` かつ `[ ! -f "$BATS_TEST_TMPDIR/docs/spec/issue-42-recovery.md" ]` であることを確認する (after 1) (→ acceptance criteria 1, 2)
3. `modules/orchestration-fallbacks.md` の `## manual-recovery-spec-write` セクション (576行目の箇条書き、585行目の Rationale) と `### Manual path: Spec Auto Retrospective write` セクション (625行目) を、「`_write_manual_recovery_to_spec()` は正式 Spec が既に存在する場合のみ `### Manual recovery (PHASE)` を追記し、存在しない場合は recoveries log + event のみに記録して Spec 側は spec phase 完了後の `/verify` に委ねる」という新しい挙動に合わせて更新する (parallel with 1, 2) (→ acceptance criteria 1)
4. `docs/tech.md` 56行目の記述を新しい条件付き挙動に合わせて更新し、`docs/translation-workflow.md` の Sync Procedure に従って `docs/ja/tech.md` 47行目に日本語ミラーを同期する (parallel with 1-3) (→ acceptance criteria 1)

## Verification

### Pre-merge

- <!-- verify: rubric "採用方式 (stub 統合または stub 非作成) の実装により、triage/spec phase 中の recovery 記録後に spec phase が走っても Spec ファイルが分裂せず、Manual recovery エントリが最終的な Spec の Auto Retrospective (または recoveries log) に保全される" -->
- <!-- verify: command "bats tests/run-auto-sub.bats" -->

### Post-merge

- 次回 triage/spec phase 中の kill → recovery 記録の実発生時、Spec 分裂が起きないことを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- **SPEC_DEPTH=light (Size M) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。** Issue Purpose で明示された2方式 (a: spec phase が stub を検出して正式 Spec に統合、b: `_write_manual_recovery_to_spec()` が Spec 不在時に stub を作らない) のうち **(b) を採用**した。判断根拠:
  - Issue 本文の AC2 が `<!-- verify: command "bats tests/run-auto-sub.bats" -->` を指定しており、bats でテスト可能な変更対象は `scripts/run-auto-sub.sh` 側 (方式 b) である。prose 実行の `skills/spec/SKILL.md` (方式 a) には bats テストが存在せず、AC2 をそのままでは満たせない
  - AC1 の rubric 文言自体が「Manual recovery エントリが最終的な Spec の Auto Retrospective **または recoveries log** に保全される」と明記しており、recoveries log のみへの保全で AC を満たす設計を許容している
  - `_write_manual_recovery_to_recoveries_log()` は現状でも Spec の有無に関わらず無条件で `docs/reports/orchestration-recoveries.md` に記録するため、(b) は「記録が失われる」ことなく最小差分で分裂を根絶できる。(a) は markdown stub の内容を正式 Spec にマージする LLM 側ロジックが必要で、light depth の実装ステップ予算 (5件) に対して相対的に複雑
  - Spec 側への反映は、正式 Spec 作成後に `/verify` Step 12 の既存ルール (`## Auto Retrospective` 未記録なら notable content として Verify Retrospective に記録) が自然にカバーするため、情報が失われるわけではなく「記録タイミングが即時から `/verify` 時点に変わる」だけである
- **Tier2/Tier3 の同型パターン (スコープ外)**: `_write_tier2_recovery_to_spec()` / `_write_tier3_recovery_to_spec()` (`scripts/run-auto-sub.sh` 356-439行目) も `_write_manual_recovery_to_spec()` と同一の stub 作成分岐を持つ。本 Issue の Purpose 文が名指しするのは `_write_manual_recovery_to_spec()` のみのため、Tier2/Tier3 側の同種修正は本 Spec のスコープ外とした。特に Tier2 (`_write_tier2_recovery_to_spec()`) は Manual recovery 系と異なり `docs/reports/orchestration-recoveries.md` への書き込みが無く、Spec 書き込みが唯一の永続記録であるため、同じ「stub を作らない」修正を機械的に適用すると記録が完全に失われる回帰を招く — Tier2 側を修正する場合は recoveries log への書き込み追加とセットで設計する必要がある。`/verify` の retro-proposals パイプラインを preempt しないため本 Spec では起票しない
- **既存の分裂/stub インスタンス (バックフィル対象外)**: 調査中に3件の実例を確認した。(1) `docs/spec/issue-957-recovery.md` (`_write_manual_recovery_to_spec()` 由来、issue #957 は phase/done で closed、他に正式 Spec が作成されず stub のみが恒久化)、(2) `docs/spec/issue-850-recovery.md` (`_write_tier2_recovery_to_spec()` 由来、issue #850 は phase/done で closed、同様に stub のみ)、(3) `docs/spec/issue-961-recovery.md` (issue #961 は CLOSED/phase/verify、正式 Spec `docs/spec/issue-961-worktree-merge-push-checkout.md` と**現在も分裂したまま** — 当時の `/spec` 実行が Notes で「別ファイルのまま残す」と意図的に非統合を選択した)。いずれも本 Issue の再発防止スコープには含めず、バックフィル/統合が必要であれば別 Issue で扱う

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-4 をそのまま順に実施した

### Design Gaps/Ambiguities
- `_write_manual_recovery_to_spec()` の stub 作成分岐は `scripts/run-auto-sub.sh` 内に3箇所同一パターンで存在した (Manual/Tier2/Tier3)。Edit ツールの一意性制約により対象箇所 (147-153行目付近、Manual recovery 用) を周辺コンテキストで一意に特定する必要があった。Spec の「Changed Files」記載行数 (127-182行目) はおおむね正確だったが、実際のブロック開始行はやや異なっていた (誤差は軽微で実装に支障なし)

### Rework
- N/A — 手戻りなし

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Notes で確定済みの方式 (b: stub 非作成 + early return) をそのまま採用し、実装は Spec Implementation Steps 1-4 の順に完了
- Tier2/Tier3 の同型 stub 作成分岐には触れず、Spec Notes の "スコープ外" 判断を踏襲した

### Deferred Items
- Tier2/Tier3 (`_write_tier2_recovery_to_spec()` / `_write_tier3_recovery_to_spec()`) の同種修正は本 Issue のスコープ外 (Spec Notes に判断根拠あり、起票はしない方針)
- 既存の分裂/stub インスタンス (#957, #850, #961) のバックフィル/統合は本 Issue のスコープ外

### Notes for Next Phase
- Behavioral change 検出により `bats tests/` フルスイート (1197件) を実行し全 PASS を確認済み — review 側で改めてフルスイートを回す必要は薄い
- `docs/tech.md` / `docs/ja/tech.md` は同一コミットで同期済み (`check-translation-sync.sh` で `docs/tech.md` IN_SYNC 確認済み)。他の pre-existing sync gap (`docs/guide/autonomy.md` 等) は本 Issue と無関係
