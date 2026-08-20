# Issue #1401: verify: Opportunistic Verification (Step 14) の単一Issue実行あたりスイープコストを改善検討

## Overview

`modules/opportunistic-verify.md` の Step 14 は、`opportunistic-verify: true` が設定されたプロジェクトで `scripts/opportunistic-search.sh` を呼び出し、`phase/verify` ラベル付き Issue から `verify-type: opportunistic` 条件を横断検索する。`/auto --batch 1395 1382 1390 1391` (session `4899-1787037881`, 2026-08-18) で単一 Issue の `/verify` 実行のたびにこの Step 14 が計4回実行され、いずれも候補は対象実行のスコープ外で SKIP 判定以外の結果はゼロ件だった一方、候補母集団は 73件→105件に増加した。

本 Issue は `<!-- implementation-type: metadata-only -->` — `scripts/opportunistic-search.sh` の `--facts`/`--context-file` フィルタリング精度改善案、または Step 14 の実行頻度・対象範囲見直し案のいずれか (実装は本 Issue のスコープ外でよい) を、Issue 本文に具体性を持って追記することが唯一の成果物であり、リポジトリへの実装差分は伴わない。

## Changed Files

None (repository files)。成果物は Issue #1401 本文自体 (GitHub state、リポジトリ外) のみ。Diff-less Axis (operate route) の判定根拠は Notes を参照。

## Implementation Steps

1. 以下2軸の調査結果 (Spec 作成時点で `scripts/opportunistic-search.sh` / `modules/opportunistic-verify.md` / 5箇所の呼び出し元 SKILL.md を確認済み) を、grep/Read で再確認 (Spec 作成からの時間経過による差分がないか) したうえで、改善提案文を作成する。両軸とも具体的な対象ファイルを特定できているため、両方を提案文に含めることを基本とする (再確認で前提が崩れていた場合は Issue 本文 Notes 相当の記載に置き換えて片方のみ採用してもよい):
   - **フィルタリング精度**: opportunistic モードの一致条件 (`--event` 未指定時) は `verify-type: opportunistic` タグ + 呼び出し元スキル名の条件文内リテラル部分一致 (`scripts/opportunistic-search.sh:386` `grep -F "$SKILL_NAME"`) のみが必須ゲートで、内容的関連性を検証する唯一の仕組みである `--context-file` の `keyword=` ゲート (`scripts/opportunistic-search.sh:431-452`) は AC 側の任意属性であり、`keyword=` を付けていない `verify-type: opportunistic` AC (現状 `keyword=` は必須の記法規約になっていない) には一切効かない。改善提案候補: 新規に起票する `verify-type: opportunistic` AC に対して `keyword=` 属性を必須の記法規約とする — 対象ファイルは `skills/issue/SKILL.md` の AC 記法規約/verify-type タグ付けセクションおよび `modules/verify-classifier.md` のドキュメント記述。
   - **実行頻度・対象範囲**: Step 14 は `opportunistic-verify: true` フラグのみをゲートに、5箇所の呼び出し元 (`skills/spec/SKILL.md`, `skills/code/SKILL.md`, `skills/issue/SKILL.md` ×2, `skills/review/SKILL.md`, `skills/verify/SKILL.md`) それぞれで無条件に発火し、バッチ/セッション単位の重複排除は存在しない。1 Issue が `/auto` フルパイプラインを通過するだけで約4回、`/auto --batch N1..Nk` はさらに k 倍のスイープが発生する構造。改善提案候補: セッション/バッチ単位の最小間隔・重複排除ゲートを追加する — 対象ファイルは `modules/opportunistic-verify.md` Step 1 冒頭、または `/auto` バッチオーケストレーション側 (`scripts/run-auto-sub.sh` 等)。
   (→ AC1)
2. Issue #1401 本文を更新する: `gh issue view 1401 --json body -q .body` で現在の本文を取得する (取得失敗時は本文を上書きせず中断する)。ステップ1で確定した提案文を `## Background` または `## Purpose` セクションに、対象ファイルが特定できる具体性を保ったまま追記する。更新後の本文を `.tmp/issue-body-1401.md` に Write ツールで書き出し、`${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh 1401 .tmp/issue-body-1401.md` で反映し、`.tmp/issue-body-1401.md` を削除する。(after 1) (→ AC1)

## Verification

### Pre-merge

- <!-- verify: rubric "Issue #1401 の本文 (Background/Purpose に追記された内容を含む) に、scripts/opportunistic-search.sh の --facts/--context-file フィルタリング精度の改善案、または Step 14 の実行頻度・対象範囲の見直し案のいずれかが、対象とする変更内容が特定できる具体性で記載されている。実装自体は本 Issue のスコープに含めなくてもよい" --> フィルタリング精度の改善案、または実行頻度・対象範囲の見直し案のいずれかが、本 Issue 本文に具体的に追記されている (実装は本 Issue のスコープに含めなくてもよい)

