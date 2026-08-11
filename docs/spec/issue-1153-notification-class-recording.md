# Issue #1153: auto: --write-manual-recovery に task notification 文言を記録し harness-stop / external-signal を判別

## Overview

親 `/auto` セッションが external kill を検知して respawn する際、手元にある task notification の文言を **分類 (classification) として** recovery 記録経路に残す。`wrapper_exit_code` が構造的に取得不能 (11/11 が `unknown`、2026-07-15 Update で確定) であるのに対し、notification は別チャネルであり親セッションが respawn 判断時点で受信済みである。

分類語彙は 4 値に固定する **(exhaustive)**:

| 値 | 意味 |
|----|------|
| `harness-stop` | 文言から harness 自身の task-kill path による停止と判別できた |
| `external-signal` | 文言から真に外部由来のシグナルと判別できた (`failed with exit code N` 等) |
| `indeterminate` | 文言は確認できたが判別情報を含まない (`killed` / "was stopped" のみで数値 exit code なし) |
| `unobserved` | 文言そのものを確認できなかった |

フラグ自体を省略した場合は上記 4 値のいずれとも異なる `unspecified` として記録され、「文言を確認できなかった (`unobserved`)」と「そもそも記録経路に渡されなかった (`unspecified`)」を区別できる。

本 Issue は **観測軸の追加のみ**であり、respawn するかどうかの判定閾値 (`detect-external-kill.sh` の 137 単独 / 143・unknown + トレーラ欠如 + `wrapper_exit` 欠如) は一切変更しない。

## Changed Files

- `scripts/run-auto-sub.sh`: `--write-manual-recovery` に `--notification CLASS` を追加 (引数パース / `_validate_recovery_args` の語彙検証 / `_write_manual_recovery_to_recoveries_log()` の `### Diagnosis` 行 / `emit_event` フィールド) — bash 3.2+ 互換
- `scripts/emit-event.sh`: `manual_intervention` スキーマコメントに `notification_class=<...>` を追記 — bash 3.2+ 互換
- `docs/reports/orchestration-recoveries.md`: `## Entry Format` の `### Diagnosis` ブロックに `- notification: <class>` を追加、`## Field Definitions` に `notification` 行を追加
- `skills/auto/SKILL.md`: Step 6 External kill pre-check に文言捕捉手順を追加 + `--write-manual-recovery` シグネチャ 2 箇所 (Step 6 Recording / Manual recovery hand-off) に `[--notification CLASS]` を追記
- `modules/orchestration-fallbacks.md`: シグネチャ 2 箇所 (`#manual-recovery-spec-write` の Fallback Steps step 1、"Manual path: recoveries.md + manual_intervention event") と step 3 の記録先説明、Rationale への `#1153` 追記
- `docs/workflow.md`: "External kill respawn" 段落のシグネチャと説明に `--notification` を追記
- `docs/ja/workflow.md`: 上記のミラー同期 (`docs/translation-workflow.md` の Sync Procedure)
- `docs/tech.md`: "Parent-session manual respawn" 段落のフラグ列挙に `--notification` を追記
- `docs/ja/tech.md`: 上記のミラー同期
- `tests/run-auto-sub.bats`: `--notification` の 4 テストを追加 (Implementation Steps 9 参照)

**変更不要 (grep / 実装読解で確認済み)**:

- `scripts/collect-recovery-candidates.sh`: パースループ (L195-221) は `^- cause: ` / `^- 起票済み #` / `^- N/A` の 3 パターンのみに一致する行単位処理であり、`- notification: <class>` 行は inert。group key (`<symptom-short>[/<cause-slug>]`) も不変
- `scripts/get-auto-session-report.sh`: L281-282 は `.event == "manual_intervention"` の件数を数えるのみでフィールドを読まないため、フィールド追加は後方互換
- `skills/verify/SKILL.md` L866: backfill 呼び出しは merge 後の事後記録で、notification 文言は事後復元不能。同行は任意フラグを列挙していないためシグネチャが陳腐化しない
- `modules/event-emission.md` L191: `--write-manual-recovery` を PGID ポインタ誤帰属の履歴文脈で言及するのみで、シグネチャ / フィールド一覧を含まない
- `docs/guide/customization.md`: `.wholework.yml` の設定キーを追加しないため対象外 (`orchestration-recoveries` の言及は `recoveries-auto-fire` の説明のみ)

