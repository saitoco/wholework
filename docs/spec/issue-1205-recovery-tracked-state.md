# Issue #1205: collect-recovery-candidates: tracked な group-key の対応 Issue が closed かを判別できるようにする

## Overview

`collect-recovery-candidates.sh --with-tracking` の 3 列目 (`tracked:#N` / `untracked`) は対応 Issue の open/closed を区別しない。このため `/audit stats --retention` Section 10 で「対応 Issue が close 済みなのに entry が閾値超過で再発している (post-fix recurrence)」状態が、通常の「tracked = 対応中」と同じ見た目になり、最も注意を要する状態が最も安全そうな表示になってしまう。`--with-tracking` の出力、または Section 10 の表示手順のいずれかで open/closed を判別可能にし、post-fix recurrence を区別して認識できるようにする。

## Reproduction Steps

1. `bash scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 1 --with-tracking` を実行する
2. 出力に `code-pr-tier3-recovery	2	tracked:#799` が含まれる (2026-08-06 実行時点で再現確認済み)
3. `gh issue view 799` は `state: CLOSED` (2026-06-27 close) を返すが、3 列目は `tracked:#799` としか表示されず、対応 Issue が既に closed であること、かつ 2 件の entry が close 後に発生した実再発であることが出力から読み取れない

## Root Cause

`scripts/collect-recovery-candidates.sh` は group-key ごとに `resolved_state` (`OPEN`/`CLOSED`、`--issues-json` から解決) をカットオフモード判定のために既に計算している (`resolved_state`/`resolved_closedat` 算出ブロック)。しかし `--with-tracking` の出力ブロックは `resolved_number` の有無だけを見て `tracked:#N` を出力しており、算出済みの `resolved_state` を捨てて印字している。加えて `skills/audit/SKILL.md` Section 10 には「tracked かつ対応 Issue が closed なのに entry が再発している」を他の tracked と区別する表示カテゴリが無い。

なお、起票時の動機となった実測値 (`manual-recovery-respawn: 21`, `code-pr-tier3-recovery: 6`) は別Issueの #1152 のカットオフ選定バグによる産物であり、PR #1207 で修正済み (Issue 本文の 2026-08-06 訂正を参照)。表示仕様自体の問題は独立して有効であり、今回のライブ再現 (`code-pr-tier3-recovery`, `tracked:#799`, #799 CLOSED) がその現存証拠。

## Changed Files

- `scripts/collect-recovery-candidates.sh`: `--with-tracking` の 3 列目を、tracked 時は `tracked:#N` 固定ではなく既に算出済みの `resolved_state` を使って `tracked:#N:open` / `tracked:#N:closed` を出力するよう拡張する (`untracked` は変更なし)。フォーマットを説明するヘッダーコメント (31行目付近) も更新する
- `tests/collect-recovery-candidates.bats`: 既存の `--with-tracking` テスト (`@test "--with-tracking: appends tracked:#N / untracked as a 3rd column..."`) を新フォーマット (`tracked:#503:closed`) を検証するよう更新し、OPEN 状態フィクスチャで `tracked:#N:open` になることも確認する
- `skills/audit/SKILL.md`: Section 10 のメトリクス表に「Recurring after fix」行 (3 列目が `tracked:#N:closed` である閾値超過 group-key 数) を追加し、手順 3 の出力パース説明を拡張フォーマットに合わせて更新する
- `docs/structure.md`: Key Files の `collect-recovery-candidates.sh` 説明 (187行目付近) の `--with-tracking` 列フォーマット記述を `tracked:#N`/`untracked` → `tracked:#N:open`/`tracked:#N:closed`/`untracked` に更新する
- `docs/ja/structure.md`: 上記の日本語ミラー同期 (`docs/translation-workflow.md` の同期手順、180行目付近)
- `tests/audit-retention.bats`: 変更不要 (grep で確認済み — このファイルは `compute-escalation-level.sh` の verify/icebox 日数閾値テストのみを含み、Section 10 / `collect-recovery-candidates.sh` のカバレッジは元々存在しない。Issue の AC はリグレッション確認のみが目的)

## Implementation Steps

1. `scripts/collect-recovery-candidates.sh` の `--with-tracking` 出力ブロックを拡張し、既に算出済みの `resolved_state` から `:open`/`:closed` を `tracked:#N` に付加する。ヘッダーコメントのフォーマット説明も更新する (→ acceptance criteria 1)
2. `tests/collect-recovery-candidates.bats` の `--with-tracking` テストを新フォーマット (`tracked:#N:open`/`tracked:#N:closed`) を検証するよう更新する (after 1) (→ acceptance criteria 3)
3. `skills/audit/SKILL.md` Section 10 に「Recurring after fix」メトリクス行を追加し、出力パース説明を拡張フォーマットに更新する (after 1) (→ acceptance criteria 2)
4. `docs/structure.md` と `docs/ja/structure.md` の `collect-recovery-candidates.sh` 説明を新フォーマットに同期する (after 1)
5. `bats tests/collect-recovery-candidates.bats` と `bats tests/audit-retention.bats` を実行し、両方 PASS することを確認する (after 2, after 3) (→ acceptance criteria 3, 4)

