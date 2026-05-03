# Issue #391: doc: Quick Start の見直し

## Overview

`/auto` 中心の Quick Start を `/issue` → `/code` → `/verify` の手動 3 ステップ中心に再構成する。サンプル Issue 本文を wholework 標準フォーマット (Pre-merge セクション + verify command 付与) で最初から提示し、各言語版 doc には各言語のサンプルを掲載。XS patch route の挙動 (spec phase スキップ + retrospective 用 spec ファイル自動生成) を一文追加し、実行時間表記を実態に合わせて更新する。`README.md` / `README.ja.md` の Quick Start 紹介行も新ワークフロー想定に揃える。

## Changed Files

- `docs/guide/quick-start.md`: change intro time and `/auto` mention; replace sample Issue body with wholework-standard format (English, Pre-merge section, verify commands); restructure Steps 3-5 to use `/issue` → `/code` → `/verify` manually; add one-line note on XS patch route behavior (spec skipped + retrospective spec file auto-generated); update Step 5 PR workflow framing to "Try `/auto` for a bigger Issue"
- `docs/ja/guide/quick-start.md`: same restructure as above with Japanese sample Issue body and Japanese prose
- `README.md`: update Quick Start mention line (currently "10–15 minutes" + "first `/auto` run") to reflect new manual 3-step workflow framing
- `README.ja.md`: update Quick Start mention line (currently "10〜15 分" + "最初の `/auto` 実行") to reflect new manual 3-step workflow framing

## Implementation Steps

1. Revise `docs/guide/quick-start.md` (→ acceptance criteria 1, 3, 4, 5):
   - Intro: change "Get from zero to your first autonomous `/auto` run in 10–15 minutes." to a sentence that reflects the new manual 3-step workflow with a shorter time estimate (e.g., "Walk through `/issue` → `/code` → `/verify` on a sample Issue in about 5 minutes.")
   - Step 2 sample Issue body: replace the current `## Background` / `## Goal` (English) block with the wholework-standard format below (English, Pre-merge section, `<!-- verify: ... -->` comments). Keep the title `Add a hello world script` unchanged so triage's title normalization still demonstrates a small adjustment but body normalization no longer triggers
   - Step 3 (formerly `/auto`): split into Steps 3 / 4 / 5 — `/issue 42` (observe triage result), `/code 42` (observe direct commit to main), `/verify 42` (observe Issue close + acceptance criteria check). For each step, add a one-liner explaining what the user should observe
   - Insert a one-liner immediately after Step 3 or in Step 5 explaining XS patch route behavior: `/spec` is skipped for XS Issues, and a retrospective spec file (`docs/spec/issue-N-*.md`) is auto-generated for verify retrospective use
   - Step 4 (results check) → renumber as Step 6
   - Step 5 (PR workflow) → renumber as Step 7 and reframe as "When you are ready, try `/auto` on a bigger Issue (Size M+) for the full PR-based workflow"
   - Sample Issue body for English version (verbatim copy/paste block in the doc):
     ```markdown
     ## Background

     We need a simple shell script to verify the project setup.

     ## Purpose

     Add `scripts/hello.sh` that prints "Hello, Wholework!" when run.

     ## Acceptance Criteria

     ### Pre-merge (auto-verified)

     - [ ] <!-- verify: file_exists "scripts/hello.sh" --> `scripts/hello.sh` exists
     - [ ] <!-- verify: command "bash scripts/hello.sh | grep -qF 'Hello, Wholework!'" --> Running `bash scripts/hello.sh` outputs `Hello, Wholework!`
     ```

2. Mirror the same restructure in `docs/ja/guide/quick-start.md` with the Japanese sample Issue body (→ acceptance criteria 2, 3, 4, 5):
   - Intro: 「10〜15 分でゼロから最初の `/auto` 自動実行までたどり着きます。」を新ワークフロー想定 (約 5 分、手動 3 ステップ) の文に置き換え
   - Step 2 サンプル本文を以下の日本語標準フォーマットに置き換え
   - Step 3〜5 を `/issue` / `/code` / `/verify` の手動 3 ステップに分割。各ステップに観察ポイントの一文を添える
   - XS patch route 挙動の一文を追加: `/spec` がスキップされる旨と、verify retrospective 用に `docs/spec/issue-N-*.md` が自動生成される旨
   - Step 4 → Step 6 にリナンバー、Step 5 → Step 7 にリナンバーして「より大きな Issue (Size M+) で `/auto` を試す」と再フレーム
   - 日本語版サンプル本文 (doc 内の verbatim コピペブロック):
     ```markdown
     ## Background

     プロジェクトのセットアップ確認用にシンプルなシェルスクリプトが必要。

     ## Purpose

     `scripts/hello.sh` を追加し、実行すると「Hello, Wholework!」と出力されるようにする。

     ## Acceptance Criteria

     ### Pre-merge (auto-verified)

     - [ ] <!-- verify: file_exists "scripts/hello.sh" --> `scripts/hello.sh` が存在する
     - [ ] <!-- verify: command "bash scripts/hello.sh | grep -qF 'Hello, Wholework!'" --> `bash scripts/hello.sh` を実行すると `Hello, Wholework!` が出力される
     ```