**Steering Docs sync candidate** (`/code` が各ファイルを読んで最終判断):

- `docs/structure.md` L190 / `docs/ja/structure.md` の対応行: `collect-recovery-candidates.sh` の group-key 説明が `### Diagnosis` body の `- cause:` 行に言及している。`- notification:` 行が集計に影響しないことを明記するか、現状記述のままで正確かを確認する
- `docs/structure.md` L240 / `docs/ja/structure.md` L232 (`scripts/run-auto-sub.sh` の 1 行説明): フラグ粒度の記述を持たないため陳腐化しない見込みだが、`/code` 時に再確認する
- `scripts/collect-recovery-candidates.sh` の冒頭コメント L5-14 (group-key の説明): `- notification:` 行を無視する旨の 1 行を足すか判断する

**測定スコープ**: 上記の「変更不要」判定は、リポジトリルートから `grep -rn -- "--write-manual-recovery" scripts/ skills/ modules/ tests/ docs/` および `grep -rn "manual_intervention" docs/ tests/ scripts/ modules/ skills/` を実行し、`docs/spec/` (disposable) と `docs/sessions/` (履歴記録) を除外した結果に基づく。

## Implementation Steps

1. `scripts/run-auto-sub.sh`: `--write-manual-recovery` の引数パースループ (`while [[ $# -gt 0 ]]` の `case`) に `--notification` の case arm を `--diagnosis` arm の直後に追加する。値欠落時は `Error: --notification requires a value` を stderr に出して exit 1 (既存 2 フラグと同形)。positional index (`_mr_pos_idx`) の扱いは変更しない。ローカル変数 `_mr_notification=""` を `_mr_diagnosis=""` の直後で初期化する — bash 3.2+ 互換 (→ 受入基準 1)

2. `scripts/run-auto-sub.sh`: `_validate_recovery_args` に 5 番目の位置パラメータ NOTIFICATION を追加する。非空のときのみ検証し、`harness-stop` / `external-signal` / `indeterminate` / `unobserved` の 4 値 **(exhaustive)** と完全一致しなければ `_validate_recovery_args: invalid notification: '<value>'` を stderr に出して return 1。関数冒頭の `# Usage: _validate_recovery_args ISSUE [PHASE] [RECOVERY_TYPE] [EXIT_CODE]` コメントも更新する。唯一の呼び出し箇所 (`--write-manual-recovery` dispatch 内、`source "$SCRIPT_DIR/emit-event.sh"` の直前) に `"$_mr_notification"` を第 5 引数として渡す (after 1) (→ 受入基準 1)

