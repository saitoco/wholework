# Issue #1226: audit: /audit stats --retention Section 10 の recovery 候補収集に --issues-json を渡す

## Overview

`/audit stats --retention` の Section 10 (Recovery Candidate Frequency) が `collect-recovery-candidates.sh` を呼び出す際に `--issues-json` を渡していないため、`Untracked threshold-exceeding` と `Recurring after fix` の集計が実際の Issue 状態を反映できていない。`skills/verify/SKILL.md` Step 15 と同じ呼び出し形 (all-state issue リストを一時ファイルに書き出し `--issues-json` で渡す) に揃える。

## Reproduction Steps

1. `docs/reports/orchestration-recoveries.md` に、対応 Issue が既に CLOSED になっている group-key (例: `manual-recovery-respawn`、対応 Issue #1014 CLOSED) のエントリが、その `closedAt` より後にも記録されている状態を用意する
2. `/audit stats --retention` を実行する
3. Section 10 は `skills/audit/SKILL.md:506` の現行呼び出し (`--issues-json` なし) で `collect-recovery-candidates.sh --with-tracking` を実行するため、3列目が常に素の `tracked:#N` (open/closed サフィックスなし) にフォールバックし、`Recurring after fix` は常に 0 として表示される
4. 同じ `docs/reports/orchestration-recoveries.md` に対して `--issues-json` 付きで実行すると (`skills/verify/SKILL.md` Step 15 と同じ形)、3列目に `tracked:#1014:closed` が現れ `Recurring after fix` が 1 以上になる (Issue 本文の実測差分表を参照)

## Root Cause

`scripts/collect-recovery-candidates.sh` は、group-key に対応する Issue の `state`/`closedAt` を `--issues-json` に渡されたファイルからしか取得できない (L103-129 の issue リスト読み込みブロック)。`--issues-json` が渡されない場合、各 group-key の除外判定は「対応 Issue の `closedAt`」ではなく「その group-key 自身の最新 `起票済み #N` エントリのタイムスタンプ」を cutoff とする degrade path に落ち (L278-292)、`--with-tracking` の3列目も `:open`/`:closed` サフィックスの付かない素の `tracked:#N` にフォールバックする (L315-329)。

`skills/audit/SKILL.md` の Section 10 (L506) はこのスクリプトを `--issues-json` なしで呼んでおり、一方 `skills/verify/SKILL.md` Step 15 (L918-926) は all-state issue リストを `.tmp/open-issues-$NUMBER.json` に書き出してから `--issues-json` 付きで呼んでいる。同一スクリプトに対する2つの呼び出し形が割れており、Section 10 側だけが `Untracked threshold-exceeding` / `Recurring after fix` を構造的に正しく算出できない状態になっている。

## Changed Files

- `skills/audit/SKILL.md`: `#### Section 10: Recovery Candidate Frequency` (現行 L502-526) の手順1 (`collect-recovery-candidates.sh` 呼び出し) の直前に、`skills/verify/SKILL.md` Step 15 と同じ「all-state issue リストを一時ファイルに書き出す」手順を新設し、既存呼び出しに `--issues-json` を追加する。以降の手順番号を1つずつ繰り下げる (現行手順2〜5 → 3〜6)
- `tests/audit-retention.bats`: `collect-recovery-candidates.sh --with-tracking` を直接呼び出し、対応 Issue が CLOSED の group-key が `closedAt` 後のエントリを「Recurring after fix」(`tracked:#N:closed`) として集計することを保護する `@test` を新設

## Implementation Steps

1. `skills/audit/SKILL.md` の `#### Section 10: Recovery Candidate Frequency` を変更する。現行の手順1 (`${CLAUDE_PLUGIN_ROOT}/scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 1 --with-tracking` を実行する箇所) の直前に新しい手順1を挿入する: `skills/verify/SKILL.md` Step 15 の手順1 (`gh issue list --state all --limit 1000 --json number,title,state,closedAt` を実行し、Write ツールで一時ファイルに書き出す) と同内容の手順を、ファイル名のみ `.tmp/audit-recovery-issues.json` (Issue番号に紐づかないプロジェクト全体集計のため、Notes参照) に変えて記述する。既存の `collect-recovery-candidates.sh` 呼び出し (新手順2) に `--issues-json .tmp/audit-recovery-issues.json` を追加する。以降の手順 (現行2〜5) をそれぞれ3〜6に繰り下げる (→ 受け入れ基準1, 2)
2. `tests/audit-retention.bats` に、`scripts/collect-recovery-candidates.sh` を指す2つ目のスクリプト変数 (例: `RECOVERY_SCRIPT`) をファイル冒頭の既存 `SCRIPT` 変数 (`compute-escalation-level.sh` 用、変更しない) と併記する形で追加し、新しい `@test` を追加する (after 1)。`tests/collect-recovery-candidates.bats` の `"--with-tracking: appends tracked:#N:closed / untracked as a 3rd column..."` テスト (L252-295) と同じインライン heredoc フィクスチャパターン (`$BATS_TEST_TMPDIR` 上に `recovery.md`/`issues.json` を都度生成、外部フィクスチャファイル不使用) を踏襲し、対応 Issue が CLOSED で `closedAt` より後の日付を持つエントリを含む group-key を用意して `--with-tracking` 出力の3列目が `tracked:#<N>:closed` になることを assert する (→ 受け入れ基準3, 4)

## Verification

### Pre-merge
- <!-- verify: section_contains "skills/audit/SKILL.md" "Section 10: Recovery Candidate Frequency" "--issues-json" --> Section 10 の `collect-recovery-candidates.sh` 呼び出しに `--issues-json` が含まれている
- <!-- verify: rubric "skills/audit/SKILL.md の Section 10 に、--issues-json へ渡す all-state issue リスト (number/title/state/closedAt を含む) の取得手順が記載されており、skills/verify/SKILL.md Step 15 と同じ内容のリストを渡す形になっている" --> all-state issue リストの取得手順が記載されている
- <!-- verify: command "bats tests/audit-retention.bats" --> `tests/audit-retention.bats` が PASS する
- <!-- verify: rubric "tests/audit-retention.bats に、対応 Issue が closed の group-key が Recurring after fix として集計されることを保護する検証ケースが追加されている" --> Recurring after fix の集計がテストで保護されている

### Post-merge
- `/audit stats --retention` を実行し、Section 10 の 3 列目に `:closed` サフィックスが現れ `Recurring after fix` が 1 以上として集計されることを確認する (実測時点の現存例: `manual-recovery-respawn` / 対応 Issue #1014 CLOSED) <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **一時ファイルのパス**: `.tmp/audit-recovery-issues.json` を採用する (Issue本文の Auto-Resolved Ambiguity Points で「`$NUMBER` を持たない命名が必要」と判断された点への回答)。`/verify` Step 15 の `.tmp/open-issues-$NUMBER.json` との対比で、`/audit stats` は Issue 番号に紐づかないプロジェクト全体集計コマンドであるため
- **issue リストの取得元**: `/audit stats` Step 1 (Data Collection) が既に取得済みの `--since`/`--limit` フィルタ付きリストは再利用しない。Issue本文の実測差分表にある通り、`docs/reports/orchestration-recoveries.md` の `tracked:#N` は Step 1 のデフォルト範囲 (90日/500件) 外の古い Issue を参照しうるため、`skills/verify/SKILL.md` Step 15 と同じ独立した `gh issue list --state all --limit 1000 ...` を新規実行する
- **`tests/audit-retention.bats` と `tests/collect-recovery-candidates.bats` の役割分担**: `tests/collect-recovery-candidates.bats` は `collect-recovery-candidates.sh` 自体のスクリプト単体テストであり、`--with-tracking` の `tracked:#N:closed` 出力は既に同ファイル L252-295 のテストで保護済み。本 Issue の AC4 (rubric) は `tests/audit-retention.bats` 側 ── `/audit stats --retention` Section 10 が消費する挙動のテストホーム ── への追加を明示的に要求しているため、同等シナリオを別ファイルに重複して追加する
- **UI Design Phase**: 本 Issue はバックエンド/CLI スキルプローズおよびテストの内部修正であり、インタラクティブ UI コンポーネントを含まないため、`skills/spec/figma-design-phase.md` の Auto-detection Criteria により「UI design not needed」と判定した (UI Design セクションは省略)
- **Issue body vs 実装の矛盾検出**: なし。Background の技術的主張 (`skills/audit/SKILL.md:506` の呼び出し形、`collect-recovery-candidates.sh` L103-127 の `--issues-json` 依存、`skills/verify/SKILL.md:918-926` の先行実装) はいずれもコードベースと突合し正確であることを確認した (Consumed Comments の issue retrospective でも同様の確認結果が記録されている)
- **ドキュメント同期**: `skills/audit/SKILL.md` を変更するため `docs/`, `tests/`, `scripts/` を "Recovery Candidate Frequency" で横断検索したが、`docs/tech.md` / `docs/ja/tech.md` の言及 (`recoveries-auto-fire` opt-out の文脈で Section 10 の利用方法を案内する記述) は本 Issue の変更後も正確であり、更新不要。`docs/spec/issue-1191-*.md` / `docs/spec/issue-1236-*.md` は使い捨ての過去 Spec のため対象外

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective ── Background の技術的主張はコードベースと突合し正確、曖昧性2件は既に Issue本文に自動解決記録済み (issue リスト取得元・一時ファイル命名)、AC変更なし、`tests/audit-retention.bats` の存在確認済み、タイトルドリフト・blocked-by・sub-issue分割いずれも該当なし ── https://github.com/saitoco/wholework/issues/1226#issuecomment-5216387034

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜2 を Spec 記載どおりの順序・内容で実施した。

### Design Gaps/Ambiguities

N/A — Spec の Auto-Resolved Ambiguity Points (issue リスト取得元・一時ファイル命名) は実装中に再検証が必要になる齟齬なく、そのまま採用できた。

### Rework

- patch route の Step 8 (「各手順完了後にコミット」) に従って手順1・2をそれぞれ中間コミットしたところ、Step 11 の `closes #$NUMBER` 必須チェック (最新コミットの subject に `#N` が含まれること) を満たさなかった。中間コミットの subject には Issue 番号を含めない設計だったため、Step 11 到達時点で working tree が既にクリーンで新規コミット対象が無く、`git commit --amend` で最新コミットの message のみ書き換えて対応した (このブランチは未 push・未 merge のローカル専用コミットのため amend は安全)。原因: Step 8 の中間コミット手順と Step 11 の「最新コミット subject に #N 必須」チェックの間に、中間コミット群の扱いに関する明示的な接続規定が SKILL.md に無い。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Section 10 の呼び出し形を `skills/verify/SKILL.md` Step 15 と完全一致させた (`gh issue list --state all --limit 1000 --json number,title,state,closedAt` → `.tmp/audit-recovery-issues.json` → `--issues-json`)。Spec Notes の指示どおり、`/audit stats` Step 1 の `--since`/`--limit` フィルタ付きリストは再利用していない
- `tests/audit-retention.bats` に `RECOVERY_SCRIPT` 変数を追加し、`tests/collect-recovery-candidates.bats` の `--with-tracking` テストと同じインライン heredoc フィクスチャパターンを踏襲した新規 `@test` を追加した。Issue Background 実測差分の `manual-recovery-respawn` / `#1014` 事例をそのままフィクスチャに使用

### Deferred Items
- Post-merge AC (`/audit stats --retention` を実行し Section 10 の `:closed` サフィックスと `Recurring after fix >= 1` を確認する) は `verify-type: observation event=auto-run session=next` のため `/verify` フェーズで確認する

### Notes for Next Phase
- Pre-merge AC 4件はすべて `/code` 内で PASS 確認済み、Issue checkbox も `[x]` 済み
- `bats tests/audit-retention.bats` は 16/16 PASS (既存15件 + 新規1件)。フルスイート (`bats tests/`) は Behavioral Change Detection の narrow-scope 判定によりスキップした (変更対象ファイルを参照する他テストファイルなし)

## Issue Retrospective

### 事実確認 (Background)

Background で参照されているコード上の主張 (`skills/audit/SKILL.md:506` の呼び出し形、`collect-recovery-candidates.sh` L103-127 の `--issues-json` 依存、`skills/verify/SKILL.md:918-926` の先行実装) はすべてコードベースと突合し、正確であることを確認した。

### 曖昧性の自動解決 (非対話モード)

Size M (検出上限 3件) のうち 2 件を検出し、いずれも「既存パターンから一意に推論可能」かつ「AC テキスト自体は選択によって変化しない」ため自動解決した。Issue 本文の `## Auto-Resolved Ambiguity Points` セクションに記録済み。

1. **Issue リストの取得元**: `/audit stats` Step 1 が既に取得済みの `--since`/`--limit` フィルタ付きリストを再利用せず、`skills/verify/SKILL.md` Step 15 と同一の独立した `gh issue list --state all --limit 1000 ...` を新規実行する方針とした。
   - 理由: `docs/reports/orchestration-recoveries.md` の `tracked:#N` は Step 1 のデフォルト `--since 90日` / `--limit 500` の範囲外を参照しうる (実測差分表の `#799` など、古い Issue 番号が該当し得る)。AC2 の rubric 文言 (「Step 15 と同じ内容のリストを渡す形」) が既にこの選択を明示的に要求している。
2. **一時ファイルのパス**: `/verify` Step 15 の `.tmp/open-issues-$NUMBER.json` は Issue 番号紐付けだが、Section 10 は特定 Issue に紐づかないプロジェクト全体集計のため `$NUMBER` を含まない命名が必要になる。具体的なファイル名は既存コードベースに規約が無く、AC テキストにも影響しないため `/spec`/`/code` フェーズの裁量とした。

### Acceptance Criteria への変更

変更なし。起票時点の AC は既に verify command 割り当て・チェックボックス形式・`observation session=next` タグとも要件を満たしており、機械チェック (`check-skill-change-observation-ac.sh` / `check-ac-checkbox-format.sh`) もいずれも問題なしを確認した。

### その他

- `tests/audit-retention.bats` は既存ファイルとして存在確認済み (AC3 の `command "bats tests/audit-retention.bats"` は有効な対象を指している)。
- タイトルドリフトなし、blocked-by なし、sub-issue 分割は Size M のため非対象 (非対話モードのため高リスク判断としてもスキップ)。
