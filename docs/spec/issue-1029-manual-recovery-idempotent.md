# Issue #1029: run-auto-sub: --write-manual-recovery の部分完了後再実行を冪等化

## Consumed Comments

| login | authorAssociation | trust tier | intent | URL |
|-------|--------------------|-----------|--------|-----|
| saito | MEMBER | first-class | Issue Retrospective (`/issue 1029 --non-interactive`)。Background の実装記述 (`_write_manual_recovery_to_spec` は open PR 時のみ Spec 書き込みをスキップ、`_write_manual_recovery_to_recoveries_log` は PR 状態に関わらず常に追記) を実コードと突合し一致を確認。Auto-Resolved Ambiguity Points 2件 (`manual_intervention` イベント再発火はスコープ外／dedup 時間窓は `/spec` に委譲) を記録。Size=S のため sub-issue 分割評価は対象外 | https://github.com/saitoco/wholework/issues/1029#issuecomment-5031992097 |

`/code` フェーズ (cutoff: 2026-07-21T09:08:09Z、`phase/ready` ラベル付与時刻): 新規コメントなし。

## Overview

`run-auto-sub.sh --write-manual-recovery ISSUE PHASE RECOVERY_TYPE` は回復記録を (1) Spec の `## Auto Retrospective`、(2) `docs/reports/orchestration-recoveries.md`、(3) `manual_intervention` イベントの3箇所に書き込む。対象 Issue に open PR が存在する場合、(1) は self-conflict 回避のためスキップされるが (2)(3) は無条件に書き込まれる。案内メッセージに従い PR マージ後に同一引数で再実行すると (1) は今度は成功するが、(2) には dedup チェックがないため同一イベントが重複して追記される。本 Issue は `_write_manual_recovery_to_recoveries_log()` に、同一イベント (同一 Issue・phase・recovery type・近接タイムスタンプ) の既存エントリを検出して追記をスキップする dedup チェックを追加し、`--write-manual-recovery` 全体を「部分完了 → 再実行」シナリオに対して冪等にする。

## Reproduction Steps

1. `run-auto-sub.sh --write-manual-recovery ISSUE PHASE RECOVERY_TYPE` 呼び出し時点で対象 Issue に open PR が存在する。
2. `_write_manual_recovery_to_spec()` (`scripts/run-auto-sub.sh:125-179`) は self-conflict 回避のため Spec への書き込みをスキップし、warning を stderr に出力する ("Retry --write-manual-recovery after PR #<N> is merged.")。
3. `_write_manual_recovery_to_recoveries_log()` (`scripts/run-auto-sub.sh:242-301`) は open PR の有無に関わらず `docs/reports/orchestration-recoveries.md` へ H2 エントリを無条件に追記する。
4. PR マージ後、案内メッセージに従い同一引数で再実行すると、`_write_manual_recovery_to_spec()` は今度は成功して Spec へ書き込むが、`_write_manual_recovery_to_recoveries_log()` は既存エントリとの重複チェックを持たないため再度 H2 エントリを追記し、同一イベントが2重に記録される。
5. 実例: `docs/reports/orchestration-recoveries.md` に Issue #1020 (phase: code-patch, recovery type: respawn) の内容が完全に同一の H2 エントリが "2026-07-16 04:12 UTC" のタイムスタンプで2件記録されている。

## Root Cause

`_write_manual_recovery_to_spec()` は open PR ガード (`_open_pr_for_issue`) により「1回目は skip、PR マージ後の2回目で初めて成功する」という自然な冪等性を持つ。一方 `_write_manual_recovery_to_recoveries_log()` にはこの種のガードや既存エントリとの照合ロジックが一切存在せず、呼び出されるたびに無条件で新しい H2 エントリを追記する。そのため、案内メッセージに従った正当な再実行が単純に recoveries ログの重複追記を引き起こす。重複エントリは `scripts/collect-recovery-candidates.sh` の symptom-short 頻度カウント (`recoveries-auto-fire` の閾値判定の入力) を不正確にし、誤発火の一因になり得る。

## Changed Files

- `scripts/run-auto-sub.sh`: `_write_manual_recovery_to_recoveries_log()` の既存 Python heredoc に dedup チェックを追加 — bash 側の構文変更なし (dedup ロジックは python3 内に実装するため bash 3.2+ 互換性に影響しない)
- `tests/run-auto-sub.bats`: 「部分完了 → 再実行」シナリオのテストと、dedup ウィンドウ外の別イベントが誤って抑制されないことを確認するテストを追加
- `modules/orchestration-fallbacks.md`: `manual-recovery-spec-write` セクション (Fallback Steps 手順3・Escalation 手順4・Rationale) を更新し、recoveries ログ書き込みが dedup ガード付きになったことを明記

