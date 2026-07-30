# Issue #1054: verify-patterns: 不在を検証する AC に参照点を持たせるガイドラインを追加

## Consumed Comments

- saito / MEMBER / first-class / `/issue 1054 --non-interactive` の Issue Retrospective (Ambiguity Points の Auto-Resolve Log: vacuous truth パターンをガイドライン射程に含めた判断根拠、`## 関連` プレースホルダーが特定不能と判断した根拠、Scope Assessment で Size=XS のためサブ Issue 分割対象外とした旨) / https://github.com/saitoco/wholework/issues/1054#issuecomment-5131432943

## Overview

`modules/verify-patterns.md` に、不在を検証する Acceptance Criteria (AC) 向けの新しいガイドライン節を追加する。対象は `file_not_contains` 型 (ファイル中の文字列不在) に加え、テーブル・集合中の「条件を満たす要素が無い」型 (vacuous truth パターン) も含む。「0 件になったこと」だけでは「対象が実際に消えた」のか「検証自体が空振りした」のかを結果だけから区別できないため、AC 作成時点で参照点 (変更前の件数・検出リスト・対照群・母集団の非空性のいずれか) を Issue または Spec に記録しておくことを求める。既存の `file_not_contains` ガイドライン (§1 "file_not_contains for negation expressions"、§8 "Policy change Issues") とは「誤検出を避ける書き方」ではなく「検証が空振りしていないことの担保」という観点で異なるため、その違いも明記する。

## Changed Files

- `modules/verify-patterns.md`: `## Processing Steps` 末尾 (`### 25. Measurement-Dependent Rubric AC — Deferral Protocol Guideline` の後、`## Output` の前) に新しい番号付きセクションを追加する

## Implementation Steps

1. `modules/verify-patterns.md` の `## Processing Steps` 末尾、現在の最終セクション (`### 25. ...`) の直後・`## Output` の直前に `### 26. Absence-Verifying Acceptance Conditions — Require a Reference Point` (実装時点で他 Issue により番号がずれていないか要確認。ずれていれば連番を採番し直す) を追加する。既存セクション (英語プローズ + 表 + 例、Japanese 用語は該当箇所のみ inline gloss) の文体に合わせ、Issue 本文「対応方針 (案)」の日本語ドラフトをそのまま転記せず英語プローズへ再構成する。含めるべき内容:
   - (a) 適用範囲: `file_not_contains` 型 (ファイル中の文字列不在) とテーブル・集合の vacuous truth 型 (条件を満たす行/要素が無いことの確認) を対比表で提示する
   - (b) AC 作成時点で記録すべき参照点の4択: 変更前の件数 / 変更前の検出リスト / 対照群 (消えないはずの項目) / 母集団の非空性 (テーブル・集合自体に要素が存在すること)
   - (c) 検証時の原則: 「0 件になったこと」ではなく「期待した差分だけが消えたこと」を確認する
   - (d) 既存ガイドラインとの違い: §1 の `file_not_contains` for negation expressions 行、§8 Policy change Issues は「誤検出を避ける書き方」の話であり、本節は「検証が空振りしていないことの担保」という別の観点である旨を明記する
   - 「参照点」「母集団」という語を本文中に literal な日本語として (英語見出し語への inline gloss として) 含める — Pre-merge の `grep` verify command 2 件がこの2語を対象にするため
   (→ acceptance criteria 1, 2, 3)

## Verification

### Pre-merge

- <!-- verify: rubric "verify-patterns に、不在を検証する AC (ファイル中の文字列不在に加え、テーブル・集合中の条件を満たす要素の不在も含む) では変更前の件数・検出リスト・対照群・母集団の非空性のいずれかを参照点として記録し、0 件になったことではなく期待した差分だけが消えたことを確認する旨のガイドラインが記載されている" --> ガイドラインが追加されている (テーブル/集合の vacuous truth パターンを含む)
- <!-- verify: grep "参照点" "modules/verify-patterns.md" --> `modules/verify-patterns.md` に参照点への言及がある
- <!-- verify: grep "母集団" "modules/verify-patterns.md" --> `modules/verify-patterns.md` にテーブル・集合の非空性 (母集団) への言及がある

