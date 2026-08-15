# Issue #1126: verify-executor: CI Reference Fallback の同一性未確認時を UNCERTAIN に倒す

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (/issue フェーズ): Triage AC audit の指摘を反映し、Pre-merge AC #3 の verify command を `grep "UNCERTAIN"` (常時 PASS してしまうパターン) から `section_contains "modules/verify-executor.md" "CI Reference Fallback" "同一性"` (実装後にのみ PASS する) へ修正済みという記録。Issue 本文には既に反映済みのため、本 Spec 側で追加対応は不要 / https://github.com/saitoco/wholework/issues/1126#issuecomment-5303044732

## Overview

`modules/verify-executor.md` の CI Reference Fallback 節 (safe mode + PR 番号ありのときに `command` 型 verify command を CI ジョブの実行結果で代替検証する仕組み) は、AC の `command` 文字列と CI ジョブ名を推論ベースで突き合わせ (Step 2)、一致したジョブが SUCCESS であれば無条件に PASS を返す (Step 3)。しかし Step 2 の推論マッチは「それらしい名前のジョブ」を選ぶだけで、そのジョブが実際に AC の要求する対象 (同一の入力・同一のテストファイルなど) を実行したかどうかは確認しない。ジョブ名は近いが実行範囲が異なるケースで false PASS が生じうる。

`verify-executor.md` の他のあいまい判定箇所 (`html_check` のセレクタ解析失敗、`mcp_call` のツール未検出、`github_check` の allowlist 外など) はすべて UNCERTAIN 側に倒す設計で一貫しているが、CI Reference Fallback の SUCCESS 判定のみ PASS 側に倒れている。本 Issue は、ジョブの同一性 (検証対象の一致) が確認できない場合に UNCERTAIN へ倒す指針を追加し、この非対称性を解消する。

## Reproduction Steps

1. Issue の Pre-merge AC に `<!-- verify: command "bats tests/foo.bats" -->` がある
2. `/review` が safe mode (PR 番号あり) で CI Reference Fallback を通る
3. Step 2 の推論マッチが、command 文字列中の "bats" 等のキーワードだけで CI ジョブ (例: `test-scripts`) を候補に選ぶ — このジョブが実際に `tests/foo.bats` を実行対象に含むかどうかは確認されない
4. 候補ジョブが SUCCESS であれば、現行の Step 3 は無条件に PASS を返す。仮に `test-scripts` が `tests/bar.bats` のみを実行しており `tests/foo.bats` を一度も実行していなくても、この false PASS を検出する手段が現状ない

## Root Cause

Step 3 の「Related job is SUCCESS → PASS」分岐は、CI ジョブの SUCCESS ステータスをそのまま PASS に変換しており、そのジョブの実行範囲が AC の検証対象を含むことを確認する手続きを経ない。手前の Step 2 は "inference-based" と明記された名前・キーワード照合に過ぎず、対象の一致を保証しない。同モジュール内の他の不確実判定箇所はすべて UNCERTAIN に倒す設計で統一されているが、この分岐だけが PASS 側に倒れる非対称な設計になっている。

## Changed Files

- `modules/verify-executor.md`: CI Reference Fallback 節 (L352-378) に Step 2a (同一性確認) を追加し、Step 3 の SUCCESS 分岐を「同一性確認済み → PASS」「同一性未確認 → UNCERTAIN」に分割。Details 記録形式も更新
- `tests/verify-executor.bats`: 同一性確認済みで PASS になる記述、および同一性未確認で UNCERTAIN になる記述 (negative case) を検証する `@test` を追加。既存の grep ベースのドキュメント内容検証パターン (`$VERIFY_EXECUTOR` 変数、`grep -q` によるプレーンテキスト照合) を踏襲。既存 `.bats` ファイルへの追記のみで bash compat 上の懸念なし

## Implementation Steps