**Steering Docs sync candidate** (`grep -l "run-auto-sub.sh" docs/*.md docs/ja/*.md` 実施済み。以下は候補列挙であり、内容確認の結果いずれも本変更による記述更新は不要と判断 — `--write-manual-recovery` の3箇所書き込み先を高レベルに説明するのみで dedup の詳細には触れていないため):
- `docs/tech.md` / `docs/ja/tech.md`: [Steering Docs sync candidate] 「Parent-session manual respawn」の説明が3箇所書き込みに触れているが dedup 詳細は不要と判断
- `docs/workflow.md` / `docs/ja/workflow.md`: [Steering Docs sync candidate] 「External kill respawn」の説明が `--write-manual-recovery` 呼び出しに触れているが dedup 詳細は不要と判断
- `docs/structure.md` / `docs/migration-notes.md` (および対応する `docs/ja/*`): [Steering Docs sync candidate] `run-auto-sub.sh` への一般的な言及のみで本変更と無関係と判断

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `_write_manual_recovery_to_recoveries_log()` 内の既存 Python heredoc に dedup チェックを追加する。エントリ文字列 (`entry = (...)`) の生成直後・ファイル書き込み (`content = content[:pos] + entry + content[pos:]` / `open(fpath, "w").write(content)`) の直前に、`marker` 以降の既存テキストを走査し、(a) symptom-short が `manual-recovery-${recovery_type}` と一致し、(b) Context 行に `- Issue #${issue}, phase: ${phase}` を含み、(c) H2 見出しのタイムスタンプ (`%Y-%m-%d %H:%M`, UTC) が現在時刻 (`datetime.now(timezone.utc)`) から24時間以内、の3条件をすべて満たす既存エントリが1件でもあれば「重複」と判定する。重複と判定した場合は書き込みをスキップし、代わりに `print()` で情報メッセージ (例: `[#${issue}] [recovery] manual-recovery-${recovery_type} already recorded for issue #${issue} phase ${phase} within the last 24h; skipping duplicate recoveries log entry`) を stdout に出す (heredoc は stderr のみ `2>/dev/null` されているため stdout は呼び出し元に伝播する)。3条件のいずれかを満たさない場合は既存どおり書き込みを行う。heredoc 冒頭に `import re` と `from datetime import datetime, timezone, timedelta` を追加する。書き込みがスキップされた場合、後続の `git -C "$_repo_root" diff --quiet "docs/reports/orchestration-recoveries.md"` は差分なしと判定するため、コミット/プッシュ処理は既存ロジックのまま自然にスキップされ、bash 側の追加分岐は不要。(→ acceptance criteria A)
2. `tests/run-auto-sub.bats` に新規テスト「部分完了 → 再実行で recoveries ログが重複しない」を追加する (after 1)。シナリオ: (a) 1回目呼び出し — `gh` モックが `pr list` に対して open PR (`[{"number":123}]`) を返す状態で `--write-manual-recovery 42 code respawn` を実行し、Spec 書き込みがスキップされ `docs/reports/orchestration-recoveries.md` に `manual-recovery-respawn` の H2 エントリが1件追記されることを確認する。(b) 2回目呼び出し — 同一 `$BATS_TEST_TMPDIR` 上で `gh` モックを `pr list` が `[]` を返すよう再定義し (PR マージ後を模擬)、同一引数 (`--write-manual-recovery 42 code respawn`) で再実行する。assert: Spec ファイルに `Auto Retrospective` / `Manual recovery` が新規追記される (未完了だった書き込み先の補完) こと、かつ `docs/reports/orchestration-recoveries.md` 内の `manual-recovery-respawn` の H2 見出し出現回数が1回目呼び出し後から変わらず1件のままである (重複追記されない) ことを確認する。(→ acceptance criteria A, B)
3. `tests/run-auto-sub.bats` に新規テスト「dedup ウィンドウ外の過去エントリは別イベントとして扱われる」を追加する (after 1)。シナリオ: `docs/reports/orchestration-recoveries.md` に、同一 symptom-short (`manual-recovery-respawn`)・同一 Issue #42・同一 phase (code) だが H2 タイムスタンプが明確に24時間以上前 (例: `2020-01-01 00:00 UTC`) の既存エントリを事前に用意した状態で、open PR なしで `--write-manual-recovery 42 code respawn` を実行する。assert: 新しい H2 エントリが追記され、ファイル内の `manual-recovery-respawn` の H2 見出し出現回数が2件になる (dedup ウィンドウ外の過去エントリは別イベントとして扱われ抑制されない) ことを確認する。(→ acceptance criteria A, B)
4. `modules/orchestration-fallbacks.md` の `manual-recovery-spec-write` セクションを更新する (after 1)。(a) Fallback Steps 手順3の2番目の箇条書き (`_write_manual_recovery_to_recoveries_log()` の説明) にある「written unconditionally regardless of Spec existence」を、「Spec の有無に関わらず書き込まれる (ただし同一 symptom-short + 同一 Issue/phase の既存エントリが24時間以内に見つかった場合は dedup によりスキップされる)」という趣旨に更新する。(b) Escalation 直前の手順4 (open-PR ガードの適用範囲説明) の末尾に、recoveries ログ書き込みは新たに dedup チェックの対象になった旨を追記する。(c) Rationale に本 Issue による dedup 追加の1文を追記し、`manual_intervention` イベントの発火は引き続き無条件のままである点も明記する。(→ documentation consistency)
5. `bats tests/run-auto-sub.bats` を実行し、既存テストと Step 2・3 で追加した新規テストがすべて PASS することを確認する (after 2, 3)。(→ acceptance criteria B)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の --write-manual-recovery が、再実行時に orchestration-recoveries.md 内の既存同一イベントエントリを検出して重複追記をスキップし、未完了の書き込み先のみ補完する" --> 再実行時の recoveries 重複追記が防止される
- <!-- verify: command "bats tests/" --> 既存テストがすべて PASS し、部分完了 → 再実行シナリオのテストが追加されている