### Post-merge

- 不在検証型の AC を含む Issue で `/issue` または `/spec` を実行した際、参照点が記録される (opportunistic)

## Notes

- 発生元 Issue 番号は特定不能 (Issue 本文 `## 関連` 参照)。Related to #1062 (`/verify` 実行時に vacuous truth パターン [Priority=high 以上の行が 0 件で AC が誤って PASS するケース] を踏んだコメントが、本 Issue のガイドライン射程を「テーブル・集合」まで広げる検討材料になった)。
- **言語規約との整合性メモ**: Issue 本文「対応方針 (案)」の日本語ドラフトは提案の骨子として有用だが、`modules/verify-patterns.md` は既存 25 セクション全てが英語プローズ (Japanese は引用例文のみ inline) という一貫した文体を取っている。実装時は日本語ドラフトを直訳転記せず、既存の文体・フォーマット (見出し構造、表、コード例) に合わせて英語で再構成すること。ただし Pre-merge の `grep "参照点"` / `grep "母集団"` を満たすため、この2語は英語見出し語への inline gloss (例: 既存 §25 の "実測データの存在 (the existence of measured/empirical data ...)" と同じパターン) として本文中に literal に残す。
- **Progressive disclosure 原則との整合性確認**: `docs/tech.md` の Progressive disclosure 原則 (capability 固有ガイダンスは eager-load モジュールに直接追加せず Domain file化する。`docs/environment-adaptation.md` line 471, 487 参照) との抵触なし — 本節は特定の capability に紐づかず全 AC に適用される普遍的ガイドラインであるため、`modules/verify-patterns.md` への直接追加が妥当と判断した。分量は既存セクション (§8, §19 相当) と同程度に収め、`docs/environment-adaptation.md` line 487 が目安とする「~1500 tokens/section」を意識する。
- **`scripts/check-eager-load-capability.sh` 抵触確認**: 同スクリプトは `modules/*-adapter.md` 由来の capability 名 (browser / visual-diff / lighthouse) を見出しに含むセクションのみを検知対象とする。新設セクション見出し `Absence-Verifying Acceptance Conditions — Require a Reference Point` はこれらの capability 名を含まないため抵触しない (grep で確認済み)。
- **ドキュメント同期確認**: `grep -rln "verify-patterns" docs/ README.md CLAUDE.md`(sessions/reports/spec/ja 配下を除く) の結果は `docs/structure.md` (モジュール一覧、説明文は変更不要)、`docs/tech.md` (Progressive disclosure の例示、変更不要)、`docs/environment-adaptation.md` (Domain file化ガイドの例示、変更不要) の3件のみで、いずれも本変更による更新は不要と確認した。
- **テスト更新不要確認**: `grep -rl "verify-patterns" tests/` は `verify-heuristics.bats` 等 5 件をヒットしたが、いずれも `verify-executor.md` の実行時挙動 (verify command の解釈・実行) を検証するテストであり、`verify-patterns.md` のガイドライン文面自体はテスト対象に含まれないことを確認した。追加のテスト更新は不要。

## Code Retrospective

### Deviations from Design
- N/A — Implementation followed the Spec's Implementation Steps as written: added `### 26. Absence-Verifying Acceptance Conditions — Require a Reference Point` at the position specified (after `### 25.`, before `## Output`), with no renumbering conflicts (25 remained the last existing section at implementation time).

### Design Gaps/Ambiguities
- N/A — No gaps found. The Spec's element list (a)-(d) mapped directly onto the section content: a comparison table for scope (a), the four reference-point options (b), the verification principle (c), and an explicit differentiation from §1/§8 (d). Both `参照点` and `母集団` appear as literal inline glosses, satisfying the two `grep` pre-merge verify commands.

