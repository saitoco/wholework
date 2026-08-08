# Issue #1281: recoveries: Tier 2/3 の復旧記録に cause slug を残し原因別の頻度検出を機能させる

## Consumed Comments

No new comments since last phase.

## Overview

`docs/reports/orchestration-recoveries.md` への 3 つの記録経路のうち、Tier 2 (`scripts/apply-fallback.sh`) と Tier 3 (`scripts/spawn-recovery-subagent.sh`) が `### Diagnosis` ブロックに `- cause: <slug>` 行を書いていない。`scripts/collect-recovery-candidates.sh` はこの行を読んで group-key を `<symptom-short>/<cause-slug>` に切り替えるため、行がないエントリは近因が異なっても素の `<symptom-short>` に束ねられる。

本 Issue は 2 経路の書き手に cause slug を出力させる。Tier 2 は既にマッチ済みの symptom anchor をそのまま cause として使えるため 1 行の追加で完結する。Tier 3 は cause 相当のスロットが agent の出力契約に存在しないため、`agents/orchestration-recovery.md` の出力 JSON に `cause` キーを追加し、`scripts/validate-recovery-plan.sh` を対応させ、呼び出し元 2 系統 (bash 経路の `spawn-recovery-subagent.sh`、LLM 経路の `skills/auto/SKILL.md`) を同一コミットで追随させる。

既存エントリへの遡及的な cause 付与は Issue 本文どおりスコープ外。

## Changed Files

- `scripts/apply-fallback.sh`: `write_recovery_entry()` の Python heredoc の `### Diagnosis` ブロック先頭に `- cause: {anchor}` 行を追加 — bash 3.2+ compatible
- `scripts/spawn-recovery-subagent.sh`: `write_recovery_entry()` に PLAN_FILE からの `cause` 抽出・kebab-case 検証・`unclassified` フォールバックを追加し、`### Diagnosis` ブロック先頭に `- cause: {cause}` 行を出力 — bash 3.2+ compatible
- `scripts/validate-recovery-plan.sh`: 任意キー `cause` の検証 (string 型 / `^[a-z0-9]+(-[a-z0-9]+)*$` / 最大 40 文字) を追加。キー欠落は従来どおり許容 — bash 3.2+ compatible
- `agents/orchestration-recovery.md`: Step 4 の出力 JSON schema に `cause` を追加、Constraints に slug 命名規約 (kebab-case / 既存 vocabulary の再利用 / 判別不能時は `unclassified`) を追加、既存 JSON 例 2 件に `cause` を追加
- `skills/auto/SKILL.md`: Tier 3 の step 4 (validation checks 記述) に `cause` を追加、step 5b に `TIER3_RECOVERY_CAUSE` を追加、Step 4a の entry format template の `### Diagnosis` に `- cause:` 行を追加し Source 2 detection 段落に反映
- `docs/reports/orchestration-recoveries.md`: Field Definitions の `cause` 行に、どの writer が本行を出力するか (Tier 2 / Tier 3 / manual recovery の `--cause`) を追記
- `tests/apply-fallback.bats`: `write_recovery_entry` テストに `- cause: dco-signoff-missing-autofix` の assertion を追加
- `tests/auto-recovery.bats`: recovery plan に `cause` があるケース / ないケース (`unclassified` フォールバック) の 2 @test を追加
- `tests/validate-recovery-plan.bats`: `cause` 有効 / 形式不正 / キー欠落 (後方互換) の 3 @test を追加
- `tests/collect-recovery-candidates.bats`: Tier 2 / Tier 3 形状のエントリで group-key が `<symptom-short>/<cause-slug>` に分離されることを保護する @test を追加

**Steering Docs sync candidates (調査済み・変更不要)**

以下は `apply-fallback.sh` / `spawn-recovery-subagent.sh` / `validate-recovery-plan.sh` / `write_recovery_entry` を `grep -rn` した結果ヒットしたファイル。いずれも復旧機構の役割・モデル・env var の記述のみで、recovery entry の `### Diagnosis` フィールド構成には触れていないことを本文読解で確認済み。

