# Issue #1350: verify: observation AC の evidence collection に実地証跡パターンを追加

## Overview

`/verify` Step 8c (observation post-merge condition の evidence collection) は現状 best-effort な調査とされているのみで、実際に有効だった調査手法 — git blame + post-fix `docs/sessions/*/session.md` 横断検索、AC の文言に一致する bats テストケースの `bats -f` サブセット実行、`docs/reports/orchestration-recoveries.md`/`.tmp/auto-events.jsonl` 等の実運用ログへの直接 grep、`.wholework/verify-commands/{name}.md` へのオンザフライ軽量実地テスト構築 — が `modules/l0-surfaces.md` にも `modules/verify-classifier.md` にも明文化されていない。本 Issue はこれらの実証済みパターンを標準の evidence source として明文化し、`/verify` 実行時の evidence collection の質と再現性を上げる。

## Changed Files

- `modules/verify-classifier.md`: 既存の `### observation Type: Firing Likelihood Check (before assignment)` セクションの直後、`### Tag Assignment Example` セクションの直前に、新規 `### observation Type: Evidence Collection Patterns` セクションを追加する。4手法をテーブル形式で整理し、いずれも best-effort であり証跡が見つからない場合は既存の UNCERTAIN/SKIPPED 方針を維持する旨を明記する
- `skills/verify/SKILL.md`: Step 8c "2. Evidence collection" の既存4項目箇条書きの末尾に、`modules/verify-classifier.md` § "observation Type: Evidence Collection Patterns" への参照ブレットを1行追加する (新パターンが実際の `/verify` 実行時に参照されるようにするため — Changed Files 判定・grep 済み、以下 Notes 参照)

## Implementation Steps

1. `modules/verify-classifier.md` に `### observation Type: Evidence Collection Patterns` セクションを新規追加する。既存の `### observation Type: Firing Likelihood Check (before assignment)` セクションの直後、`### Tag Assignment Example` セクションの直前に挿入する。以下4手法をテーブルで整理する: (a) `git blame` + post-fix `session.md` 横断検索 — `session=next` 系条件向け, (b) AC の文言が指すシナリオに一致する bats テストケースを `bats tests/foo.bats -f "test name"` で直接特定・実行, (c) `docs/reports/orchestration-recoveries.md` や `.tmp/auto-events.jsonl` 等の実運用ログファイルへの直接 grep, (d) `.wholework/verify-commands/{name}.md` へのオンザフライ軽量実地テスト配置。末尾に「いずれも best-effort であり、証跡が見つからない場合は無理に PASS 判定せず UNCERTAIN または SKIPPED を維持する」という既存方針との整合を明記する一文を追加する (→ 受入条件 AC1, AC2, AC3, AC4)
2. `skills/verify/SKILL.md` Step 8c の "2. Evidence collection" 箇条書き (既存4項目) の末尾に、Step 1 で追加したセクションへの参照ブレット (`git blame`+`session.md`横断検索/bats サブセット実行/実運用ログ直接 grep/オンザフライ軽量実地テスト構築のポインタ) を1行追加する (after 1)

## Verification

### Pre-merge
- <!-- verify: rubric "modules/l0-surfaces.md または modules/verify-classifier.md の observation AC evidence collection に関する記述に、git blame と post-fix の docs/sessions/*/session.md 横断検索を用いて session=next 系 observation AC の実発生を裏取りする手法が追加されている" --> git blame + session.md 横断検索の手法が明文化されている
- <!-- verify: rubric "同箇所に、AC の文言が指すシナリオと一致する bats テストケースを bats -f (フィルタ) で直接特定・実行して証跡とする手法が追加されている" --> bats サブセット実行による裏取り手法が明文化されている
- <!-- verify: rubric "同箇所に、docs/reports/orchestration-recoveries.md や .tmp/auto-events.jsonl 等の実運用ログファイルへ直接 grep して observation AC の実発生パターンを確認する手法が既存の evidence source 一覧に整理されている" --> 実運用ログへの直接 grep が evidence source として整理されている
- <!-- verify: rubric "これらの手法がいずれも best-effort であり、証跡が見つからない場合は無理に PASS 判定せず UNCERTAIN または SKIPPED を維持する既存方針と矛盾しないことが明記されている" --> 既存の保守的な judgment 方針との整合が明記されている

