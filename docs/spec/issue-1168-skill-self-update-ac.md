# Issue #1168: issue/verify: SKILL.md 変更 Issue の post-merge AC が skill 自己更新の非伝播で同一セッション評価不能になる構造を扱う

## Consumed Comments

cutoff (最新の `phase/*` ラベル付与時刻) は `2026-08-05T02:50:37Z`。cutoff 以降のコメントは 0 件。

ただし cutoff 直前 (`2026-08-05T02:34:50Z`) に投稿された以下のコメントは、本 Issue の設計判断を直接左右する一次データを含むため、best-effort で consume した (Issue 本文には未反映の観測事実であり、落とすと方針評価が誤る)。

| login | authorAssociation | trust tier | 意図要約 | URL |
|-------|-------------------|-----------|---------|-----|
| saito | MEMBER | first-class | skill キャッシュ境界は `/auto` 実行単位ではなく**会話セッション単位**であることを実測。別 `AUTO_SESSION_ID` でも同一会話内なら古い skill で動くため、方針 C の `AUTO_SESSION_ID` 比較は検知漏れになる。方針 A / B が相対的に優位、方針 D も `skill_versions` が「開始時点のハッシュ」でしかない同じ限界を持つ | https://github.com/saitoco/wholework/issues/1168#issuecomment-5186873804 |

## Overview