### Rework
- N/A — Single-pass edit; all three pre-merge verify commands (rubric + 2 grep) passed on first evaluation with no follow-up correction needed.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Documentation-only change: added `### 26.` to `modules/verify-patterns.md` with no code/script changes, since the Issue's scope is a guideline addition.
- Kept the existing English-prose section style (table + numbered decision procedure + examples), matching sections §1-§25, with `参照点` and `母集団` retained as literal inline glosses per the Spec Notes' language-convention guidance.
- Ran the full `bats tests/` suite (not a narrow per-file scope) because Behavioral Change Detection found 5 test files referencing `modules/verify-patterns.md` beyond a single direct counterpart; all 1283 tests passed with no test file changes required.

### Deferred Items
- The post-merge opportunistic AC ("`/issue` or `/spec` records a reference point when authoring a future absence-verifying AC") cannot be verified at code time — it depends on a future Issue actually exercising the new guideline.

### Notes for Next Phase
- All 3 pre-merge ACs (1 rubric + 2 grep) were verified during `/code` and the Issue body checkboxes are already marked `[x]`.
- No documentation sync is required elsewhere — confirmed against `docs/structure.md`, `docs/tech.md`, `docs/environment-adaptation.md` (all 3 references are illustrative examples, unaffected by this change).
- This is a patch-route (XS) Issue with `closes #1054` in the commit — `/verify` should find the commit already merged to `main` and only needs to confirm the post-merge opportunistic condition when relevant future activity occurs.

## Issue Retrospective

`/issue 1054 --non-interactive` による既存 Issue refinement を実行した。

### Ambiguity Points と Auto-Resolve Log

