# Issue #1408: recoveries: orchestration-recoveries.md にローテーション/アーカイブ方針を導入

## Consumed Comments

No new comments since last phase. (cutoff undetermined — この Issue にはまだ `phase/*` ラベルの付与履歴がなく、Fallback B によりベストエフォートで全コメントを走査した。Issue へのコメントは 0 件)

## Overview

`docs/reports/orchestration-recoveries.md` は「Append-only. Newest entries first.」な単調増加ログで、現在 1960 行 (約 78KB, 92 エントリ, 2026-06-03〜2026-08-19) ある。`skills/verify/SKILL.md` Step 15 (`scripts/collect-recovery-candidates.sh` 経由) と `/audit stats --retention` Section 10 が `/verify` 実行のたびに全文を読み込むため、読み込みコストが際限なく増加する。

兄弟ファイルの `modules/orchestration-fallbacks.md` には `docs/reports/orchestration-fallbacks-archive.md` という既存のアーカイブ機構 (#1180) があるが、その退避基準 (発火実績ゼロ AND live 参照元ゼロ AND 手順として無効化 = 3 軸ゼロ) は「使われなくなった一般手順」を退役させるためのもので、`orchestration-recoveries.md` は個々のエントリが実際に起きた事象の記録 (インシデントログ) であり「無効化」される性質のものではない。そのため本 Issue では、`orchestration-fallbacks-archive.md` と同じ**アーカイブ機構の形** (単一の追記専用アーカイブファイル、新しい順、フル構造を verbatim 保持) を踏襲しつつ、退避基準はインシデントログに適した**サイズ上限 + 経過エントリ数によるローテーション**に置き換える。

`collect-recovery-candidates.sh` の頻度集計ロジックを読んだ結果、この方式は集計を破壊しない: 同スクリプトは group-key ごとに、解決済み (CLOSED) Issue の `closedAt` またはログ内の最新 `起票済み #N` エントリのタイムスタンプを cutoff とし、それ以前のエントリを既にカウントから除外している。ローテーションで live ファイルから退避されるのは常に「ファイル末尾側 = 最も古いエントリ群」であり、直近の再発エントリ (cutoff より新しいもの) は必ず live ファイル側に残るため、追跡中の再発検知能力は損なわれない。

## Changed Files

- `docs/reports/orchestration-recoveries.md`: `## Purpose and Role Division` の直後・`## Entry Format` の直前に `## Rotation / Archival Policy` セクションを新設。あわせて、既に 1500 行のトリガーを超えている現状分について初回ローテーションを実施し、最も古い 58 エントリ (`## 2026-07-31 03:08 UTC: manual-recovery-review-rerun` 以降末尾まで) を後述のアーカイブファイルへ退避する
- `docs/reports/orchestration-recoveries-archive.md`: 新規作成。`orchestration-fallbacks-archive.md` と同形式の frontmatter + `## Role` セクション + `## Archived Entries` セクションを持つ。初回ローテーションで退避される 58 エントリを収容する
- `scripts/collect-recovery-candidates.sh`: 冒頭コメントブロックに 1 行、新アーカイブファイルの存在とその集計対象外である旨を追記する (動作変更なし)

Steering Docs sync candidate 横断検索 (`grep -rl "orchestration-recoveries.md"` / `grep -rl "collect-recovery-candidates.sh"` を `docs/` `tests/` `scripts/` `modules/` に実行、`docs/spec/*` `docs/sessions/*` `docs/ja/*` ミラーおよびその他の `docs/reports/*` からの一過的な言及は履歴記録として対象外とした):

- `docs/structure.md:192` (`collect-recovery-candidates.sh` の説明文): [Steering Docs sync candidate] 本 Issue はスクリプトの入出力仕様やパース挙動を変更しないため更新不要と判断したが、`/code` 側で内容を確認すること
- `modules/orchestration-fallbacks.md` (複数箇所, 新規エントリ記録時の `orchestration-recoveries.md` 書き込みに言及): [Steering Docs sync candidate] いずれも「新規エントリの追記」についての記述であり、既存エントリの退避には触れていないため更新不要と判断したが、`/code` 側で内容を確認すること
- `docs/guide/customization.md:87,156` (`recoveries-auto-fire` 設定キーの説明): [Steering Docs sync candidate] 闾値超過時の自動起票という設定意味論自体は変わらないため更新不要と判断したが、`/code` 側で内容を確認すること
- `docs/structure.md:145` (`orchestration-fallbacks.md` の Key Files 行、姉妹アーカイブへの言及): 参考として引用しているのみで本 Issue の変更対象ではないため対象外

## Implementation Steps

1. `docs/reports/orchestration-recoveries.md` の `## Purpose and Role Division` セクション末尾 (`- These files are not long-term storage for cross-Issue knowledge` の直後) から `## Entry Format` の直前に、`## Rotation / Archival Policy` セクションを英語で追加する (このファイル自体が English documentation であり、Spec のみが日本語という言語規約に従う)。内容:
   - **Trigger**: live ファイルの行数が 1500 行を超えたら (`wc -l docs/reports/orchestration-recoveries.md` で確認)。`orchestration-fallbacks-archive.md` と同様、自動化されたフックはなく手動確認 (または `/audit fragility` が偶発的に検知) に依る
   - **Split boundary**: エントリは新しい順に並んでいるため、ファイル末尾側 (最も古いエントリ群) から連続したブロックを、live ファイルの行数がおよそ 800 行に戻るまでアーカイブへ移動する
   - **Archive destination**: `docs/reports/orchestration-recoveries-archive.md` (`orchestration-fallbacks-archive.md` と同じく日付分割しない単一の追記専用アーカイブ)。アーカイブ内も新しい順を維持するため、各ローテーションで移動するブロックはアーカイブの `## Archived Entries` 直下 (先頭) に挿入する
   - **Content preservation**: エントリは `### Context` / `### Diagnosis` / `### Recovery Applied` / `### Outcome` / `### Improvement Candidate` の全構造を verbatim で移動する (要約しない)
   - **Effect on consumers**: `scripts/collect-recovery-candidates.sh` (および `/verify` Step 15、`/audit stats --retention` Section 10) は live ファイルのみを読むため、アーカイブされたエントリは以後の頻度集計から外れる。これは許容されるトレードオフである — 同スクリプトの cutoff ロジックは解決済み (CLOSED) Issue の `closedAt` 以前のエントリを既に除外しており、未解決の group-key の直近エントリは常に live ファイル側に残るため、実際に失われるのは「既にカウント対象外」か「十分古く直近再発の判定に寄与しない」エントリのみである (→ 受け入れ条件 1)

2. `docs/reports/orchestration-recoveries-archive.md` を新規作成する。frontmatter は `type: report`、`description: Archive for docs/reports/orchestration-recoveries.md entries rotated out once the live file exceeds its line-count trigger. Newest-archived-first. Not consumed by scripts/collect-recovery-candidates.sh or any other runtime script.`。続けて `# Orchestration Recoveries Archive` 見出し、1 段落の役割説明、`orchestration-fallbacks-archive.md` の `## Role` セクションと同形式の `## Role` セクション (Scope / Role / Not consumed by / Not subject to の 4 項目)、空の `## Archived Entries` セクションを配置する (→ 受け入れ条件 1)

3. 初回ローテーションを実施する (after 1, 2): `docs/reports/orchestration-recoveries.md` の `## 2026-07-31 03:08 UTC: manual-recovery-review-rerun` (このエントリを含む) からファイル末尾の最終エントリ (`## 2026-06-03 16:15 UTC: verify worktree FF merge failed (concurrent push advanced base)`) までの範囲 — 92 エントリ中、最も古い 58 エントリ — を、`docs/reports/orchestration-recoveries-archive.md` の `## Archived Entries` 直下へ verbatim で移動する。live ファイル側にはそれ以外の直近 34 エントリ (先頭〜`## 2026-07-31 19:12 UTC: manual-recovery-commit-push` まで) のみが残る。移動対象の範囲は本文中の見出しテキストで特定すること (行番号はエントリ追加により変動するため使わない) (→ 受け入れ条件 1、Purpose)

4. `scripts/collect-recovery-candidates.sh` の冒頭コメントブロック (既存の `# Note (Issue #1153): ...` 等の並び) に 1 行、`docs/reports/orchestration-recoveries-archive.md` へローテーションされたエントリはこのスクリプトの入力範囲外であり集計対象から外れる旨を追記する。`docs/reports/orchestration-recoveries.md` の `## Rotation / Archival Policy` セクションを参照させる。コメント追記のみで動作変更はない (→ 受け入れ条件 1)

5. 非破壊性のスポットチェック (after 3): Step 3 の編集前後で `bash scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 1` をそれぞれ実行し、出力を diff する。カウントが変化した group-key があれば、それが「アーカイブへ移動したエントリのみに起因する変化」であり、live 側に残っている未解決 group-key のカウントが失われていないことを確認する。比較結果を本 Spec の `## Notes` に記録する (Post-merge 受け入れ条件が次回実際のローテーション発火時に求める確認と同じ手順であり、その先例として残す)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/orchestration-recoveries.md or its consuming scripts (e.g. scripts/collect-recovery-candidates.sh) document a rotation/archival policy (size cap, date-based split, or equivalent) analogous to orchestration-fallbacks-archive.md, so the file's per-/verify-run read cost does not grow unbounded" --> ローテーション/アーカイブ方針が実装または明記されている

### Post-merge

- 実際にアーカイブ方針が発火した際、`scripts/collect-recovery-candidates.sh` の集計結果 (group-key の再発カウント) が退避前後で破壊されないことを確認 (verify-type: opportunistic)

## Notes

### Auto-Resolve Log (non-interactive mode)

- **ローテーションの数値パラメータ (トリガー 1500 行 / 目標 800 行程度)**: 本リポジトリに既存の行数上限の前例はない (`grep` で確認済み)。Issue 本文が示す成長率 (約 475 行/月) から、次回ローテーションまで約 1.5 か月の猶予が生まれる値として選定した。今回の初回ローテーションの実際の境界 (エントリ #35, 2026-07-31 03:08 UTC) は目標 800 行に近い 777 行に収まった
- **ローテーションを自動化せず手動運用とした判断**: 直接のモデルである `orchestration-fallbacks-archive.md` 自身の導入 (#1180) も、`/verify` や `/audit` へのフック追加ではなく `/audit fragility` の単発検知を契機とした手動退避だった。本 Issue も同じ前例に倣い、`skills/verify/SKILL.md` や `skills/audit/SKILL.md` への自動トリガー組み込みは行わない。Size M / light depth のスコープを超えると判断したための選択であり、手動運用が機能しないと分かった場合は別 Issue でのフック化を検討する
- **Post-merge AC の `verify-type: opportunistic` タグを変更しなかった判断**: `modules/verify-classifier.md` の opportunistic 判定基準 (「`/skill-name` 実行時に X を確認する」という、`opportunistic-search.sh` がディスパッチ可能な named event に紐づくパターン) に照らすと、本 AC の発火契機である「アーカイブ方針が実際に発火したとき」は上記の通りローテーションを手動運用としたため対応する自動イベントが存在せず、厳密には整合しない。とはいえ Issue 本文で既に付与されたタグを本 Spec (light depth) の判断だけで再分類するのは影響範囲の広い決定であり見送った。実務上は、次回ローテーションを実施する者が本 Spec の Implementation Step 5 と同じ手順 (前後の `collect-recovery-candidates.sh` 出力比較) を再実行することで、この AC が求める確認を満たせる

### Steering Docs sync candidate の確認結果

`docs/structure.md` / `docs/guide/customization.md` / `modules/orchestration-fallbacks.md` / `modules/verify-classifier.md` / `modules/verify-executor.md` / `docs/workflow.md` / `docs/tech.md` の該当箇所を確認したが、いずれも「新規エントリの追記」や「頻度集計の設定意味論」についての記述であり、既存エントリの退避 (本 Issue の変更) によって不正確になるものはなかった。`README.md` にも `collect-recovery-candidates.sh` / `orchestration-recoveries.md` への言及はなかった (grep 確認済み)

### docs/structure.md への新規ファイル追記を見送った判断

直接の前例である `orchestration-fallbacks-archive.md` は、導入時 (#1180) も現在も `docs/structure.md` の Directory Layout / Key Files に個別の行を持たない (`modules/orchestration-fallbacks.md` の説明文中に参照が 1 箇所あるのみ)。同じ前例に倣い、`docs/reports/orchestration-recoveries-archive.md` についても `docs/structure.md` への新規行追加は行わない

### Step 5 スポットチェックの記録欄 (`/code` が実施後に追記する)

- ローテーション前の `collect-recovery-candidates.sh` 出力: 32 group-key、合計 92 エントリを集計 (`code-pr-tier3-recovery: 3`, `manual-recovery-commit-push: 2`, `manual-recovery-push-only: 2`, `manual-recovery-push-and-pr: 2`, `manual-recovery-respawn-skip-code: 2`, `manual-recovery-merge-rerun/pre-merge-ac-command-unverifiable: 2`, `manual-recovery-manual-recovery-review-uncommitted-work/background-notification-wait: 2`, `manual-recovery-review-rerun/ci-infra-outage-during-ci-wait: 2`, その他は 1 件ずつ)
- ローテーション後の `collect-recovery-candidates.sh` 出力: 21 group-key に減少。カウントが変化したのは `code-pr-tier3-recovery` (3→1)、`manual-recovery-commit-push` (2→1) の 2 件のみ。以下 11 group-key はカウント 0 (集計結果から消滅): `manual-recovery-pr-create`, `manual-recovery-push-only` (bare key。cause-suffix 付きの `manual-recovery-push-only/background-notification-wait` は影響なし), `manual-recovery-push-and-pr`, `manual-recovery-completion-override`, `manual-recovery-respawn-skip-code`, `manual-recovery-skip-forward`, `nested-verify-committed-to-review-worktree`, `Silent no-op when prior Issue's merge already satisfied AC`, `silent-no-op recovered via wrapper-anomaly Tier 2 retry`, `false-positive silent-no-op on patch route`, `watchdog kill before PR creation; recovery sub-agent op unsupported`
- 差分の説明: カウントが変化した 2 group-key (`code-pr-tier3-recovery`, `manual-recovery-commit-push`) は、いずれも live ファイル側に直近発生分 (それぞれ 1 件) が残存しており、減少分はすべて今回アーカイブされた 58 エントリ (2026-06-03〜2026-07-31 03:08) 側の古い occurrence だった。カウントが 0 になった 11 group-key はいずれも該当 occurrence の全件がアーカイブ範囲に含まれていたケースで、live ファイル側に残る occurrence は無い。未解決 (直近再発が追跡対象) の group-key で live 側のカウントが失われたものはなく、Purpose および受け入れ条件 1 が求める非破壊性を満たすことを確認した。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜5 を Spec の記載順どおりに実施した。ステップの並べ替え・省略・統合は発生していない

### Design Gaps/Ambiguities
- N/A — Spec の Notes (Auto-Resolve Log、Steering Docs sync candidate 確認結果) が実装時の判断点を事前に解消しており、実装フェーズで新たに発見された曖昧点はなかった

### Rework
- 58 エントリのブロック (1183 行) をライブファイルからアーカイブファイルへ逐語移動する際、当初 Bash heredoc/リダイレクトで `.tmp/` に中間ファイルを作成してしまい (グローバル規約「一時ファイルは Write ツールで作成」に反する)、気づいた時点で削除してやり直した。最終的には、1183 行を Edit ツールの `old_string` に手動転記すると transcription drift のリスクがあるため、`git show HEAD:<path> | sed -n '<range>p'` で未コミットの元ファイル (このセッションではまだ何もコミットしていなかったため HEAD に原本が残っていた) からバイト完全に抽出し、`sed -i` でライブファイル側を切り詰める方式に切り替えた。逐語保持が受け入れ条件の前提 (要約しない) である大きなブロック移動では、Edit ツールでの手動転記より `git show` + `sed` による機械的な抽出のほうが安全であるという教訓は今後の同種タスク (アーカイブ/ローテーション実装) に有用

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Steps 1〜5 をそのまま実施し、逸脱なし (詳細は Code Retrospective 参照)
- 58 エントリの逐語移動は Edit ツールでの手動転記ではなく `git show HEAD:<path> | sed -n` + `sed -i` による機械的抽出で実施し、transcription drift リスクを排除した
- Pre-merge AC (rubric) は実装内容 (Rotation / Archival Policy セクション新設) に照らして PASS と判定し、Issue のチェックボックスを更新済み

### Deferred Items
- Post-merge AC (`verify-type: opportunistic`、次回ローテーション発火時の非破壊性確認) は今回未発火のため未検証のまま。次回ローテーション実施者が Spec Implementation Step 5 と同じ手順 (前後の `collect-recovery-candidates.sh` 出力比較) を再実行することで満たされる

### Notes for Next Phase
- 本 Issue は patch route (直接 main へコミット) のため PR は作成されない。`/verify` は origin/main 上のコミット `chore: recoveries.md にローテーション/アーカイブ方針を導入 (closes #1408)` を対象に Pre-merge AC を再確認すること
- テストは `bats --jobs 18 tests/` で全 1887 件 PASS 済み (Behavioral Change Detection により `scripts/collect-recovery-candidates.sh` を参照する他テストファイルの存在からフルスイート実行と判定)
- `docs/reports/orchestration-recoveries-archive.md` は新規ファイルであり `docs/structure.md` への追記は前例 (`orchestration-fallbacks-archive.md`) に倣い見送っている