wholework は自己ホスト型リポジトリであり、harness が **会話セッション単位で skill 内容をキャッシュ**する。このため `skills/*/SKILL.md` を変更する Issue の post-merge observation AC は、その Issue を処理した会話セッション内では原理的に評価できず、`/verify` が UNCERTAIN を返して `phase/verify` 滞留を 1 件増やす (実例: #1157 条件 7)。

本 Issue は、この制約を **AC 生成時点で宣言可能にし、`/verify` の判定でも意味論的に正しく扱えるようにする**。

採用方針は **A (AC 生成時の機械的警告) + B (条件文への評価タイミング宣言規約)** を軸に、宣言を機械可読な属性 `session=next` として定義し、**`/verify` Step 8c の判定分岐 (C の文書レベル部分)** を併せて導入する。方針 D (`collect-run-facts.sh` への skill ハッシュ取り込み) と、セッション境界を機械判定する方針 C 全体は不採用 (根拠は `## Notes`)。

### `session=next` の定義

```
<!-- verify-type: observation event=auto-run session=next -->
```

意味: この observation AC が観察する挙動は、**当該 Issue 自身が変更した `skills/*/SKILL.md`** に由来する。変更が base branch に着地する前に skill を読み込んだ会話セッションでは観察できず、評価が成立するのは着地後に開始した会話セッション以降である。

consumer (exhaustive):

| consumer | 役割 |
|----------|------|
| `/issue` Step 4 | 起票時に付与漏れを機械検出して警告 (方針 A) |
| `/verify` Step 8c | 発火済み AC の判定で UNCERTAIN ではなく SKIPPED に倒す |
| `scripts/opportunistic-search.sh` | **gate ではない** — マッチング挙動は変更しない |

`opportunistic-search.sh:139` の event マッチは `grep "event=${EVENT_NAME}"` の部分一致であり、`event=auto-run session=next` も既存どおりマッチする (スクリプト変更不要であることを実装確認済み)。

## Changed Files

- `scripts/check-skill-change-observation-ac.sh`: 新規作成 — Issue 本文ファイルを受け取り、`skills/*/SKILL.md` 参照を含む場合に `session=next` 未付与の observation AC 行を検出する warn-only チェッカー — bash 3.2+ 互換 (`mapfile` / 連想配列 / `${var^^}` を使わない)
- `tests/check-skill-change-observation-ac.bats`: 新規作成 — 「SKILL.md 変更を含むケース」「含まないケース」の 2 経路 + 付与済みケース + usage error の 4 ケース
- `modules/verify-classifier.md`: `### observation Type: Event Values and Syntax` 節に `session=next` 属性の定義・意味論・consumer 一覧を追加
- `modules/observation-trigger.md`: `## Notes` に「`session=next` は宣言用属性であり `keyword=` / `config=` のような dispatch gate ではない」旨を追加
- `skills/issue/SKILL.md`: `### Step 4: Classify Acceptance Criteria and Assign Verify Commands` に "Skill self-update propagation check" サブステップを追加。frontmatter `allowed-tools` の `Bash(...)` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-skill-change-observation-ac.sh:*` を追加
- `skills/verify/SKILL.md`: `#### Step 8c: Observation Post-merge Conditions` の "3. Judgment" に `session=next` 分岐を追加
- `tests/issue.bats`: `/issue` Step 4 の新サブステップに対する content-assertion テストを 1 件追加
- `tests/verify.bats`: Step 8c の `session=next` 分岐に対する content-assertion テストを 1 件追加 (既存の `extract_step_8c` ヘルパを再利用)
- `docs/structure.md`: `**Tooling:**` の `check-*` 群に `scripts/check-skill-change-observation-ac.sh` の 1 行を追加
- `docs/ja/structure.md`: [translation sync] `**ツーリング:**` に同エントリの日本語版を追加 (`docs/translation-workflow.md` の同期義務対象 — top-level `docs/*.md` の変更)

**変更不要と確認済み (grep 実施)**:
- `scripts/opportunistic-search.sh`: line 139 の `grep "event=${EVENT_NAME}"` は部分一致のため `session=next` 併記でも既存マッチが壊れない — 変更不要
- `.claude/settings.json.template`: `Bash(${WHOLEWORK_ROOT}/scripts/*.sh *)` のワイルドカード行が既にあり、既存の `check-pre-merge-ac.sh` / `check-session-findings-disposition.sh` も個別登録されていない — 変更不要
- `scripts/validate-skill-syntax.py`: 追加するのは `Bash(...)` 内のスクリプトパターンであり新規ツール名ではないため `KNOWN_TOOLS` 更新は不要
- `modules/verify-patterns.md`: 追記しない (根拠は `## Notes`)

## Implementation Steps

1. `scripts/check-skill-change-observation-ac.sh` を新規作成する (→ AC1, AC2)
   - **入力**: 第 1 引数に Issue 本文の Markdown ファイルパス (`/issue` は `.tmp/issue-body-$NUMBER.md` を渡す)
   - **出力**: `session=next` を欠く observation AC 行を 1 行 1 件で stdout へ
   - **exit code (exhaustive)**:
     - `0` — 本文に `skills/*/SKILL.md` 参照が無い、または該当する observation AC がすべて `session=next` を持つ
     - `1` — usage error (引数欠落、またはファイルが読めない)
     - `2` — `session=next` 未付与の observation AC を 1 件以上検出
   - **判定ロジック**:
     - skill 変更スコープ判定: `grep -qE 'skills/[A-Za-z0-9_-]+/SKILL\.md' "$FILE"`。ヒットしなければ即 `exit 0` (出力なし)
     - observation AC 行の抽出: `^- \[[ xX]\]` にマッチし、かつ `verify-type: observation` を含む行
     - 未付与判定: その行が `session=next` を**含まない**場合に出力対象
   - `set -euo pipefail` + `#!/usr/bin/env bash` で開始し、`scripts/check-session-findings-disposition.sh` のヘッダコメント形式 (Usage / Exit codes) を踏襲する
   - bash 3.2+ 互換: `while IFS= read -r line` ループと `case` / `[[ ... == *...* ]]` のみを使う

2. `tests/check-skill-change-observation-ac.bats` を新規作成する (after 1) (→ AC3, AC4)
   - `bats_require_minimum_version 1.5.0` + `PROJECT_ROOT` / `REAL_SCRIPT` 定義は `tests/check-session-findings-disposition.bats` の形式に揃える
   - テストケース (exhaustive):
     - 「SKILL.md 変更を**含まない**ケース」: 本文に `skills/*/SKILL.md` 参照が無く、`session=next` 無しの observation AC がある → exit 0 かつ出力なし
     - 「SKILL.md 変更を**含む**ケース (未付与)」: 本文に `skills/auto/SKILL.md` 参照があり、`session=next` 無しの observation AC がある → exit 2 かつ当該行が出力される
     - 「SKILL.md 変更を含む + 付与済み」: `session=next` 付きの observation AC のみ → exit 0
     - usage error: 引数なし / 存在しないパス → exit 1
   - **self-reference 除外は不要**: 本スクリプトは引数で渡されたファイルだけを走査し、リポジトリ全体を grep しないため、bats fixture が検出対象に混入する経路が存在しない

3. `modules/verify-classifier.md` の `### observation Type: Event Values and Syntax` 節に `session=next` の定義を追加する (parallel with 1, 2) (→ AC1, AC2)
   - 挿入位置: 既存の `**\`config=<key>\` for setting-dependent observation conditions**:` 段落の直後、`### Tag Assignment Example` 見出しの直前
   - 記述内容: タグ例、意味論 (skill 自己更新の非伝播により、変更着地後に開始した会話セッション以降でしか評価が成立しない)、consumer 一覧 (exhaustive) — `/issue` Step 4 の警告 / `/verify` Step 8c の SKIPPED 判定 / `opportunistic-search.sh` は gate にしない
   - 背景の参照先として `docs/sessions/73536-1785868487-2026-08-04/session.md` § Skill Self-Update Propagation Note と #1157 を挙げる

4. `modules/observation-trigger.md` の `## Notes` に、`session=next` が dispatch gate ではないことを明記する (after 3) (→ AC2)
   - `## Condition Check Gate (keyword=)` / `## Condition Check Gate (config=)` の 2 節と対比し、`session=next` は同じ属性位置に置かれるが**マッチング挙動を変えない宣言用属性**であることを 1 パラグラフで記す
   - 理由も併記する: セッション境界は機械判定できず (Issue #1168 コメントの実測)、gate 化すると AC が恒久的に dispatch されなくなる

5. `skills/issue/SKILL.md` の Step 4 に "Skill self-update propagation check" サブステップを追加し、`allowed-tools` を更新する (after 1, 3) (→ AC1, AC2)
   - 挿入位置: `**Assign verify-type tags to post-merge conditions:**` 段落の直後、`**Metadata-only implementation-type marker (auto-attach):**` の直前
   - サブステップ本文 (要旨): Issue が `skills/*/SKILL.md` の変更を含み、かつ post-merge に `verify-type: observation` の AC を置く場合、その AC は当該 Issue を処理する会話セッションでは評価できない。条件文に評価タイミングを明示したうえで、タグに `session=next` を付与する。付与漏れの機械検出として、Issue 本文を `.tmp/issue-body-$NUMBER.md` に書き出したうえで次を実行する:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/check-skill-change-observation-ac.sh .tmp/issue-body-$NUMBER.md
     ```
     exit 2 のときは出力された行を警告として提示し、`session=next` を付与してから本文を更新する。exit 1 は warn-only として扱い、処理は継続する
   - **既存 Issue 精錬経路への伝播**: line 461 の `### Step 7: Classify Acceptance Criteria and Assign Verify Commands` は「New Issue Creation → Step 4 の手順に従う」と参照しているため、Step 4 への追加だけで両経路がカバーされる。Step 7 側の参照文に本サブステップ名を追記する必要はない (追記も変更もしない)
   - frontmatter `allowed-tools` の `Bash(...)` リストに `${CLAUDE_PLUGIN_ROOT}/scripts/check-skill-change-observation-ac.sh:*` を追加する (`scripts/check-allowed-tools.sh` が SKILL.md body の `${CLAUDE_PLUGIN_ROOT}/scripts/` 参照と allowed-tools の差分を検出するため必須)
   - SKILL.md 本文制約: 半角 `!` を使わない / Step 番号は整数のみ / 本文にトリプルバッククォートを直接置かない (コードフェンス内は可)

6. `skills/verify/SKILL.md` Step 8c の "3. Judgment" に `session=next` 分岐を追加する (after 3) (→ AC1, AC2)
   - 挿入位置: `**3. Judgment**` の判定リスト直後、`**Post-Step 8 checkpoint: flip post-merge PASS checkboxes**` の直前
   - 分岐内容: AC 行が `session=next` を持つ場合、"2. Evidence collection" で集めた証拠から**変更後の skill ステップが当該 `/auto` 実行で実際に走ったか**を確認する。走ったことを示す証拠がある → 通常どおり PASS/FAIL を判定する。証拠が無い/曖昧 → **UNCERTAIN ではなく SKIPPED** とし、Details 列に `skill self-update not yet propagated (session=next)` を記録する
   - 併記する根拠: 既存の SKIPPED 定義「The observed premise itself does not hold in this repository」の一般化であり、Step 11 (a) 分岐で SKIPPED が無視される一方 UNCERTAIN は (d) 分岐で手動再検証の催促を発生させるため、意味論的にも運用コスト的にも SKIPPED が正しい

7. `tests/issue.bats` と `tests/verify.bats` に content-assertion を 1 件ずつ追加する (after 5, 6) (→ AC3, AC4)
   - `tests/issue.bats`: 既存の `@test "issue skill Step 4 ..."` 群の末尾に、Step 4 本文が `check-skill-change-observation-ac.sh` と `session=next` の両方を含むことを検証するテストを追加
   - `tests/verify.bats`: 既存の `extract_step_8c` ヘルパを再利用し、Step 8c 節が `session=next` と `skill self-update not yet propagated` を含むことを検証するテストを追加
   - `@test` 名は既存ファイルの命名 (`issue skill Step 4 ...` / `Step 8c: ...`) に揃える

8. `docs/structure.md` と `docs/ja/structure.md` にスクリプトエントリを追加する (after 1) (→ AC2)
   - `docs/structure.md`: `**Tooling:**` の `check-session-findings-disposition.sh` 行の直後に 1 行追加
   - `docs/ja/structure.md`: `**ツーリング:**` の対応位置に同内容の日本語行を追加 (`docs/translation-workflow.md` の同期手順に従う)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/*/SKILL.md を変更する Issue の post-merge observation AC が、その Issue を処理したセッションでは評価できないという制約が、/issue の AC 生成手順・modules/verify-patterns.md・/verify の判定手順のいずれか (または複数) に明文化されている" --> 制約が手順として明文化されている
- <!-- verify: rubric "採用した方針 (A/B/C/D のいずれか、または組み合わせ) が実装され、採用しなかった候補について不採用の判断根拠が Spec または Issue に記録されている" --> 採用方針が実装され不採用根拠が記録されている
- <!-- verify: rubric "tests/ 配下に、SKILL.md 変更を含む Issue のケースと含まないケースの 2 経路を検証するテストが存在する。方針 B (条件文の書式規約のみ) を採用した場合は、規約の存在を検証する content-assertion テストでもよい" --> 2 経路を検証するテストが追加されている
- <!-- verify: command "bats tests/" --> テストスイート全件が PASS する

### Post-merge

- 次回 `skills/*/SKILL.md` を変更する Issue を処理した際、その post-merge AC が採用方針どおりに扱われる (`/issue` が `session=next` 未付与を警告する、または `/verify` Step 8c が `session=next` 付き AC を SKIPPED に倒す) ことを観察する <!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - `/issue` 実行時に `check-skill-change-observation-ac.sh` の警告行 (未付与の observation AC 行) が出力される、または生成された AC に `session=next` が付与されている
    - `/verify` 実行時、`session=next` 付き observation AC の Details 列が UNCERTAIN ではなく SKIPPED (理由: `skill self-update not yet propagated`) になる

## Tool Dependencies

### Bash Command Patterns
- `${CLAUDE_PLUGIN_ROOT}/scripts/check-skill-change-observation-ac.sh:*` — `skills/issue/SKILL.md` の `allowed-tools` に追加が必要 (新規スクリプトの Step 4 からの呼び出し)

### Built-in Tools
- none (既存の Read / Write / Edit / Grep のみで足りる)

### MCP Tools
- none

## Notes

### 不採用方針とその根拠 (→ AC2)

| 候補 | 判断 | 根拠 |
|------|------|------|
| **A. `/issue` の AC 生成時に警告する** | **採用** | セッション境界の機械判定を必要とせず、付与漏れを決定論的に検出できる。Issue コメントの実測でも A / B の相対的優位が示された |
| **B. 条件文に評価タイミングを織り込む書式を定める** | **採用 (機械可読な属性として実装)** | 自然言語の言い回し (「次回以降の」等) は言語依存で機械検証できない。Skills は language-agnostic を保つ方針 (CLAUDE.md) のため、既存の `keyword=` / `config=` と同じ HTML 属性形式 `session=next` に落とした |
| **C. `/verify` が skill 変更 Issue を検知して SKIPPED に倒す** | **部分採用 (判定分岐のみ。セッション境界の機械判定は不採用)** | Issue コメントの実測により、**別 `AUTO_SESSION_ID` でも同一会話セッション内なら古い skill で動く**ことが判明した。`AUTO_SESSION_ID` 比較も `skill_versions` 比較も検知漏れになるため、機械判定は導入しない。代わりに AC 側の `session=next` 宣言を入力として Step 8c の判定分岐だけを実装する |
| **D. `collect-run-facts.sh` の実行事実に skill ハッシュを含める** | **不採用** | `.tmp/auto-session-*.json` の `skill_versions` は `git log -1` 由来の「セッション開始時点のディスク上のハッシュ」であり、「実際に読み込まれた skill 内容」ではない。#1157 の事例そのものが両者の乖離例であるため、実装量に見合う精度が得られない。#1157 の run-fact reconciliation 機構への接続は、`session=next` が運用実績を持ってから再評価する |

### `modules/verify-patterns.md` に追記しない判断

AC1 は「`/issue` の AC 生成手順・`modules/verify-patterns.md`・`/verify` の判定手順の**いずれか (または複数)**」を許容しており、本 Spec は `/issue` と `/verify` の 2 箇所で満たす。`modules/verify-patterns.md` は eager-load 共通モジュールで、`docs/environment-adaptation.md` の Eager-load vs Lazy-load 分類表が「1 セクションあたり ~1500 tokens、追加は避ける」と明記している。本制約は自己ホスト型リポジトリでのみ発火するため、全プロジェクトに eager-load コストを課す配置は不適切と判断した。

### #1118 / #1157 との境界

- **#1118** (observation AC への実行文脈条件の宣言) は route / mode / recovery tier といった**実行文脈**を宣言して dispatch 母集団から除外する提案。`session=next` は**時間軸 (どのセッション以降で評価が成立するか)** の宣言であり、直交する。`session=next` を dispatch gate にしないのは、gate 化すると #1118 の設計空間と衝突し、かつセッション境界が機械判定できない以上 AC が恒久的に dispatch されなくなるため
- **#1157** (run-fact AC reconciliation) との接続は方針 D にあたり、本 Issue では不採用。上表参照

### 実装確認済みの前提

- `scripts/opportunistic-search.sh` line 139 の event マッチは `grep "event=${EVENT_NAME}"` の部分一致。`event=auto-run session=next` でも既存マッチが維持されるため、属性追加による後方互換性の破壊はない
- `/verify` Step 11 の分岐は (a) 「PASS または SKIPPED のみ」= `phase/verify` 付与のみ、(d) 「UNCERTAIN あり」= `phase/verify` 付与 + 手動再検証の催促。SKIPPED へ倒すことで、観察不能な AC に対する再検証の催促が消える (Issue の close 判定自体は observation AC が unchecked のままなので変わらない — 過大評価しないこと)

### 自己適用

本 Issue 自身が `skills/issue/SKILL.md` と `skills/verify/SKILL.md` を変更するため、post-merge observation AC には本 Spec で導入する `session=next` を自己適用した。Issue 本文の AC も同じ形に更新済み。

## spec retrospective

### Minor observations

- Issue のコメント (issuecomment-5186873804) は `phase/issue` ラベル付与時刻より 16 分早く投稿されており、`modules/l0-surfaces.md` の cutoff ルールでは consume 対象外になる。しかし内容は方針評価を反転させる一次データだった。cutoff は「前フェーズ以降の追加入力」を拾う設計だが、**同一フェーズ内で後から投稿された観測データ**を落とす経路がある。cross-phase marker exception (`type=verify-fail` / `type=preview-ac-unverified`) と同種の救済が、人手の一次データ追記コメントにも要りうる
- `/issue` の AC 分類手順は「New Issue Creation → Step 4」に集約され、既存 Issue 精錬経路 (Step 7) はそこを参照する構造になっている。この参照関係のおかげで、AC 生成系のサブステップ追加は 1 箇所で両経路に効く。今回のように「どちらの経路にも効かせたい」変更では、Step 7 を触らないのが正しい

### Judgment rationale

- **方針決定の決め手はコメントの実測データだった** — Issue 本文だけを読むと C (セッション同一性を機械判定) と D (skill ハッシュを実行事実へ) が「精度が高い」候補に見える。しかし「skill キャッシュ境界が `/auto` 実行単位ではなく会話セッション単位」という実測により、両者が依拠する `AUTO_SESSION_ID` / `skill_versions` がいずれも検知漏れを持つことが確定した。Issue 本文の候補列挙をそのまま評価軸にしていたら誤った方針を選んでいた
- **B を自然言語の言い回し規約ではなく HTML 属性 `session=next` に落とした** — Issue 本文の B は「『次回以降の』のように条件文に明示する規約」を想定していたが、AC3 が求める機械検証 (2 経路テスト) を自然言語パターンで実装すると日本語固定になり、Skills の language-agnostic 方針 (CLAUDE.md) に反する。既存の `keyword=` / `config=` と同じ属性形式に揃えることで、B の意図を保ちながら A の機械検出を成立させた
- **`session=next` を dispatch gate にしない判断** — `keyword=` / `config=` は同じ属性位置にありながら `opportunistic-search.sh` のマッチを絞る gate である。同じ形をしていて挙動が違うのは混乱の元なので、`modules/observation-trigger.md` に「gate ではない」旨を明記する実装ステップを立てた。gate 化しない理由は、セッション境界が機械判定できない以上、gate が恒久的に false になり AC が永久に dispatch されなくなるため
- **`modules/verify-patterns.md` を触らない判断** — AC1 が 3 つの記述先を「いずれか (または複数)」と許容していたため、eager-load コスト方針 (`docs/environment-adaptation.md`) を優先して 2 箇所に絞った。AC の許容幅が広い場合、プロジェクトの既存アーキテクチャ方針が実質的な選択基準になる

### Uncertainty resolution

- **`session=next` 追加が既存の observation dispatch を壊さないか** — `scripts/opportunistic-search.sh:139` の `grep "event=${EVENT_NAME}"` が部分一致であることをコード確認し、`event=auto-run session=next` でも既存マッチが維持されることを確定させた。属性の並び順にも依存しない
- **SKIPPED へ倒すことの実効果** — `skills/verify/SKILL.md` Step 11 を読み、(a) 「PASS または SKIPPED のみ」と (d) 「UNCERTAIN あり」の差が「手動再検証の催促の有無」であることを確認した。Issue の close 判定は observation AC が unchecked のまま変わらないため、`phase/verify` 滞留件数そのものは減らない。Spec の Notes に「過大評価しないこと」として明記した
- **`.claude/settings.json.template` への登録要否** — `Bash(${WHOLEWORK_ROOT}/scripts/*.sh *)` のワイルドカード行が既にあり、同種の `check-pre-merge-ac.sh` / `check-session-findings-disposition.sh` も個別登録されていないことを grep で確認し、変更不要と判定した (未検証の「変更不要」判定を避けるルールに従った)

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1-8 をすべて Spec 記載どおりの順序・挿入位置で実装した

### Design Gaps/Ambiguities

- N/A — Spec の判定ロジック・挿入位置・テストケースの記述が具体的で、実装時に解釈が割れる箇所はなかった

### Rework

- N/A

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- PR #1173 は mergeable=true (clean, CI success, review approved) であったため、コンフリクト解消・追加テスト実行は不要でそのまま squash merge を実行した
- pre-merge AC gate は 4 件全てチェック済みで `unchecked_count=0` を確認し、ゲート通過を確認した上でマージした

### Deferred Items

- #1157 の run-fact reconciliation への接続 (方針 D) は不採用のまま。`session=next` が運用実績を持ってから再評価する
- #1118 が扱う route / mode / recovery tier 依存の dispatch 抑止は本 Issue のスコープ外のまま

### Notes for Next Phase

- 本 Issue 自身が `skills/issue/SKILL.md` / `skills/verify/SKILL.md` を変更するため、post-merge observation AC には `session=next` を自己適用済み。次回 `/verify` 実行時、この AC が fire したら Step 8c の `session=next` 分岐 (このセッションで導入した変更後の Step 8c ロジック自身) が SKIPPED 判定を返すか確認すること — 自己適用のため一種の自己参照的な検証になる
- `bats tests/` は全 1387 件 PASS 済み。behavioral change 検出により全件実行した (modules/verify-classifier.md が tests/verify-executor.bats から、skills/issue・verify/SKILL.md が複数のテストファイルから参照されているため)

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- Size L / Type Task の判定と AC 4 件の verify command 割り当ては適切だった。AC1 が記述先を「いずれか (または複数)」と許容していたことが、`modules/verify-patterns.md` を触らない判断 (eager-load コスト回避) を可能にした。AC の許容幅を意図的に持たせる書き方が、実装時にアーキテクチャ方針を優先させる余地を作った好例

#### spec

- **MUST 指摘 2 件の起点はいずれも Spec 側だった**。Code Retrospective は "Deviations from Design: N/A" と記録しているが、これは正しい — 実装は Spec どおりで、Spec の記述自体に欠陥があった:
  - ゲート条件を「Issue の `## Changed Files` に `skills/*/SKILL.md` が含まれる場合」と定義したが、`## Changed Files` は **Spec のセクション**であり `/issue` 実行時点では Spec 自体が存在しない。常に false になるゲートを書いていた
  - 検査対象ファイルを `.tmp/issue-body-$NUMBER.md` と指定したが、New Issue Creation 経路の Step 4 時点では Issue 未作成で `$NUMBER` が未束縛
- 共通する構造は「**そのフェーズの実行時点で参照可能な情報かを検証していない**」こと。Spec が別フェーズの成果物 (Spec のセクション、後のステップで束縛される変数) をゲート条件に使う場合、フェーズ順序との整合を明示的に確認する観点が要る

#### code

- 実装は Implementation Steps 1-8 を順序どおり遂行し、逸脱なし。Spec 由来の欠陥は code フェーズでは検出されなかったが、これは code の責務範囲を考えれば妥当 (Spec を疑う責務は review 側にある)

#### review

- **検出能力は有効に働いた**。`review-spec` + `review-bug`×2 の並列構成が MUST 2 件 / SHOULD 4 件 / CONSIDER 3 件を検出し、すべて実体のある欠陥だった。特に MUST 1 (常に false のゲート) は、見逃していれば機能が完全に無効なまま着地していた。adversarial 検証サブエージェントによる 1 件の REJECT も妥当な判断だった
- **一方でフェーズ完走に 2 回連続で失敗した**。両実行とも「バックグラウンドの bats テスト完了を待ちます」で turn を終え、`claude -p` セッションがそこで終了 (silent no-op)。1 回目は指摘の投稿前、2 回目は指摘投稿後・Step 11 の修正コミット前に停止した
- **2 回目の fallback が完了シグナルを立ててしまった**。`post-fallback-review-summary.sh` が `<!-- review-summary -->` 付きコメントを投稿した結果、`reconcile-phase-state.sh review --check-completion` が `matches_expected: true` を返し、`run-review.sh` は exit 0 で終了した。実際には MUST 2 件が未対応のままで、親セッションが PR コメントを直接読まなければ、未修正のまま `/merge` へ進んでいた
- 未コミットの修正が review worktree に残っていたため作業自体は失われなかったが、その事実を orchestrator に伝えるシグナルは存在しなかった

#### merge

- CI 9/9 pass・pre-merge AC gate 4/4 チェック済みで、コンフリクトなく squash merge が完了。異常なし

#### verify

- 全 4 件の pre-merge AC が PASS、post-merge の observation AC は未発火のため SKIPPED。判定は設計どおり
- **本 `/verify` 実行そのものが、この Issue の扱う非伝播現象の実測になった**。merge (`232f0837`) 後に同一会話セッション内で `/verify 1168` を起動したが、セッションに注入された `skills/verify/SKILL.md` Step 8c には `session=next` 分岐 (L416) が含まれていなかった (ディスク上の `main` には存在)。`AUTO_SESSION_ID` は同一 (`54459-1785897894`) であり、会話セッション自体が merge 前に開始しているため、方針 C の `AUTO_SESSION_ID` 比較でも方針 D の `skill_versions` 比較でも検知できない構造であることが再確認された。Spec `## Notes` の不採用判断と整合する

### Improvement Proposals

- `post-fallback-review-summary.sh` の fallback 投稿が review フェーズの完了シグナル (`<!-- review-summary -->` マーカー) を立ててしまい、未対応の MUST 指摘を持つ PR が `/merge` のゲートを通過しうる。本 Issue では `run-review.sh` が exit 0 で終了し `reconcile-phase-state.sh` も `matches_expected: true` を返したが、実際には MUST 2 件が未修正だった。fallback サマリは「review が自力で完了しなかった」ことを機械可読なマーカー (例: `<!-- wholework-event: type=review-incomplete -->`) で記録し、`/merge` の pre-merge ゲートまたは `/auto` の completion check がそれを検出して停止できるようにすべき
- `/review` がバックグラウンドで `bats tests/` を起動し完了通知を待つ形で turn を終えると、`claude -p` セッションがそこで終了して silent no-op になる。本 Issue では 2/2 の再現率で発生した (`review-completion-false-negative` として Tier 2 検出済み)。`run-review.sh` のプロンプト側で「テストはフォアグラウンドで実行し、turn を跨いで待たない」旨を明示するか、wrapper 側がバックグラウンドタスク待ちで終了した turn を検出して継続を促す仕組みが要る
- `reconcile-phase-state.sh review --check-completion` が review worktree (`.claude/worktrees/review+pr-N`) の dirty 状態を確認していないため、「修正途中で中断」と「修正不要で完了」を区別できない。本 Issue では未コミットの修正が worktree に残っており、親セッションが手動で確認するまで検出されなかった。completion check に worktree dirty 判定を加えれば、Tier 1 の段階で「修正途中」を診断できる
- Spec が `/issue` 実行時点で存在しないセクション (`## Changed Files` は Spec のセクション) や、その時点で未束縛の変数 (`$NUMBER`) をゲート条件・ファイルパスに使っていた。`/spec` の設計時に「このゲート条件は、それを評価するフェーズの実行時点で参照可能な情報だけで書かれているか」を確認する観点を追加すべき。本 Issue では MUST 指摘 2 件がいずれもこの一点に起因した