1. **ガイドラインの射程にテーブル・集合の vacuous truth パターンを含めるか**
   - 検出元: 2026-07-29 付コメント (Issue #1062 の `/verify` 実行時に踏んだ「Priority=high 以上の行が 0 件で AC が vacuous truth に PASS する」ケース)。コメントは本 Issue が想定する `file_not_contains` 型 (ファイル中の文字列不在) との構造的な対応関係を対比表で示しつつ、射程を広げるかどうかの確認を求めていた。
   - 判断: **含める。** コメント自身が「参照点 (母集団の非空性、対象の実在) を AC に持たせる」という解決策を既に提示しており、構造的に同一の問題であることが明確だったため、既存パターンから一意に推論可能と判断した。リスクも低い (既存の rubric + grep という AC の形式は変えず、対象範囲の記述を広げるだけ)。
   - 反映内容: Background に該当パターンの例を追加、Purpose・対応方針 (案) に射程拡大の明記と対比表を追加、Pre-merge AC に「母集団」を対象とする grep 補助チェックを追加。
   - 見送った代替案: `file_not_contains` 型に限定し、テーブル/集合パターンは別 Issue として起票する。同じ「参照点が無いと空振りと区別できない」という構造を持つため、同一ガイドライン節で扱う方が一貫性が高いと判断し見送った。

2. **`## 関連` の downstream Issue プレースホルダーが未解消だった**
   - 調査: `docs/spec/`, `docs/sessions/` 配下、および git log を「アセット参照」「9 件」「6 件」等のキーワードで検索したが、本 Issue の Background が記述する具体的なスキャンシナリオ (スキャン実行前 9 件 → 実行後 6 件) に対応する Issue をこのリポジトリ内に見つけられなかった。
   - 判断: 発生元 Issue 番号は特定不能と明記する形に置き換えた。プレースホルダーをそのまま残すと壊れた Markdown リンクとしてレンダリングされるため。
   - 別途、コメントで言及された Issue #1062 は本 Issue の直接の発生元ではないが、ガイドライン射程の検討材料として `Related to #1062` の形で明記した。

### Acceptance Criteria の変更理由

- Pre-merge の rubric AC の文言に「ファイル中の文字列不在に加え、テーブル・集合中の条件を満たす要素の不在も含む」を追加し、射程拡大を verify 時に判定できるようにした。
- Pre-merge に `grep "母集団" "modules/verify-patterns.md"` を追加した。rubric との併用ガイドライン (`modules/verify-patterns.md` §9) に沿い、rubric が誤って PASS した場合の機械的なセーフティネットとする。
- Post-merge の条件は変更なし (射程拡大によって observation の対象が変わるものではないため)。

### Scope Assessment

Size=XS のため、サブ Issue 分割の評価対象外 (非対話モードでも High-Stakes スキップの判定に該当しない規模)。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 射程拡大 (テーブル・集合の vacuous truth を含めるか) の判断を、コメント側が既に解決策の骨子を提示していたことを根拠に auto-resolve できた。Auto-Resolve Log に採用理由と見送った代替案の両方が残っており、後から覆せる形になっている。
- `## 関連` の downstream Issue プレースホルダーが未解消だった点を検出し、リポジトリ内を検索したうえで「特定不能」と明記する形に置き換えている。プレースホルダーを放置すると壊れたリンクとしてレンダリングされるため、妥当な処理。

#### spec
- Spec の element list (a)-(d) が実装内容に 1:1 で対応しており、Design Gaps は N/A。`参照点` / `母集団` を literal な inline gloss として置く設計が、2 つの `grep` AC をそのまま満たす形になっていた。AC と実装の対応が設計時点で担保されていた good case。

#### code
- Deviations / Design Gaps / Rework すべて N/A。single-pass edit で pre-merge AC 3 件が初回評価で PASS。
- 節番号 (`### 26.`) の挿入位置に採番衝突がないことを実装時に確認しており、後続節の繰り上げが発生しなかった。

#### review
- patch route (XS) のため review フェーズなし。

#### merge
- patch route のため merge フェーズなし (main 直コミット)。

#### verify
- pre-merge 3 件すべて PASS、FAIL / UNCERTAIN なし、auto-retry 発火なし。
- post-merge の opportunistic 1 件は未チェックのまま `phase/verify` 留置 (設計どおり)。

### Improvement Proposals

- **`run-auto-sub.sh` の spec dispatch が Size を見ておらず、`/auto` の「XS は spec 不要」規定と食い違う**: `skills/auto/SKILL.md` Step 3 は単一 Issue 経路について「**Size is XS**: Spec not needed — skip spec and proceed to Step 4」と明記している。一方 `scripts/run-auto-sub.sh` (L828-837) の spec dispatch 条件は「`phase/ready` が無く、かつ `phase/code` / `phase/review` / `phase/merge` / `phase/verify` / `phase/done` のいずれも無い」だけで、**Size を判定材料に含めていない**。このため `--batch` / XL 経路では XS Issue でも spec フェーズが走る。本 Issue で実測: Size=XS かつ `phase/issue` の状態で `run-auto-sub.sh 1054` を実行したところ、`docs/spec/issue-1054-verify-absence-reference-point.md` が作成された (commit `7ebce2dd`)。
  - **影響 1 (前提の齟齬)**: `skills/auto/SKILL.md` Step 4b は「The XS patch route does not go through the `/spec` phase, so no Spec file exists」という前提で、Spec を新規作成して issue retrospective を転記する手順になっている。batch 経路ではこの前提が成り立たない。今回は Step 4b の冪等性チェック (Spec に `## Issue Retrospective` 見出しがあるか) が効いて二重転記は避けられたが、前提と実態のずれは残る。
  - **影響 2 (実行コスト)**: XS Issue に対して不要な spec フェーズ (`claude -p` の 1 セッション) が走る。batch で XS を多数処理する場合に累積する。
  - **判断が必要な点**: どちらを正とするか。(a) `run-auto-sub.sh` に Size 判定を足して規定に合わせる、(b) 規定側を「XS でも spec を走らせる」に改め Step 4b を「Spec が無ければ作る」から「Spec が無ければ作る、あれば追記する」に明確化する、(c) XS の spec を任意とし設定キーで制御する。なお本 Issue に限れば Spec があったことで Code Retrospective / Phase Handoff / issue retrospective 転記先が確保され、`/verify` の情報源としても有用だったため、(b) にも実利はある。

### 観察 (Issue 化は保留)

- 本 Issue の実行は kill を含むオーケストレーション異常がゼロで、issue → code → verify が素直に完走した。#1066 (Size L、kill 3 回) との対比から、フェーズ数と 1 フェーズあたりの実行時間が短いほど完走率が高いという既存の観察を補強するデータ点になる。