## Verification

### Pre-merge
- <!-- verify: rubric "collect-recovery-candidates.sh の --with-tracking 出力、または skills/audit/SKILL.md Section 10 の表示手順のいずれかで、tracked な group-key の対応 Issue が open か closed かを判別できるようになっている" --> tracked の open/closed が判別できる
- <!-- verify: rubric "対応 Issue が closed かつ entry が閾値を超えている group-key (post-fix recurrence) が、Section 10 の出力で他と区別して認識できる形になっている" --> post-fix recurrence が区別して認識できる
- <!-- verify: command "bats tests/collect-recovery-candidates.bats" --> `tests/collect-recovery-candidates.bats` が PASS する
- <!-- verify: command "bats tests/audit-retention.bats" --> `tests/audit-retention.bats` が PASS する

### Post-merge
- `/audit stats --retention` を実行し、対応 Issue が closed である group-key (実測時点の現存例: `code-pr-tier3-recovery` / 対応 Issue #799 CLOSED) が、対応 Issue が open の group-key と区別できる形で表示されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **設計選択**: Issue 本文の対応方針候補 1 (スクリプト出力形式の拡張) + 候補 3 (Section 10 での区別表示) の組み合わせを採用 (Issue 本文が「自然に見える」と示唆する組み合わせと一致)。候補 1 単独では Section 10 の集計ロジックに反映されず、候補 3 単独では `/audit` 以外の消費者 (将来の bats や他ツール) に open/closed 情報が伝わらないため、両方を採用した。`resolved_state` は既に算出済みのため追加の API 呼び出しは不要
- **Issue 本文との差異 (Step 6 実装確認)**: Issue 本文は対応方針候補 1 で「既存の消費側 (`/verify` Step 15、`/audit` Section 10、bats) の追従が要る」と述べているが、`skills/verify/SKILL.md` Step 15 の実装を確認したところ `collect-recovery-candidates.sh` を `--with-tracking` **無し** (`--issues-json` のみ、2 列出力) で呼んでおり、`--with-tracking` の 3 列目フォーマットには依存していない。したがって本 Issue の変更で `/verify` Step 15 側の追従は不要 (影響を受けるのは `skills/audit/SKILL.md` Section 10 と `tests/collect-recovery-candidates.bats` のみ)
- **フォーマット選定**: 3 列目は `tracked:#N:open` / `tracked:#N:closed` とし、コロン区切りは既存の `tracked:#N` プレフィックス表記と一貫させた。`untracked` は変更しない
- **計測範囲**: `grep -rn "tracked:#N" docs/ tests/ scripts/` (2026-08-06 実行) — 実装対象として2件検出 (`docs/structure.md`, `docs/ja/structure.md`)。`docs/spec/issue-1152-*.md` / `docs/spec/issue-1191-*.md` (disposable な過去 Spec の記録) と `docs/sessions/.../session.md` (セッション記録) はヒットしたが、履歴記録のため対象外とした
- **ライブ再現確認 (2026-08-06)**: `bash scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 1 --with-tracking` の出力に `code-pr-tier3-recovery	2	tracked:#799` を確認し、`gh issue view 799` で state=CLOSED (closedAt 2026-06-27) であることを確認した。Issue 本文が指摘する動機の実測値 (21件/6件) は #1152 のバグにより無効化されているが、本件の表示仕様問題自体はこのライブ再現によって独立に成立していることを確認済み
- **外部仕様依存チェック (Step 6)**: `collect-recovery-candidates.sh` の変更は既存の内部データ (`--issues-json` の `state` フィールド、#1152 で導入済み) を使うのみで、新しい外部コマンド/API/ライブラリ仕様への依存は発生しない。該当なしと判断
- **UI Design フェーズ (Step 9)**: 本 Issue はバックエンドスクリプト + Skill 表示手順の変更であり、インタラクティブ UI 要素を含まない。スキップと判断

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: `/issue` フェーズの自律判断記録 — Issue の扱い (保留/スコープ縮小/close の3択) について案2「スコープ縮小して維持」を採用した根拠 (#1152 修正確認、`tracked:#799` closed が --threshold 1 で依然出力されることの実測) を記載。Purpose・対応方針候補・AC 本体への変更は無し / URL: https://github.com/saitoco/wholework/issues/1205#issuecomment-5204827118
