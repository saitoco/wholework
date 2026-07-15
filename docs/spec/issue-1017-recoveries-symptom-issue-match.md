# Issue #1017: run-auto-sub: recovery 記録の Improvement Candidate を既知 symptom Issue で自動初期化

## Consumed Comments

No new comments since last phase.

## Overview

`scripts/run-auto-sub.sh` の `_write_manual_recovery_to_recoveries_log()` は `docs/reports/orchestration-recoveries.md` へのエントリ書き込み時、`### Improvement Candidate` を常にテンプレート固定の `未起票` で書く。この `未起票` は `collect-recovery-candidates.sh` の頻度カウント対象であり、正規化を怠ると mitigation 済み symptom に対して `recoveries-auto-fire` が重複 Issue を起票するリスクがある (#1014 verify で実際に手動正規化が必要になった)。

本 Issue では、書き込み時に既知の同 symptom Issue (タイトルが `recoveries: <symptom-short>` を含む Issue) を照合し、存在すれば `起票済み #N` で初期化、存在しなければ現行どおり `未起票` にフォールバックする。

## Changed Files

- `scripts/run-auto-sub.sh`: `_search_recoveries_issue()` / `_find_known_recoveries_issue()` の2ヘルパー関数を追加し、`_write_manual_recovery_to_recoveries_log()` から呼び出して `### Improvement Candidate` の初期値を決定する — bash 3.2+ compatible (連想配列等は使用せず、JSON のフィルタ・ソートは既存パターンと同じ python3 に委譲)
- `tests/run-auto-sub.bats`: 既知 Issue 照合成功時 (`起票済み #N`) と照合失敗時 (`未起票` フォールバック) の両ケースを検証するテストを追加
- `modules/orchestration-fallbacks.md`: `## manual-recovery-spec-write` § `### Rationale` に #1017 の変更点を追記 (同関数への変更は #1005・#1012 と同じくこのセクションに追記する既存慣行)
- Steering Docs sync candidates (`/code` が個別に要否判断。`run-auto-sub.sh` を汎用的に言及しているのみで、本 Issue が変更する内部関数の粒度までは踏み込んでいないため、更新不要の可能性が高い):
  - `docs/migration-notes.md` / `docs/ja/migration-notes.md`
  - `docs/structure.md` / `docs/ja/structure.md`
  - `docs/tech.md` / `docs/ja/tech.md`
  - `docs/workflow.md` / `docs/ja/workflow.md`

## Implementation Steps

1. `scripts/run-auto-sub.sh`: `_write_manual_recovery_to_spec()` の直後 (既存コメント `# _write_manual_recovery_to_recoveries_log ISSUE PHASE RECOVERY_TYPE [EXIT_CODE]` の直前) に、以下2つのヘルパー関数を追加する (→ 受入条件1)
   - `_search_recoveries_issue TARGET STATE DATE_FIELD LIMIT`: `gh issue list --state "$STATE" --json "number,title,$DATE_FIELD" --limit "$LIMIT"` を実行し (失敗時は空文字列にフォールバックし `set -euo pipefail` で script を落とさない)、結果 JSON を `python3 -c` に渡す。python 側で `json.loads` 失敗を空扱いにガードした上で、`TARGET` がタイトルに部分文字列として含まれる (Python の `in` — `collect-recovery-candidates.sh` の `grep -qF` と同じ contains 判定) エントリのみに絞り込み、`DATE_FIELD` の降順でソートして先頭要素の `number` を標準出力する (該当なしなら何も出力しない)
   - `_find_known_recoveries_issue SYMPTOM_SHORT`: `target="recoveries: ${SYMPTOM_SHORT}"` を組み立て、まず `_search_recoveries_issue "$target" open createdAt 500` を呼ぶ。結果が非空ならそれを出力して終了。空なら `_search_recoveries_issue "$target" closed closedAt 1000` を呼び、その結果 (空の場合もそのまま) を出力する
2. `scripts/run-auto-sub.sh`: `_write_manual_recovery_to_recoveries_log()` 内、`if [[ ! -f "$_recoveries_file" ]]; then return 0; fi` の直後・`_date=$(date -u '+%Y-%m-%d %H:%M UTC')` の直前に、以下を追加する (→ 受入条件1)
   ```bash
   local _symptom_short="manual-recovery-${recovery_type}"
   local _matched_issue
   _matched_issue="$(_find_known_recoveries_issue "$_symptom_short")"
   local _improvement_candidate="未起票"
   if [[ -n "$_matched_issue" ]]; then
     _improvement_candidate="起票済み #${_matched_issue}"
   fi
   ```
   続けて、既存の python heredoc内 `"\n### Improvement Candidate\n" "- 未起票\n"` の `"- 未起票\n"` を `"- ${_improvement_candidate}\n"` に置き換える (heredoc デリミタは非クォートの `PYEOF` のため、bash 変数展開が有効)
3. `tests/run-auto-sub.bats`: 既存の `"run-auto-sub: manual recovery: appends canonical H2 entry to orchestration-recoveries.md"` の近くに以下2ケースを追加する (→ 受入条件2)
   - 新規テスト: `$MOCK_DIR/gh` に `"$1" == "issue" && "$2" == "list" && "$*" == *"--state open"*` 分岐を追加し、`[{"number":555,"title":"recoveries: manual-recovery-push-only","createdAt":"2026-07-10T00:00:00Z"}]` を返す。`run bash "$SCRIPT" --write-manual-recovery 42 code push-only` 実行後、`docs/reports/orchestration-recoveries.md` に `起票済み #555` が含まれることを assert
   - 既存の "appends canonical H2 entry" テスト (`gh` mock はデフォルトで `issue list` に空応答 → 未マッチ) に `grep -q -- "- 未起票"` の assertion を追加し、フォールバックケースを明示的に検証する
4. `modules/orchestration-fallbacks.md`: `## manual-recovery-spec-write` § `### Rationale` の末尾 (Issue #1012 の箇条書きの後) に、`_write_manual_recovery_to_recoveries_log()` が既知 symptom Issue の照合により `### Improvement Candidate` を `起票済み #N` で初期化するようになった旨と、目的 (`recoveries-auto-fire` による mitigation 済み symptom の重複起票防止) を1箇条追記する
5. `bats tests/run-auto-sub.bats` を実行し、全テストが PASS することを確認する (→ 受入条件3)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の _write_manual_recovery_to_recoveries_log が、タイトル recoveries: <symptom> に一致する既知 Issue を照合して Improvement Candidate を 起票済み #N で初期化し、照合失敗時は 未起票 にフォールバックする実装になっている" --> 同 symptom の既知 Issue が存在する場合、新規エントリの Improvement Candidate が `起票済み #N` で書き込まれる
- <!-- verify: rubric "tests/run-auto-sub.bats に、既知 Issue 照合成功時に 起票済み #N が書かれるケースと、照合失敗時に 未起票 にフォールバックするケースの両方を検証するテストが存在する" --> 照合ありなし両ケースの bats テストが追加されている
- <!-- verify: command "bats tests/run-auto-sub.bats" --> bats テストが PASS する

### Post-merge

- <!-- verify-type: observation event=auto-run --> <!-- verify: rubric "docs/reports/orchestration-recoveries.md の直近の manual-recovery エントリについて、既知 symptom (recoveries: <symptom-short> を含むタイトル) の Issue が存在する場合は Improvement Candidate が 起票済み #N 形式で初期化されている" --> 次回 manual recovery 記録時、既知 symptom のエントリが `起票済み #N` で初期化されることを観察

## Notes

- **Auto-Resolved Ambiguity Points の引き継ぎ**: `/issue` フェーズで既に「照合精度は contains 方式」「タイブレークは open優先→作成日時降順、なければ closed の closedAt 降順」の2点が解決済み (Issue body参照)。本 Issue は SPEC_DEPTH=light のため Step 7 (Ambiguity Resolution) はスキップし、上記の決定をそのまま設計に反映した。
- **`gh issue list --search` を採用しなかった判断**: Issue body の Auto-Resolved Ambiguity Points はタイブレーク根拠として `gh issue list --search` のソート順に触れているが、本 Spec では `--search` ではなく `--state <open|closed> --json ... --limit <N>` の単純リスト取得 + ローカル Python contains フィルタを採用する。理由: GitHub 検索バックエンドのトークナイズ挙動 (ハイフン区切りの symptom-short、例 `manual-recovery-respawn`、に対する厳密な部分一致保証が `gh issue list --help` の公式説明からは確認できない) に依存すると偽陰性(真の一致を見逃す)リスクがあり、既存の `collect-recovery-candidates.sh` が同じ問題領域で既に採用している「ローカル contains フィルタ」方式 (`grep -qF`) と技術的に一貫させる方が安全。タイブレーク自体 (open優先・日時降順) は Python 側のソートで実現するため、`--search` の `sort:` 機能に依存しなくても同じポリシーを実現できる。
- **フェッチ件数の上限**: open は `--limit 500` (現在の open Issue 数は24件で十分な余裕)、closed は `--limit 1000` (現在の closed Issue 数は約722件)。`skills/verify/SKILL.md` Step 15 の既存の `--limit 200` 前例に倣った固定値であり、ページネーションは行わない。`_write_manual_recovery_to_recoveries_log()` は外部強制終了からの手動復旧という低頻度パスでのみ呼ばれるため、コスト面の懸念は小さい。
- **Post-merge AC の強化**: 元の Issue body の post-merge AC は `<!-- verify-type: observation event=auto-run -->` のみで観測構造 (期待される出力) が未記載だったため、`modules/verify-classifier.md` の observation AC 構造チェックに従い Option B (rubric verify command 付与) で強化し、Issue body ・ Spec 双方に反映した。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note。diff は Implementation Steps 1〜5 と1対1で対応しており、構造的な逸脱は見られなかった。

### 再発している問題パターン

Nothing to note。今回のレビューで検出された問題は CONSIDER 1件 (固定 `--limit` 値の将来的なスケール懸念) のみで、Spec Notes で既に既知のトレードオフとして明記済みのものだった。ワークフロー上の改善点として抽出すべき繰り返しパターンはない。

### Acceptance Criteria の検証難易度

Nothing to note。pre-merge AC 3件 (rubric x2, command x1) はいずれも diff・bats 結果と明確に対応しており、UNCERTAIN は発生しなかった。verify command の記載・精度に問題はなかった。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- pre-merge AC 3件 (rubric x2, command x1) を diff 内容と bats 実行結果から再検証し、いずれも PASS を確認 (Issue body は既に `[x]` 済みだったため更新なし)
- REVIEW_DEPTH=light (Size M と `--light` 指定) のため review-light agent 1体で全4アスペクトを実行し、MUST/SHOULD 無し・CONSIDER 1件のみを確認
- CONSIDER 1件 (固定 `--limit 500`/`1000` の将来的なスケール懸念) は Spec Notes で既に許容済みのトレードオフと判断し、修正せずインラインコメントのみ投稿

### Deferred Items
- `--limit 500`/`1000` の固定値は closed Issue 数が1000に近づいた場合の再検討事項として CONSIDER コメントに記録 (対応は不要、将来のフォローアップ候補)
- post-merge AC (`起票済み #N` 初期化の観察) は次回 manual recovery 記録時に `/verify` で検証される

### Notes for Next Phase
- MUST issue 無し、CI 全 SUCCESS のため `/merge 1019` にそのまま進行可能
- worktree `code+issue-1017` が stale ロック状態で残存していたため review 開始時に削除・ブランチ再作成済み (プロセス終了済みを確認の上で強制削除)