### Post-merge

なし (Issue 本文 `### Post-merge` に準拠)

## Notes

- **Diff-less / operate route の判定根拠**: `## Changed Files` にリポジトリファイルのエントリなし、`## Implementation Steps` の各項目は調査 (grep/Read) と Issue 本文編集 (`gh issue view` / `gh-issue-edit.sh`) のみで、コミットを伴う手順はない。`/spec` Step 18 の Diff-less Axis 判定で `ROUTE=operate` に解決されることを想定している。
- **rubric AC の評価範囲との整合**: `modules/verify-executor.md` § Rubric Command Semantics により、grader のデフォルト入力範囲は Issue body + git diff + rubric 文中で明示したファイル。本 Issue は git diff が空 (operate route) のため、grader は実質 Issue 本文のみで判定する。AC の評価対象を「本 Issue 本文への追記」に明示的に固定しているのはこの制約と整合するための設計であり (`/issue` フェーズの Issue Retrospective で既に説明済み)、Spec 側で変更の必要なし。
- **read-then-write ガード**: Implementation Step 2 (Issue #1401 本文更新) は read-then-write 操作。`gh issue view` の取得失敗時は本文を上書きせず中断することを明示している。
- **audit/investigation-type 判定**: 否 — 本 Issue は単一の論点 (Step 14 のスイープコスト) に対する改善提案の起草であり、`/spec` Step 6 が定義する「複数の既存項目を定義済みカテゴリに分類する」条件を満たさない。ただし判断根拠として引用する識別子 (`scripts/opportunistic-search.sh:386` 等の行番号を含む) は本 Spec 作成時点ですべて Read ツールで実在・内容確認済み。`/code` 実行時、Spec 作成からの時間経過で該当箇所が変更されている可能性があるため、Implementation Step 1 で再確認を明示的に求めている。
- **Issue 本文との食い違い**: なし。Background の記述 (hit rate 実測値、`FACTS_CANDIDATE_LIMIT=30` が精度改善ではなく population-size safety valve である旨、`modules/opportunistic-verify.md` の Purpose 記述) はいずれも本 Spec 作成時の調査結果と一致した。
- **SPEC_DEPTH=light**: Step 7 (Ambiguity Resolution) は未実施。Issue 本文のあいまい性は `/issue` フェーズの Issue Retrospective (Auto-Resolve Log) で既に解決済み。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: Issue Retrospective — Triage AC 監査コメント (AC1 の rubric が起票時点で常時 PASS してしまう Pattern 2 型問題の指摘) を踏まえ、AC1 (hit rate 定量化) を削除し、AC2 (改善案提示) の rubric text に「本 Issue 本文への追記」という評価対象の明示を追加、Pre-merge/Post-merge のセクション分割と `implementation-type: metadata-only` マーカーを付与した判断根拠を記録。本 Spec 作成時点の Issue 本文には既に反映済みで、追加で取り込むべき新規情報はなし。 / https://github.com/saitoco/wholework/issues/1401#issuecomment-5358812202
- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: 直前コメントの `### Consumed Comments` サブセクション記載漏れの追記 (対象: issuecomment-5336448321、Triage AC 監査コメント本体)。本 Spec 作成に新規に影響する情報はなし。 / https://github.com/saitoco/wholework/issues/1401#issuecomment-5358814948

- saito / MEMBER / first-class / <!-- wholework-event: type=execution-log phase=code issue=1401 --> / https://github.com/saitoco/wholework/issues/1401#issuecomment-5359026525
## Code Retrospective

### Deviations from Design
- なし。Spec の Implementation Steps を順序どおりに実行した。

### Design Gaps/Ambiguities
- なし。Spec 作成時点で確認済みの行番号・呼び出し箇所は `/code` 実行時点でも変化がなく、再確認は形式的な裏取りで完了した。

### Rework
- なし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 改善提案は2軸 (フィルタリング精度 / 実行頻度・対象範囲) の両方を Issue 本文に採用した。Spec 作成時点の前提 (行番号・呼び出し箇所) が `/code` 実行時点でも崩れていなかったため。
- rubric AC の判定は、追記内容が対象ファイルを特定できる具体性を持つことを根拠に PASS とし、チェックボックスを `[x]` に更新した。

### Deferred Items
- 改善提案自体の実装 (`keyword=` 属性必須化、セッション/バッチ単位の重複排除ゲート追加) は本 Issue のスコープ外。Issue 本文の「### 改善提案」に記載した対象ファイルを参照し、別 Issue での実装を想定。

### Notes for Next Phase
- 本 Issue は operate route (diff-less) のため、`/verify` の Post-merge AC はなし。Pre-merge の rubric AC は本フェーズで PASS 済み・チェック済み。