3. Update `README.md` Quick Start intro line (line 37) (→ acceptance criteria 4):
   - Current: `New to Wholework? The [Quick Start guide](docs/guide/quick-start.md) walks you through installation and your first `/auto` run in 10–15 minutes.`
   - New (example): `New to Wholework? The [Quick Start guide](docs/guide/quick-start.md) walks you through installation and your first manual `/issue` → `/code` → `/verify` cycle in about 5 minutes.`

4. Update `README.ja.md` Quick Start intro line (line 37) (→ acceptance criteria 4):
   - Current: `Wholework を初めて使いますか？ [クイックスタートガイド](docs/ja/guide/quick-start.md) が、インストールから最初の `/auto` 実行までを 10〜15 分で案内します。`
   - New (example): `Wholework を初めて使いますか？ [クイックスタートガイド](docs/ja/guide/quick-start.md) が、インストールから最初の手動 `/issue` → `/code` → `/verify` サイクルまでを約 5 分で案内します。`

## Verification

### Pre-merge

- <!-- verify: file_contains "docs/guide/quick-start.md" "/issue" --> `docs/guide/quick-start.md` のワークフロー説明に `/issue` が登場し、手動 3 ステップ構成になっている
- <!-- verify: file_contains "docs/ja/guide/quick-start.md" "/issue" --> `docs/ja/guide/quick-start.md` のワークフロー説明に `/issue` が登場し、手動 3 ステップ構成になっている
- <!-- verify: rubric "docs/guide/quick-start.md と docs/ja/guide/quick-start.md の Step 2 サンプル Issue 本文が wholework 標準フォーマット (`## Purpose` セクション + `### Pre-merge (auto-verified)` セクション + `<!-- verify: ... -->` コメント) で書かれており、英語版は英語、日本語版は日本語のサンプル本文になっている" --> サンプル Issue 本文が両言語版で標準フォーマット + 各言語に整合
- <!-- verify: rubric "docs/guide/quick-start.md, docs/ja/guide/quick-start.md, README.md, README.ja.md の 4 ファイルから旧時間見積もり (英語版: '10–15 minutes', 日本語版: '10〜15 分') が除去されており、新ワークフロー想定の数字 (例: '5 minutes' / '5 分') に置き換わっている" --> 4 ファイルから旧時間見積もりが除去され新数字に更新
- <!-- verify: rubric "docs/guide/quick-start.md と docs/ja/guide/quick-start.md に XS patch route の挙動 (`/spec` フェーズスキップ + verify retrospective 用 `docs/spec/issue-N-*.md` の自動生成) が一文以上説明されている" --> XS patch route 挙動の説明が両言語版に追加されている

### Post-merge

- 改訂後の Quick Start を空のテストリポジトリで実機検証し、`/issue` → `/code` → `/verify` の手動 3 ステップが各 1〜3 分程度で完了することを確認
- 改訂後のサンプル Issue 本文をコピペした際、`/issue` の triage 自動補正がほぼ走らない (フォーマット保持) ことを確認

## Notes

- Issue body の Pre-merge 受入条件 9 件は Spec 設計時に 5 件に統合した (両言語版を 1 件にまとめ rubric 化)。Issue body 側を Spec の 5 件に揃える (Step 10 の "Verification conditions vs. Issue body acceptance criteria consistency check" による自動同期)
- 各言語版 doc に各言語サンプルを掲載する方針は #391 issue retrospective で auto-resolve 済み (Quick Start docs は採用者向けで言語整合が UX 上自然、wholework 自体の Issue 言語ポリシーとはレイヤーが異なる)
- `docs/translation-workflow.md` は top-level `docs/*.md` を対象とするため `docs/guide/quick-start.md` には自動同期は適用されないが、本 Spec では英語版・日本語版の両方を同時に手動更新する
- 時間表記の「約 5 分」は手動 3 ステップ × 1〜3 分の合計目安。Post-merge の実機検証で乖離が判明した場合は数字を再調整 (フォローアップ Issue 起票)
- 旧 Step 5 の PR ワークフロー紹介は新 Step 7 に移動し、`/auto` をより大きな Issue で試す導線として再フレーム。`/auto` 自体は依然として推奨ワークフローだが、初回体験では明示的に避ける