### Post-merge
- 次回 `/verify` が observation AC を処理する際、追加された evidence source が実際に参照され、UNCERTAIN/SKIPPED 率が改善することを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **配置先の判断根拠 (Issue 本文の「l0-surfaces.md または verify-classifier.md」からの自動解決)**: Issue 本文は追加先として両モジュールを候補に挙げているが、`modules/l0-surfaces.md` は Purpose 上「L0 (GitHub state) サーフェス」に scope が限定されており (`## L0 Surface SSoT` テーブルは Issue title/body/comments/labels 等の GitHub 状態のみを列挙)、本 Issue が追加する4手法 (git blame, session.md, bats, 実運用ログファイル) はいずれも GitHub L0 サーフェスではなくローカル成果物である。一方 `modules/verify-classifier.md` は既に `### observation Type: ...` という同型のサブセクション群 (Event Values and Syntax / Population Definition / Firing Likelihood Check) を持ち、Purpose 冒頭で "Expected to also be referenced by `/verify` in the future" と明記済みで、`skills/verify/SKILL.md` からも既に2箇所 (Patch Route CI Verification Note, session=next semantics) が `§` 参照している。この2点から `modules/verify-classifier.md` を追加先として一意に決定した (SPEC_DEPTH=light のため、Issue 本文の更新・ユーザー確認は行わず本 Notes に記録するのみ)。
- **`skills/verify/SKILL.md` への参照ブレット追加について**: Issue 本文の Pre-merge AC はいずれも `modules/l0-surfaces.md` または `modules/verify-classifier.md` の記述内容のみを対象とした rubric であり、`skills/verify/SKILL.md` の変更自体は AC の直接要求ではない。しかし Step 8c の実際の evidence collection 箇条書きは `skills/verify/SKILL.md` 側にインラインで存在し、`modules/verify-classifier.md` 側にドキュメントを追加するだけでは `/verify` 実行時に参照されない「死んだドキュメント」になり、本 Issue の Purpose (「/verify 実行時の evidence collection の質と再現性を上げる」) を実質的に達成できない。既存4項目の削除・変更は行わず、末尾に参照ブレットを1行追加するのみの最小差分とした。
- **Steering Docs sync candidate 確認済み (変更不要)**: `grep -rln "verify-classifier.md" modules/ scripts/ tests/` で `modules/observation-trigger.md` / `modules/size-workflow-table.md` / `modules/verify-patterns.md` / `tests/verify-executor.bats` の4件を検出したが、いずれも "Patch Route CI Verification Note" または `event=`/`config=`/`session=next` 構文に関する既存セクションへの参照であり、本 Issue が追加する新セクションとは無関係。変更不要と判断した。
- **`docs/workflow.md` / `docs/guide/` 確認済み (変更不要)**: `grep -n -i "step 8c\|evidence collection\|observation AC"` で両者にヒットなし。Step 8c の evidence collection 手法の詳細レベルはこれらのドキュメントの記述粒度を超えているため、同期不要と判断した。
- **`tests/verify.bats` 更新不要**: 既存の `@test "Step 8c: evidence collection lists auto logs, auto-events.jsonl, and opportunistic-search.sh"` は `step8c_section` 内の `/auto` / `auto-events.jsonl` / `opportunistic-search.sh --event` の3文字列存在のみを検証しており、本 Issue は該当4項目箇条書きを削除・変更せず末尾に追記するのみのため、既存テストへの影響はない。Issue 本文の Pre-merge AC もテストファイルを対象としていないため、Changed Files には含めない。

## Consumed Comments

前フェーズ以降の新規コメントなし。