3. `scripts/run-auto-sub.sh`: `_write_manual_recovery_to_recoveries_log()` に 7 番目の位置パラメータ NOTIFICATION を追加し、Python heredoc へは既存の `WW_CAUSE` / `WW_DIAGNOSIS` と同じ **環境変数チャネル** (`WW_NOTIFICATION`) で渡す (heredoc のソーステキストに補間しない — #1123 の SyntaxError silent-skip 回帰を防ぐ)。`_diagnosis_body` の組み立てを「順序付き行リスト」に書き換える: (a) `cause` が非空なら `- cause: <slug>`、(b) `notification` が非空なら `- notification: <class>`、(c) 最後に 1 行のテキスト行 (`_diagnosis` が非空ならその値、空なら既存の定型文)。この構成により、既存の 3 ケース (両フラグなし / `--cause` のみ / `--cause`+`--diagnosis`) の出力はバイト等価のまま保たれる (after 2) (→ 受入基準 1, 2)

4. `scripts/run-auto-sub.sh`: dispatch 末尾の `emit_event "manual_intervention" ...` 呼び出しに `"notification_class=${_mr_notification:-unspecified}"` を追加する (`intervention_type=...` の後ろ)。`unspecified` はフラグ省略を表し、語彙値 `unobserved` (文言を確認できなかった) とは意図的に別値である (after 1) (→ 受入基準 2)

5. `scripts/emit-event.sh`: 冒頭の `manual_intervention` スキーマコメントブロックに `notification_class=<...>` の行を `intervention_type=<type>` の後ろに追加し、`harness-stop | external-signal | indeterminate | unobserved | unspecified` **(exhaustive)** と各値の意味を 1 行ずつ記述する (parallel with 1, 2, 3, 4) (→ 受入基準 2)

6. `docs/reports/orchestration-recoveries.md`: `## Entry Format` のコードフェンス内 `### Diagnosis` ブロックに `- notification: <class>` 行を `- cause: <slug>` 行の直後 (optional 注記つき) で追加し、`## Field Definitions` テーブルに `notification` 行を追加する。行の意味は「manual recovery 経路でのみ書かれる。行が存在しない = フラグ未指定。値は 4 語彙 **(exhaustive)**。frequency grouping には影響しない」 (parallel with 1-5) (→ 受入基準 2)

7. `skills/auto/SKILL.md` Step 6 の "External kill pre-check": **Response** 箇条書きと **Recording (mandatory)** 箇条書きの間に、respawn 前の文言捕捉手順を追加する。内容は (a) 停止したバックグラウンドタスクの task notification の `status` / `summary` を確認する、(b) `failed with exit code N` 形式なら `external-signal`、`killed` / "was stopped" のみで数値 exit code を含まないなら `indeterminate`、(c) 文言そのものを確認できなければ `unobserved` を渡す (省略と区別するため必ず渡す)、(d) 生の文言は `--diagnosis` に 1 行で渡す。あわせて同 Step の Recording コードブロックと L1084/L1089 付近の "Manual recovery hand-off" 段落のシグネチャに `[--notification CLASS]` を追記する。SKILL.md 本文では半角感嘆符とトリプルバッククォートを使用しない (`validate-skill-syntax.py` 制約) (parallel with 1-6) (→ 受入基準 3)

8. `modules/orchestration-fallbacks.md`: `#manual-recovery-spec-write` の Fallback Steps step 1 のコードブロックと "Manual path: recoveries.md + manual_intervention event" のコードブロック、計 2 箇所のシグネチャに `[--notification CLASS]` を追記し、step 1 の説明文に 4 語彙と `unspecified` の区別を 1 文で加える。step 3 の 2 記録先の説明に notification 分類が両方へ落ちることを追記し、Rationale に "Extended in Issue #1153" の箇条書きを追加する (parallel with 1-7) (→ 受入基準 2, 3)

9. `tests/run-auto-sub.bats`: 既存の `--cause` / `--diagnosis` テスト群と同じ mock (`$MOCK_DIR/git`, `$MOCK_DIR/gh`) 構成で 4 テストを追加する — (a) `--notification harness-stop` が recoveries log に `- notification: harness-stop` 行を書き、`$EMIT_LOG` に `notification_class=harness-stop` を出す、(b) `--cause` と `--notification` の併用で `- cause:` と `- notification:` の両行が出る、(c) `--notification` 省略時は `- notification:` 行が書かれず `notification_class=unspecified` が出る (既存挙動の保持)、(d) `--notification bogus` と値なしの `--notification` がいずれも非 0 で終了し診断メッセージを出す (after 1, 2, 3, 4) (→ 受入基準 4)

10. ドキュメント同期: `docs/workflow.md` の "External kill respawn" 段落と `docs/tech.md` の "Parent-session manual respawn" 段落のフラグ列挙・シグネチャに `--notification CLASS` を追記し、`docs/translation-workflow.md` の Sync Procedure に従って `docs/ja/workflow.md` / `docs/ja/tech.md` の対応段落を日本語で同期する (コードフェンス数の一致も確認する)。あわせて Changed Files の Steering Docs sync candidate 3 件を読んで採否を判断する (after 1-8) (→ 受入基準 5)

## Alternatives Considered

- **生の文言を専用フィールド (`--notification-text TEXT`) で保存する** — 不採用。既存の `--diagnosis TEXT` が同じ自由記述チャネルとして機能し、#1123 の環境変数渡し修正により改行を含む文言も安全に保存できる。フラグを 2 本追加すると、集計上の価値が不明なフィールドが `### Diagnosis` に増えるだけになる。Issue Notes の「未知の文言は `unobserved` ではなく生の文言を残せる設計」という要請は、(a) `indeterminate` を `unobserved` と別値にしたこと、(b) 生文言を `--diagnosis` に渡す手順を SKILL.md Step 6 に明記すること、の 2 点で満たす
- **分類を `--cause` の slug として表現し新フラグを追加しない** — 不採用。`--cause` の値は `_find_known_recoveries_issue` の group key (`<symptom-short>/<cause-slug>`) に組み込まれるため、通知分類を混ぜると同一 root cause の occurrence が 4 グループに分裂し、`collect-recovery-candidates.sh` の頻度検知が壊れる
- **`scripts/detect-external-kill.sh` に分類を補助証拠として渡す** (Issue の Implementation Outline 項目 3 の「要判断」) — 不採用。本 Issue の既存方針は判定閾値を動かさないことであり、判定に影響しない入力を追加してもデッドサーフェスになる。2026-08-07 の実例が示したとおり `killed` / "was stopped" 文言は harness-stop と external-signal を区別しないため、そもそも現時点の分類は判定材料として不十分でもある
- **`scripts/get-auto-session-report.sh` に notification 分類の内訳 Metrics 行を追加する** — 不採用。受入基準は記録先 2 箇所のみを要求しており、分布の読み出しは `docs/reports/orchestration-recoveries.md` の `- notification:` 行を grep すれば足りる。データが数件貯まってから別 Issue で判断する

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の --write-manual-recovery に、親セッションが観測した task notification の分類を渡す任意引数が追加されており、引数を省略した場合の既存挙動が変わらないことが実装またはテストから確認できる" --> notification 分類の記録経路が任意引数として追加されている
- <!-- verify: rubric "渡された notification 分類が manual_intervention イベントと docs/reports/orchestration-recoveries.md のエントリの両方に機械可読な形で残ることが、実装またはテストから確認できる" --> 分類が 2 つの記録先に機械可読な形で残る
- <!-- verify: rubric "skills/auto/SKILL.md の Step 6 (External kill pre-check) に、respawn 前に task notification の文言を確認して記録経路に渡す手順が追加されており、文言が確認できない場合の扱い (unobserved) と、文言は確認できたが harness-stop / external-signal のいずれか判別できない場合の扱い (indeterminate) の両方が明記されている" --> 親セッション側の捕捉手順が SKILL.md に明記されている
- <!-- verify: command "bats tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` が PASS する
- <!-- verify: rubric "docs/structure.md / docs/workflow.md / docs/tech.md のうち本変更で記述が古くなる箇所が更新され、docs/ja/ 側のミラーも同期している" --> ドキュメントと日本語ミラーが同期している

### Post-merge

- 次に external kill が観測された際、記録された notification 分類が `docs/reports/external-kill-investigation.md` に Update として反映されている <!-- verify-type: manual -->

## Tool Dependencies

### Bash Command Patterns

- none (実装に必要な `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*` は `skills/auto/SKILL.md` / `skills/verify/SKILL.md` の `allowed-tools` に既に登録済み — allowed-tools impact chain check の結果は Notes 参照)

### Built-in Tools

- none (Read / Edit / Write / Grep / Glob はいずれも登録済み)

### MCP Tools

- none

## Uncertainty

- **上流 (Claude Code harness) の notification 文言はバージョン更新で変化しうる**
  - **検証方法**: 文言のパターンマッチをスクリプト側に持たせない設計にすることで回避する。分類判断は親セッション (LLM) が行い、スクリプトは 4 値の語彙のみを検証する。上流文言が変化した場合に更新が必要なのは `skills/auto/SKILL.md` Step 6 の例示のみで、`scripts/run-auto-sub.sh` の変更は不要
  - **影響範囲**: Implementation Steps 7 のみ (Steps 1-4 の語彙検証は文言に依存しない)
- **`- notification:` 行が `collect-recovery-candidates.sh` の集計を壊さないこと** — **解決済み**。`scripts/collect-recovery-candidates.sh` L195-221 のパースループを読解し、`^- cause: ` / `^- 起票済み #[0-9]+` / `^- N/A` の 3 パターンのみに一致する行単位処理であることを確認した。語彙 4 値のいずれもこれらの接頭辞に一致しないため inert

## Notes

### 判定閾値は動かさない

本 Issue は観測軸の追加であり、respawn するかどうかの判断ロジック (`detect-external-kill.sh` の検知シグネチャ) は現状維持。誤検出時も `code_phase_milestone` チェックポイントで冪等に再開できるという既存の fail-safe 設計 (#1014) を崩さない。

### `unspecified` と `unobserved` の使い分け

| 状況 | recoveries log | `manual_intervention` イベント |
|------|----------------|-------------------------------|
| `--notification` を渡さなかった | `- notification:` 行なし | `notification_class=unspecified` |
| 文言を確認できなかった | `- notification: unobserved` | `notification_class=unobserved` |

イベント側は既存の `wrapper_exit_code=${_mr_exit_code:-unknown}` と同じく必ずフィールドを出力する (JSONL の欠損フィールドを後段で扱うより一貫する)。recoveries log 側は `- cause:` と同じく「フラグ未指定なら行を書かない」に揃える。

### `_diagnosis_body` 再構成の副作用 (意図的)

現行実装では `--diagnosis` を `--cause` なしで渡すとテキストが黙って捨てられる (`if _cause:` の else 分岐が `_diagnosis` を参照しない)。Implementation Step 3 の行リスト化により、この経路でも `--diagnosis` の値が出力されるようになる。既存テストが依存する 3 ケース (両フラグなし / `--cause` のみ / `--cause`+`--diagnosis`) の出力はバイト等価であり、回帰ではない。

### 追加の判別軸は本 Issue のスコープ外

2026-08-07 の実例コメントで挙げられた 3 軸 — (1) 数値 exit code の有無、(2) 停止までの経過時間 vs watchdog 閾値、(3) 起動方法 (`run_in_background` かどうか) — は判別ロジックそのものを強化する候補だが、判定閾値を変えない本 Issue の方針とは別の変更 (判別アルゴリズムの再設計) になるため今回は含めない。将来これらを組み込む場合は別 Issue として起票する。

### post-merge AC を `verify-type: manual` のまま維持した理由

`modules/verify-patterns.md` §11 の quick reference に照らして `file_contains` / `rubric` への置換を検討したが、この AC は「次に external kill が観測された際」という発生依存の条件であり、kill が起きていない期間に機械検証すると必ず FAIL する。`observation` タイプへの変更も検討したが、2026-08-03 以降 kill は再現しておらず (Issue Notes)、`modules/verify-classifier.md` が警告する「解決経路を持たない observation が SKIPPED 通知を無限に蓄積する」病理 (#1026) を招く。`manual` のまま維持し、`/audit stats --retention` の retire-proposal escalation に委ねる。

### rubric に `file_contains` を併記しなかった理由

`modules/verify-patterns.md` §9 は rubric の grader 記述に定数名・閾値が含まれる場合に `file_contains` の併記を推奨するが、本 Issue の rubric 3 が挙げる `unobserved` / `indeterminate` は「値が静かにドリフトしうる定数」ではなく語彙そのものである。4 語彙が SKILL.md 本文に存在することを `file_contains` で確認しても、AC が本当に問うている「捕捉手順が明記されているか」は検証できず、trivial PASS を増やすだけになる。`docs/spec` 側でも Issue body 側でも AC を書き換えない (`modules/verify-patterns.md` §18: Issue body が verify command の SSoT)。

### allowed-tools impact chain check (Case 2: `modules/*.md` 変更)

`modules/orchestration-fallbacks.md` の変更差分は `scripts/run-auto-sub.sh` パスを含むため lightweight gate に一致する。読み手を `grep -rl "modules/orchestration-fallbacks\.md" skills/*/SKILL.md` で列挙した結果は `skills/auto/SKILL.md` と `skills/verify/SKILL.md` の 2 件 **(exhaustive)** で、両方とも `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*` をリテラルで保持している。ギャップなし。

### skill-dev 制約 (`validate-skill-syntax.py`)

`skills/auto/SKILL.md` に本文を追記するため、半角感嘆符とトリプルバッククォートを本文 (コードフェンス外) に含めない。追加する語彙リストには **(exhaustive)** マーカーを付ける。

### Auto-Resolve Log (non-interactive mode)

本 Spec は `--non-interactive` で実行された。設計上の判断はすべてモデル判断で自動解決した (Step 7 の ambiguity 解決対象は下記 3 点。いずれも Alternatives Considered に判断根拠を記載):

1. **生の文言を保存するか分類のみか** (Issue Implementation Outline 項目 1 の「Spec で決める」) → 分類は新フラグ `--notification`、生文言は既存の `--diagnosis`。理由: 集計しやすさ (固定語彙) と文言ドリフト耐性 (自由記述) を既存フラグ 1 本の追加で両立できる
2. **`detect-external-kill.sh` へ接続するか** (項目 3 の「要判断」) → 接続しない。理由: 判定閾値を動かさない方針に整合し、判定に影響しない入力はデッドサーフェスになる
3. **`unspecified` を導入するか** → 導入する。理由: Issue の「省略と区別できるようにする」要求を、イベント側フィールドを常時出力する既存慣行 (`wrapper_exit_code=...:-unknown`) と衝突させずに満たせる

### Issue body と実装の矛盾検出

矛盾は検出されなかった。Issue body の前提 (`--cause` / `--diagnosis` が #1123 で追加済み、記録先が `manual_intervention` イベントと `orchestration-recoveries.md` の 2 箇所、`collect-recovery-candidates.sh` が `- cause:` 行で group key を作る) はいずれも実装と一致することを `scripts/run-auto-sub.sh` L212-390 および `scripts/collect-recovery-candidates.sh` L195-221 の読解で確認した。

## Consumed Comments

| login | authorAssociation | trust tier | intent summary | URL |
|-------|-------------------|------------|----------------|-----|
| saito | MEMBER | first-class | `/issue` フェーズの Issue Retrospective。`indeterminate` 語彙追加の auto-resolve 判断、判定閾値を動かさない方針の維持、AC3 ルーブリックへの `indeterminate` 明記を記録 | https://github.com/saitoco/wholework/issues/1153#issuecomment-5247533556 |

cutoff: 2026-08-11T00:13:10Z (直近の `phase/*` ラベル付与時刻)。cutoff 以前の 2026-08-07 コメント (issuecomment-5218189694) は Issue body の「2026-08-07 追記」として本文に反映済みのため、本 Spec でも前提として参照している。
