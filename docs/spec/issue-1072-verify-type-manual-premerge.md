# Issue #1072: audit/auto: verify-type: manual の pre-merge 拡張を下流の集計と分類器に反映

## Overview

#1059 で `verify-type: manual` タグの意味論が「post-merge 専用」から「pre-merge (`ac-tier: preview` 併用時) にも配置可能」へ拡張されたが、このタグ値を消費する `skills/audit/SKILL.md` の Manual Waiting Count、`skills/auto/SKILL.md` の Pending manual confirmation 集計、および `modules/verify-classifier.md` の自己記述 (Purpose / Input / Processing Steps) が旧セマンティクスのまま据え置かれている。本 Issue はこれら 3 箇所を新セマンティクスに追従させ、pre-merge の manual preview AC が「人間の対応待ち」として誤カウントされる状態を解消する。

## Reproduction Steps

1. `.wholework.yml` で `capabilities.pr-preview: true` を設定したプロジェクトで、`/issue` が Pre-merge に URL/UX 系の manual AC を `<!-- ac-tier: preview --> <!-- verify-type: manual -->` として配置する (`skills/issue/SKILL.md` Step 4 の pre-merge-preview tier、manual subcase)。
2. 当該 Issue が `/review` → `/merge` を経て `phase/verify` に到達する。pre-merge の manual preview AC は `/review` 時に人間が preview URL 上で確認済みだが、`/verify` Step 5 の skip rule により checkbox は unchecked のまま恒久的に残る (#1059 の設計)。
3. `/audit stats --retention` (Manual Waiting Count) または `/auto --batch` 完了レポート (Pending manual confirmation) を実行する。
4. 観測: 既に `/review` で確認済みの pre-merge manual preview AC が、post-merge の「未対応 manual AC」と区別されずに N / `MANUAL_N` へ計上される。

## Root Cause

`skills/audit/SKILL.md` の Manual Waiting Count と `skills/auto/SKILL.md` の Pending manual confirmation は、いずれも Issue 本文全体を対象に `- [ ]` + `verify-type: manual` を走査しており、`ac-tier: preview` タグによる pre-merge 配置を除外する記述を持たない。この 2 箇所は #1059 (`verify-type: manual` の pre-merge 拡張) より前に書かれたロジックで、当時は `verify-type: manual` が常に post-merge を意味していたため除外条件が不要だった。`modules/verify-classifier.md` の Purpose / Input / Processing Steps も同様に「post-merge condition」を前提とした記述のまま残っており、実際のタグ意味論 (`/issue` Step 4 が pre-merge にも `verify-type: manual` を付与し得る) と乖離している。この乖離は `/review #1068` の review retrospective で SHOULD/CONSIDER として検出されたが、PR スコープ外のため据え置かれ、フォローアップ Issue 化もされていなかった。

## Changed Files

- `modules/verify-classifier.md`: L3 タグライン、Purpose (L7)、Input (L13)、Processing Steps (L17) を、`verify-type: manual` が `/issue` Step 4 の pre-merge-preview tier (`ac-tier: preview` 併用) 経由で pre-merge にも付与され得る事実を反映した記述に更新
- `skills/audit/SKILL.md`: § Manual Waiting Count のスキャン定義 (L365) と N1-N4 内訳の step 2 (L372) を、`ac-tier: preview` を伴う行を N の母集団から除外する記述に更新
- `skills/auto/SKILL.md`: § Pending manual confirmation の `MANUAL_N` カウント定義 (L1267) を、`ac-tier: preview` を伴う行を除外する記述に更新
- `docs/structure.md` [Steering Docs sync candidate]: Modules 表の `modules/verify-classifier.md` 一行説明 (L111 "post-merge condition verifiability classification") が同じ「post-merge 専用」前提の文言のため、上記 `verify-classifier.md` の Purpose 更新と整合するか確認し、必要なら更新する。更新する場合は `docs/translation-workflow.md` の同期手順に従い `docs/ja/structure.md` (L104) も同期する

## Implementation Steps

1. `modules/verify-classifier.md` の L3 タグライン・Purpose・Input・Processing Steps を更新し、`verify-type: manual` の pre-merge 拡張 (`ac-tier: preview` 併用時) を反映する (→ acceptance criteria 3)
2. `skills/audit/SKILL.md` § Manual Waiting Count のスキャン定義 (L365) と step 2 (L372) を更新し、`ac-tier: preview` を伴う行を N の母集団から除外する (parallel with 1, 3) (→ acceptance criteria 1)
3. `skills/auto/SKILL.md` § Pending manual confirmation の `MANUAL_N` カウント (L1267) を更新し、`ac-tier: preview` を伴う行を除外する (parallel with 1, 2) (→ acceptance criteria 2)
4. `docs/structure.md` の Modules 表 `modules/verify-classifier.md` 一行説明を確認し、Step 1 の Purpose 更新と整合しない場合は更新する。更新する場合は `docs/ja/structure.md` も同期する (after 1)
5. `bats tests/*.bats` を実行し、既存テストがすべて PASS することを確認する (after 1, 2, 3, 4) (→ acceptance criteria 4)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/audit/SKILL.md の Manual Waiting Count が、集計対象を Post-merge セクション配下に限定するか、ac-tier: preview タグを持つ AC を除外する記述に更新されている" --> `/audit` の Manual Waiting Count が pre-merge manual preview AC を除外する
- <!-- verify: rubric "skills/auto/SKILL.md の Pending manual confirmation 集計が、集計対象を Post-merge セクション配下に限定するか、ac-tier: preview タグを持つ AC を除外する記述に更新されている" --> `/auto` の Pending manual confirmation 集計が pre-merge manual preview AC を除外する
- <!-- verify: rubric "modules/verify-classifier.md の Purpose / Input / Processing Steps が、verify-type: manual タグが post-merge 専用ではなく pre-merge (ac-tier: preview 併用時) にも付与されうる事実を反映した記述に更新されている" --> `verify-classifier.md` の記述が pre-merge 拡張を反映している
- <!-- verify: command "bats tests/*.bats" --> 既存の bats テストがすべて PASS する

### Post-merge
- pre-merge に manual preview AC を持つ Issue が `phase/verify` にある状態で `/audit stats --retention` を実行し、Manual Waiting Count に当該 AC が含まれないことを確認する (本 repo は `.wholework.yml` で `capabilities.pr-preview` 未設定のため、自然発生する対象 Issue が存在しない — 検証時は `ac-tier: preview` + `verify-type: manual` を持つ AC を含む Issue を一時的に構築するか、`capabilities.pr-preview: true` を設定した検証用シナリオで確認する) <!-- verify-type: manual -->

## Notes

- **Tag/enum semantic extension consumer sweep** (`modules/verify-classifier.md` を変更するため実施): `grep -rn "verify-type: manual" skills/ modules/ scripts/` で全 consumer を洗い出した。Issue 本文が挙げる 3 箇所 (`skills/audit/SKILL.md`、`skills/auto/SKILL.md`、`modules/verify-classifier.md`) 以外に該当した箇所は以下のとおりで、いずれも修正不要と判断した:
  - `modules/l0-surfaces.md` (L179, L222 — `type=verify-executability` マーカー): `/verify` Step 8b は pre-merge preview AC を Step 5 で既にスキップした後の post-merge AC のみを扱うため、「post-merge AC」という記述は現状でも正しい
  - `modules/verify-patterns.md` (L411, L423, L449, L539) と `skills/triage/skill-dev-verify-audit.md` (L228, L272, L275): いずれも新規 AC 執筆時の一般的なガイダンス (「他に手段がなければ manual」という fallback 推奨) であり、`ac-tier: preview` という狭いケースに毎回言及する必要はない
  - `skills/issue/SKILL.md` L235 (operate route 判定): 「`### Post-merge` 配下の条件が」と明示的にスコープ済みのため対象外
- **fix 方針の選択**: Issue の Pre-merge AC 1・2 は「Post-merge セクション配下に限定」と「`ac-tier: preview` タグを除外」の 2 案を許容している。#1059 の Spec retrospective (`docs/spec/issue-1059-pre-merge-preview-manual-ac.md` L136) も同じ 2 択を記録している。本 Spec は後者 (`ac-tier: preview` タグ除外) を採用した — 理由: 現行設計では pre-merge に `verify-type: manual` が付与される経路が `ac-tier: preview` 経由のみ (`skills/issue/SKILL.md` Step 4) であり、タグベースの除外の方が除外理由を自己文書化できる。また `skills/audit/SKILL.md` の Manual Waiting Count は元々セクション非依存の LLM プロース走査であり (`docs/reports/manual-ac-retype-d3.md` #491 の記録参照)、セクション境界へのアンカーより属性タグでの除外の方が既存の記述スタイルと整合する。
- **docs/structure.md sync candidate**: `modules/verify-classifier.md` の一行説明 (L111) が同じ「post-merge 専用」前提の文言を持つため、Steering Docs sync candidate として Changed Files に記載した。実際の更新要否は `/code` が判断する。
- **Post-merge AC の検証手段注記**: Issue 本文の Autonomous Auto-Resolve Log に記載のとおり、本 repo には `capabilities.pr-preview` を有効化した Issue が存在せず、Post-merge AC が想定する状態が自然発生しない。検証時は一時構築または capability 一時有効化が必要である旨を Verification > Post-merge に転記済み。

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective コメント (`/issue --non-interactive` 実行時点)。#1072 起票時の非対話モード自動判断ログ (Post-merge AC の検証手段注記、「skill 自己変更 AC の manual/observation 分類」提案は本 Issue に不適用と判断、行番号の現状への更新) を記録したもの。Issue 本文の Autonomous Auto-Resolve Log と同内容の転記であり、本 Spec の設計判断に新規の変更は生じていない。(https://github.com/saitoco/wholework/issues/1072#issuecomment-5304571477)

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-4 を Spec のとおり実施した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `docs/structure.md` / `docs/ja/structure.md` の Modules 表一行説明 ("post-merge condition verifiability classification" / 「マージ後条件の検証可能性分類」) は、`modules/verify-classifier.md` の Purpose 本文が pre-merge 拡張を反映する記述に変わった以上、一行要約だけが旧前提のまま残ると同じ種類のドリフトを再発させるため、更新対象とした (Spec Notes で「実際の更新要否は `/code` が判断する」とされていた判断ポイント)
- `modules/verify-classifier.md` の既存の `auto|opportunistic|manual` タグ列挙 (`observation` が抜けている、本 Issue とは無関係の既存ギャップ) は変更しなかった — 本 Issue のスコープは pre-merge 拡張の反映のみ

### Deferred Items
- Post-merge AC (`/audit stats --retention` 実行時に pre-merge manual preview AC が Manual Waiting Count から除外されることの確認) は、本 repo に `capabilities.pr-preview` を有効化した Issue が存在しないため、検証用シナリオの一時構築が必要 — Issue 本文の Autonomous Auto-Resolve Log に記載済み

### Notes for Next Phase
- Post-merge AC の検証には `ac-tier: preview` + `verify-type: manual` を持つ AC を含む Issue を一時的に構築するか、`capabilities.pr-preview: true` を設定した検証用シナリオが必要
- 修正した 3 ファイル (`skills/audit/SKILL.md`、`skills/auto/SKILL.md`、`modules/verify-classifier.md`) 以外に `verify-type: manual` を参照する箇所は、Spec Notes の consumer sweep (`grep -rn "verify-type: manual" skills/ modules/ scripts/`) で洗い出し済み — いずれも修正不要と判断済み