1. `modules/verify-executor.md` の CI Reference Fallback 節 (L352-378) を修正する (→ 受入条件1, 2, 3)
   - Step 2 (推論マッチ) の直後に新しい Step "2a" を挿入する。命名は既存の Step "2a" (`--when` modifier, L25) に倣う。内容: 「SUCCESS 結果を PASS に変換する前に、対象の identity (同一性) を確認する」ことを明記し、確認手段として次の3つを列挙する (いずれか1つでも確認できれば「同一性確認済み」と扱う — 厳格化しすぎて UNCERTAIN が多発しないためのバランス。Issue 本文の懸念に対応):
     - Run command containment: 該当ジョブを定義する `.github/workflows/*.yml` 内のステップの実行コマンドが、AC の `command` 文字列の対象を包含しているか (例: ワークフロー側が `bats tests/` を実行していれば `bats tests/setup-labels.bats` を包含する)
     - Exact job name match: Step 2 で推論されたジョブ名が部分一致ではなく完全一致であるか
     - Execution target path containment: ワークフローステップの実行対象パス (ディレクトリ/glob) が AC の対象パスを包含しているか (隣接パスや類似名のみでは不可)
   - Step 3 の「Related job is **SUCCESS** → **PASS**」行を次の2行に分割する:
     - SUCCESS かつ Step 2a で同一性確認済み → PASS。detail に確認した signal と根拠を記録する (例: "Alternative verification via CI job `test-scripts` success (identity confirmed via run command containment: workflow step runs `bats tests/`, which includes `tests/setup-labels.bats`)")
     - SUCCESS だが同一性未確認 → UNCERTAIN。detail に "CI job `job-name` succeeded but its run scope could not be confirmed to cover the AC's verification target" 等を記録する
   - Step 3a 以降 (FAILURE 分岐、CI infra 判定、ローカル実行フォールバック) は変更しない — ローカル実行時は AC の `command` をそのまま再実行するため CI ジョブの同一性に依存せず、本 Issue のスコープ外。番号 "3a" は本ファイル内でのみ参照される (ファイル内 self-reference のみ、他ファイルからの参照なしを grep で確認済み) ため、Step 3 以降の番号変更は不要
2. `tests/verify-executor.bats` に新しい `@test` を追加する (after 1) (→ 受入条件4)
   - 既存の `VERIFY_EXECUTOR="$PROJECT_ROOT/modules/verify-executor.md"` 変数を再利用する
   - 「SUCCESS かつ同一性確認済み → PASS」の記述が存在することを確認する `@test`
   - 「SUCCESS だが同一性未確認 → UNCERTAIN」の記述 (negative case) が存在することを確認する `@test`
   - 3つの identity confirmation signal (run command containment / exact job name match / execution target path containment) が列挙されていることを確認する `@test`

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-executor.md の CI Reference Fallback 節に、参照した CI ジョブが AC の要求する検証対象を含むと確認できない場合は PASS ではなく UNCERTAIN とする指針が明記されている。SUCCESS を PASS に変換してよい条件が示されている" --> 同一性が確認できない場合に UNCERTAIN へ倒す指針が明記されている
- <!-- verify: rubric "同一性を確認するための具体的な手掛かり (ワークフロー定義内の実行コマンドとの突き合わせ、実行対象パスの包含関係など) が列挙されている" --> 同一性の確認手段が列挙されている
- <!-- verify: section_contains "modules/verify-executor.md" "CI Reference Fallback" "同一性" --> `verify-executor.md` の CI Reference Fallback 節に同一性確認に関する記述が追加されている
- <!-- verify: rubric "tests/ 配下に、CI Reference Fallback の判定を検証するテストが存在する。同一性が確認できるケースで PASS、確認できないケースで UNCERTAIN になること (negative case) の両方を含む" --> 両ケースを検証するテストが追加されている

### Post-merge

- `command` 型 AC を含む Issue の `/review` (safe mode) で、CI Reference Fallback の判定根拠が Details に記録されることを確認する <!-- verify-type: opportunistic -->

## Notes

- **「同一性」を English documentation に記載する判断について**: Pre-merge 受入条件3 は `section_contains "modules/verify-executor.md" "CI Reference Fallback" "同一性"` を要求している。`modules/verify-executor.md` はプロジェクト言語規約 (`CLAUDE.md`) 上 English documentation に分類されるが、`modules/verify-patterns.md` に "reference point (参照点)"・"実測データの存在" 等、英語モジュール文書内に概念ラベルとして日本語グロスを併記する既存の前例があることを grep で確認した。同様に「identity (同一性)」という形で Step 2a の初出時にバイリンガル表記する方針とした。受入条件の verify command 自体は独自に書き換えず、Issue 本文からそのまま転記している
- **スコープ外**: Step 3a (FAILURE → CI infra 判定 → ローカル実行) は AC の `command` をそのまま再実行するため CI ジョブの同一性に依存しない。`modules/ci-failure-classifier.md` への変更も不要と判断した
- **既存の前方参照**: `modules/verify-classifier.md:206` に本 Issue (#1126) を先行して引用する記述がある ("the same operational stance as the CI Reference Fallback (#1126), applied here as guidance rather than an automated check")。ポリシースタンスの引用に留まり、具体的な文言には依存しないため変更不要と判断した
- **doc-checker 影響評価**: `docs/workflow.md` に `verify-executor.md` への参照が存在しないことを grep で確認した (0 件)。モジュールの役割・名称自体は変更しないため、`README.md` / `docs/workflow.md` の更新は不要と判断した
- **Related**: #1055 / PR #1120 (本 Issue の起点となった review retrospective の観察)。#1083 (逆方向 — 常時 UNCERTAIN になる verify command の検出) とは PASS/UNCERTAIN の境界を挟んで対になる