### Post-merge

なし

## Notes

- **dedup キーとウィンドウの設計判断 (Issue 本文が `/spec` に委譲した決定)**: dedup キーは Purpose 文言どおり `(Issue, phase, recovery type)` = symptom-short (`manual-recovery-${recovery_type}`) + Context 行 (`- Issue #${issue}, phase: ${phase}`) の組み合わせとした。時間窓は **24時間** とした。理由: 本バグの実際の発生パターンは「open PR で1回目 skip → PR マージ後に案内メッセージに従い同一引数で2回目を実行する」という正当な再実行であり、両呼び出しの間隔は対象 Issue 自身の spec→code→review→merge パイプライン (自動実行だが人間レビューや CI 待ちを含みうる) の所要時間に依存する。24時間は「案内に従った再実行」を確実に同一イベントとして畳み込みつつ、同一 (Issue, phase, recovery type) の組み合わせが数日後に別の独立したインシデントとして再発した場合はこれを別イベントとして記録し続けられる、という両立点として選んだ。より短い窓 (例: 同一分・同一セッション) は再実行の呼び出し元 (親セッション) にセッション相関 ID がなく判定が脆弱になるため採用しなかった。
- **`manual_intervention` イベントの再発火は Issue 本文の Auto-Resolved Ambiguity Points により本 Issue のスコープ外**: dedup ガードは `_write_manual_recovery_to_recoveries_log()` のみに適用し、event emission (`emit_event "manual_intervention" ...`) は引き続き無条件のまま変更しない。
- **`_write_manual_recovery_to_spec()` には dedup ロジックを追加しない**: 本 Issue の実害シナリオ (open PR で1回目 skip → PR マージ後の2回目で初めて成功) では、Spec 書き込みは2回目で初めて完了するため、既存の open-PR ガードが実質的に「未完了の場合のみ書き込む」という補完動作を果たす。3回目以降の重複呼び出しで Spec 側にも重複が生じるケースは Background に記載された実害 (recoveries ログの症状カウント water down) の対象外であり、本 Issue のスコープ外と判断した。
- **ドキュメント同期**: Changed Files の Steering Docs sync candidate は内容確認済みで、いずれも本変更 (内部 dedup ロジックの追加) による更新は不要と判断した。`modules/orchestration-fallbacks.md` の `manual-recovery-spec-write` セクションのみが実際の動作記述を持つため更新対象とした。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜5 を順序通りそのまま実装した。

### Design Gaps/Ambiguities
- N/A — dedup キー・時間窓は Spec Notes の設計判断で既に確定しており、実装時に新たな曖昧点は発生しなかった。

### Rework
- N/A — dedup ロジックはサンドボックス (`/tmp`) での事前検証 (重複スキップ・24時間超の非重複扱いの両方) で一発で意図通り動作し、bats テスト追加後も修正なしで全 PASS した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- dedup チェックは既存 Python heredoc 内に実装し、bash 側の分岐は追加しなかった (Spec Implementation Step 1 の指示通り)。`_symptom_short` の bash 変数をそのまま heredoc に渡して python 側の `symptom_short` と一致させ、文字列生成ロジックの重複を避けた。
- 正規表現による H2 エントリ抽出は `re.DOTALL | re.MULTILINE` + 非貪欲 `(?=\n## |\Z)` の先読みで実装。マーカー直後からの走査で全既存エントリを一度に評価できる。
- `datetime.strptime` のパース失敗は個別に `try/except ValueError: continue` で握りつぶし、1件のエントリの日付形式が壊れていても dedup 走査全体が落ちないようにした (外側の `except Exception: pass` に巻き込まれて書き込み自体がスキップされる事態を避けるため)。

### Deferred Items
- `manual_intervention` イベントの重複発火防止は Issue 本文の Auto-Resolved Ambiguity Points により明示的にスコープ外。
- `_write_manual_recovery_to_spec()` 側への dedup 追加も Spec Notes によりスコープ外 (open-PR ガードが実質的に補完動作を果たすため)。

### Notes for Next Phase
- `/review` では、追加した2件の bats テスト (#55 部分完了→再実行, #56 dedup ウィンドウ外) が dedup ロジックの正例・負例を両方カバーしている点を確認してほしい。
- `scripts/run-auto-sub.sh` は `tests/run-code.bats` / `tests/auto-sub-observability.bats` からも参照されるため、behavioral change detection によりフルスイート (`bats tests/`, 1215件) を実行済み・全 PASS。