- `docs/structure.md:230,232` — [Steering Docs sync candidate] スクリプトの役割記述のみ (エントリのフィールド列挙なし) → 変更不要
- `docs/product.md:178` / `docs/tech.md:55,102,249` — [Steering Docs sync candidate] 3 段階復旧機構の概要・sub-agent モデル・`WHOLEWORK_MAX_RECOVERY_SUBAGENTS` の記述のみ → 変更不要
- `docs/ja/structure.md:222,224` / `docs/ja/product.md:167` / `docs/ja/tech.md:46,102,218` — [Steering Docs sync candidate] 上記の日本語ミラー → 変更不要
- `modules/orchestration-fallbacks.md:639,660` — [Steering Docs sync candidate] `write_recovery_entry()` が成功分岐でのみ呼ばれる旨のみ → 変更不要
- `docs/translation-workflow.md` — sync 対象外 (`docs/reports/` は明示的な除外パスであり、top-level `docs/*.md` の変更は本 Issue に含まれない)

## Implementation Steps

1. `scripts/validate-recovery-plan.sh` に任意キー `cause` の検証を追加する。Python ブロックの `steps` 検証の直後 (`if errors:` の最終判定の直前) に、`"cause" in plan` の場合のみ (a) `isinstance(plan["cause"], str)`、(b) `re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", plan["cause"])`、(c) `len(plan["cause"]) <= 40` を検査し、いずれか失敗時に `errors` へ追加する。必須キーリスト `("action", "rationale", "steps")` は変更しない (キー欠落は valid のまま)。`re` は既存の `import re as _re` がステップ検証ブロック内のローカルスコープにあるため、ファイル冒頭の `import json` の隣にトップレベル `import re` を追加して使用する (→ 受入条件 4)
2. `agents/orchestration-recovery.md` の出力契約に `cause` を追加する (1 と並行可)。Step 4 の JSON schema コードフェンスに `"cause": "<kebab-case root-cause slug>"` を `action` の次に追加し、**Constraints** に次の 3 点を追記する: `cause` は症状ではなく根本原因を表す kebab-case slug (`^[a-z0-9]+(-[a-z0-9]+)*$`、40 文字以内)、同じ根本原因が再発した場合は `docs/reports/orchestration-recoveries.md` に既出の slug (例: `background-notification-wait` / `external-kill-during-merge` / `ff-only-merge-base-advanced` / `ci-infra-outage-during-ci-wait`) を再利用する、根本原因が特定できない場合は `unclassified` を返す。Step 4 の watchdog-kill-before-PR 例と Dirty-tree-cleanup-plus-PR-creation 例 (Issue #917) の JSON 2 件にも `cause` フィールドを追加する (→ 受入条件 4)
3. `scripts/apply-fallback.sh` の `write_recovery_entry()` の Python heredoc で、`### Diagnosis` ブロックの先頭行として `f"- cause: {anchor}\n"` を既存の `Symptom anchor ...` 行の前に出力する (1, 2 と並行可)。`anchor` は `detect_symptom_anchor()` が返す 3 種のリテラル (`dco-signoff-missing-autofix` / `code-patch-silent-no-op` / `json-mode-silent-hang`) のいずれかで既に kebab-case が保証されるため、追加のサニタイズは行わない (→ 受入条件 1, 2)
4. `scripts/spawn-recovery-subagent.sh` の `write_recovery_entry()` に cause の抽出とフォールバックを追加する (1, 2 の後)。既存の `rationale` 抽出と同じ python3 ワンライナー方式で `PLAN_FILE` から `cause` を読み、値が空 / キー欠落 / `^[a-z0-9]+(-[a-z0-9]+)*$` に不一致のいずれかなら `unclassified` に正規化する (抽出自体が失敗した場合も `|| echo "unclassified"` で同値に落とす)。正規化後の値を `WRE_CAUSE` として heredoc へ渡し、`### Diagnosis` ブロックの先頭行に `- cause: {cause}\n` を既存の `- {rationale}` 行の前に出力する (→ 受入条件 3)
5. `skills/auto/SKILL.md` の LLM 経由 Tier 3 を契約変更に追随させる (2 の後)。(a) Tier 3 の step 4 の validation checks 列挙 (`required keys (action, rationale, steps) present, ...` の行) に「任意キー `cause` は存在する場合のみ kebab-case slug として検証される」旨を追記、(b) step 5b の retain 変数リストに `TIER3_RECOVERY_CAUSE`: recovery plan JSON の `cause` フィールド (欠落・不正時は `unclassified`) を追加、(c) Step 4a の entry format template の `### Diagnosis` ブロックに `- cause: <slug>` 行を追加し、Source 2 detection 段落に「`TIER3_RECOVERY_CAUSE` を `### Diagnosis` の先頭行 `- cause:` として書く」旨を明記する (→ 受入条件 4)
6. `docs/reports/orchestration-recoveries.md` の Field Definitions テーブルの `cause` 行に、本行を出力する writer が Tier 2 (`apply-fallback.sh`、値はマッチした symptom anchor)、Tier 3 (`spawn-recovery-subagent.sh`、値は recovery plan の `cause`、欠落時 `unclassified`)、manual recovery (`run-auto-sub.sh --write-manual-recovery --cause`) の 3 経路であることを追記する (3, 4 と並行可)。`Entry Format` の `(optional; ...)` 注記は歴史的エントリが本行を持たない事実を表すため維持する (→ 受入条件 1, 3)
7. `tests/validate-recovery-plan.bats` に 3 @test を追加する (1 の後): `cause` が有効な kebab-case slug のとき exit 0、`cause` が形式不正 (大文字・空白を含む値) のとき exit 1、`cause` キーが存在しないとき exit 0 (後方互換)。既存 6 @test のフィクスチャは 3 キー構成のまま変更しない (→ 受入条件 4)
8. `tests/apply-fallback.bats` と `tests/auto-recovery.bats` に cause 行の assertion を追加する (3, 4 の後)。前者は既存の `@test "write_recovery_entry: prepends entry after marker with --record-issue Issue number, not phase-local issue arg"` に `[[ "$report_content" == *"- cause: dco-signoff-missing-autofix"* ]]` を追加。後者は `cause` を含む plan で `- cause: <slug>` が出力される @test と、`cause` を持たない plan で `- cause: unclassified` が出力される @test を追加する (→ 受入条件 1, 3)
9. `tests/collect-recovery-candidates.bats` に cause 分離の保護テストを 1 @test 追加する (3, 4 の後)。フィクスチャは Tier 3 形状 (`## <ts> UTC: code-pr-tier3-recovery` + `### Diagnosis` に `- cause:` + `### Improvement Candidate` に `- 未起票`) を cause A で 2 件・cause B で 1 件、Tier 2 形状 (`code-pr-tier2-recovery` + `- cause: <anchor>` + `- N/A (resolved by known catalog)`) を別 anchor で 2 件並べる。`--threshold 2` で `code-pr-tier3-recovery/<causeA>` が count 2 で出力され、素の `code-pr-tier3-recovery` が出力されないこと、`--threshold 1` で `code-pr-tier3-recovery/<causeB>` が count 1 で出力されること、いずれの threshold でも Tier 2 の group-key が #1191 の N/A 除外により出力されないことを assert する (→ 受入条件 5, 6)
10. `bats tests/collect-recovery-candidates.bats tests/validate-recovery-plan.bats tests/apply-fallback.bats tests/auto-recovery.bats tests/spawn-recovery-subagent.bats` を実行し全 green を確認する (7, 8, 9 の後)。`spawn-recovery-subagent.bats` は plan JSON を直接扱う既存テスト群のため、`cause` を持たない既存フィクスチャが引き続き通ることの回帰確認として含める (→ 受入条件 5)

## Alternatives Considered

- **`cause` を recovery plan の必須キーにする**: 不採用。`validate-recovery-plan.sh` は bash 経路 (`spawn-recovery-subagent.sh:205`) と LLM 経路 (`skills/auto/SKILL.md` Tier 3 step 4) が共有する安全ゲートであり、検証失敗時の挙動は「復旧を諦めて stop-and-report にフォールバック」。メタデータ 1 個の欠落で復旧可能な障害を復旧不能にするのは費用対効果が逆転する。契約文 (agent 側) では必須として指示し、validator は present-only 検証にとどめる非対称構成を採る
- **`rationale` から cause slug を導出する**: 不採用。`rationale` は 1-2 文の自由記述で、正規化ルールを機械側に置くと同じ根本原因が表記ゆれで別 slug に割れる。group-key の安定性が本 Issue の目的そのものなので、slug を agent の明示的な出力にする方が目的に直結する
- **cause が欠落・不正なとき `- cause:` 行を省略する**: 不採用。省略すると素の `<symptom-short>` key に落ちるが、これは本 Issue が解消しようとしている状態そのもので、しかも「cause を出せなかった」のか「#1281 以前のエントリ」なのかが事後に区別できない。sentinel `unclassified` を必ず書くことで、`<symptom>/unclassified` が `/audit recoveries` 出力上で診断不足の可視シグナルになる
- **Tier 2 と Tier 3 を別 Issue に分割する**: 不採用 (Issue 本文が `/spec` の判断に委ねた項目)。受入条件 1-6 が両 Tier をまたぐ 1 セットとして書かれており、分割すると受入条件の再編と 2 件目の起票が必要になる。実変更は Tier 2 が 1 行、Tier 3 が契約 + writer + validator + 呼び出し元 2 系統で、合算しても Size L の範囲に収まる

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/apply-fallback.sh の write_recovery_entry() が生成するエントリの ### Diagnosis ブロックに、マッチした anchor 名を値とする `- cause: <slug>` 行が含まれている" --> Tier 2 のエントリが anchor を cause slug として記録する
- <!-- verify: grep "cause:" "scripts/apply-fallback.sh" --> `apply-fallback.sh` に cause 行の出力がある
- <!-- verify: rubric "scripts/spawn-recovery-subagent.sh の write_recovery_entry() が生成するエントリの ### Diagnosis ブロックに `- cause: <slug>` 行が含まれている。slug の供給元 (recovery plan の新規フィールド、または既存フィールドからの導出) が実装されていること" --> Tier 3 のエントリが cause slug を記録する
- <!-- verify: rubric "agents/orchestration-recovery.md の出力契約に cause slug 相当のフィールドが定義され、scripts/validate-recovery-plan.sh がその存在を許容している (必須化するか任意にするかは実装判断)。呼び出し元と契約定義の双方が同一コミットで更新されていること" --> agent の出力契約と validator が cause slug に対応している
- <!-- verify: command "bats tests/collect-recovery-candidates.bats" --> `collect-recovery-candidates.bats` が PASS する
- <!-- verify: rubric "Tier 2 / Tier 3 が書いた cause 付きエントリを collect-recovery-candidates.sh が `<symptom-short>/<cause-slug>` 形式で分離することを保護するテストケースが追加されている" --> cause 分離がテストで保護されている

### Post-merge

- 次回 Tier 2 または Tier 3 recovery が発火した際、`docs/reports/orchestration-recoveries.md` の当該エントリに `- cause:` 行が記録され、`collect-recovery-candidates.sh --with-tracking` の出力で cause 別に分離されることを観察する

## Tool Dependencies

### Bash Command Patterns
- none (実装は既存の Read / Edit / Write と `bats` 実行のみ。新規スクリプト・新規 Bash パターンの追加なし)

### Built-in Tools
- none (`/code` の既存 `allowed-tools` で充足)

### MCP Tools
- none

## Uncertainty

- **Tier 3 の cause slug 品質は実運用でしか測れない**: agent が返す slug が既存 vocabulary を実際に再利用するか、毎回新しい slug を作って group-key が単発だらけになるかは、プロンプト側の指示だけでは確定できない。
  - **検証方法**: post-merge 受入条件の観察 (次回 Tier 3 発火時のエントリと `collect-recovery-candidates.sh --with-tracking` 出力)。単発 group-key が増える傾向が観察された場合は、agent プロンプトに既出 slug 一覧を動的に注入する後続 Issue を検討する
  - **影響範囲**: Implementation Step 2 の Constraints 文言のみ。スクリプト側の実装 (Step 3, 4) には影響しない

## Notes

**実装との矛盾 (Tier 2 の cause 行は今日の頻度シグナルには効かない)**

Issue 本文 Background は Tier 2 / Tier 3 の双方について「`- cause:` 行がないため頻度検出が原因別に分離できない」としているが、Tier 2 に限っては現状そもそも頻度カウントに乗っていない。

- Issue 本文の記述: 「記録経路が 3 つあるが、**Tier 2 と Tier 3 が `- cause:` 行を書いていない**。結果として、根本原因の異なる復旧イベントが 1 つの group-key に潰れ、`collect-recovery-candidates.sh` の頻度検出が原因別に分離できない」
- 実装: `scripts/apply-fallback.sh:191` は Improvement Candidate に常に `- N/A (resolved by known catalog)` を書く。`scripts/collect-recovery-candidates.sh:218` の #1191 由来の `^- N/A` 判定がこれを拾い、当該エントリを count から完全に除外する (`cutoff` / `count_all` の両モードで `ENTRY_NA[$i]` が 0 のものしか数えない)
- 実測: `bash scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 1 --with-tracking` の出力に、ログ中に 1 件存在する `code-pr-tier2-recovery` は現れない (対して `code-pr-tier3-recovery 3 tracked:#799` は現れる)

**解決方針 (非対話モードで自動解決)**: Tier 2 側も受入条件どおり実装する。ただし Tier 2 における `- cause:` 行の価値は「今日の頻度シグナルの分離」ではなく (a) ログ本文の可読性、(b) #1191 の N/A 除外方針が将来変わった場合・エントリが手作業で再分類された場合に group-key が即座に正しくなる前方互換性、の 2 点である。本 Issue の頻度検出上の実効は Tier 3 側で得られる。Implementation Step 9 のテストはこの相互作用そのものを assert して固定する。

**自動解決したあいまい点 (非対話モード)**

- **Tier 2 と Tier 3 を同一 Issue で扱う** — 理由: 受入条件 1-6 が両 Tier をまたぐ 1 セットとして書かれており、分割は受入条件の再編と追加起票を要する。実変更量も Size L に収まる。他候補: Tier 2 と Tier 3 を別 Issue に分割
- **`cause` は validator では任意キー、agent 契約文では必須指示** — 理由: validator は復旧の安全ゲートであり、検証失敗は stop-and-report を意味する。メタデータ欠落で復旧を止めるのは least-risk 原則に反する。既存 `tests/validate-recovery-plan.bats` の 3 キー構成フィクスチャも無改変で通る。他候補: 必須キー化 / validator では一切検証しない
- **cause 欠落・不正時は sentinel `unclassified` を書く** — 理由: 行を省略すると素の `<symptom-short>` に落ち、「cause を出せなかった」と「#1281 以前のエントリ」が区別できなくなる。他候補: `- cause:` 行そのものを省略

**allowed-tools impact chain check**

Changed Files に新規 `scripts/*.sh` は含まれず、`modules/*.md` の変更も含まれないため、Case 1 / Case 2 のいずれも該当せずスキップ。

**bash 互換**

`scripts/apply-fallback.sh` / `scripts/spawn-recovery-subagent.sh` / `scripts/validate-recovery-plan.sh` はいずれも bash 3.2+ 互換 (連想配列・`mapfile` 不使用) を維持する。追加処理は python3 heredoc 内および python3 ワンライナー内に閉じるため、bash 側の新機能依存は生じない。

**`- cause:` 行の配置**

`scripts/collect-recovery-candidates.sh:213-216` の検出は「エントリ内の任意の行が `^- cause: .+` にマッチするか」であり `### Diagnosis` セクションへのスコープ限定はない。それでも既存 3 経路 (`run-auto-sub.sh` の manual recovery、および本 Issue で対応する Tier 2 / Tier 3) は `### Diagnosis` の先頭行に置く規約で揃える。`docs/reports/orchestration-recoveries.md` の Entry Format も同位置を規定している。

**verify command の事前確認**

- `grep "cause:" "scripts/apply-fallback.sh"` — 現状 0 件 (ファイル中の唯一の `cause` 出現は `scripts/apply-fallback.sh:100` のコメント `# Safe because reconcile confirms...` で、`cause` の直後がコロンではないため不一致)。Implementation Step 3 で導入される文字列であり、変更検知として機能する
- `command "bats tests/collect-recovery-candidates.bats"` — 対象ファイルは実在 (549 行、19 @test)
- rubric 4 件はいずれも実装後の状態を意味レベルで判定するもので、数値リテラル・定数名・閾値を含まないため `file_contains` の併記は不要
