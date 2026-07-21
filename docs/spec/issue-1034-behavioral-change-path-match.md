# Issue #1034: code: 汎用ファイル名で Behavioral Change Detection が full-suite を誤発火する問題を修正

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: `/triage` 実行時の Issue Retrospective コメント。Title 正規化、Type=Bug・Size=S・Value=2 の割り当て、および Auto-Resolved Ambiguity Points (パス込みフルパス一致を第一候補として推奨) の記録を報告。本 Spec の設計判断は Issue 本文の Auto-Resolved Ambiguity Points をそのまま踏襲した。 / URL: https://github.com/saitoco/wholework/issues/1034#issuecomment-5034002286

## Overview

`skills/code/SKILL.md` Step 9 の Behavioral Change Detection サブセクション (check 2) は、変更された既存ファイルからベア名 (パスなし) を抽出し `grep -rl "<filename>" tests/` で追加参照テストの有無を判定している。`SKILL.md` のように複数 Skill で共有される汎用ファイル名では、この判定が無関係なテストファイルまで大量にヒットし、常に `bats tests/` フルスイート実行を強制する。check 2 の一致方式をベア名一致からリポジトリルート相対のフルパス一致に切り替え、汎用ファイル名でも適切なスコープを選択できるようにする。

## Reproduction Steps

1. `/code` で `skills/review/SKILL.md` のような既存ファイルを変更する (他 Skill と無関係な狭い変更)。
2. Behavioral Change Detection check 2 が変更ファイルからベア名 `SKILL.md` を抽出し `grep -rl "SKILL.md" tests/` を実行する。
3. 実測 (2026-07-21 時点、スコープ: `tests/` 配下の `.bats` + fixture 全ファイル): `grep -rl "SKILL.md" tests/` は 22 件ヒットする。直属テスト (`tests/review.bats`) + 正当な追加参照 (`tests/run-review.bats`) の 2 件を除く残り 20 件は無関係な Skill のテストファイルである。
4. 「追加テストファイルが参照している」と誤判定され、スコープを大きく超える `bats tests/` フルスイートが強制される。

## Root Cause

check 2 は変更ファイルのパスを破棄しベア名のみで `tests/` 配下を全文検索するため、`SKILL.md` のように複数ファイルで共有される汎用ファイル名に対しては、無関係なテストファイル中の偶発的な文字列一致 (コメントやドキュメント文中の言及等) まで「追加参照」として検出してしまう。この一致は実際のテストとファイルの振る舞い依存関係 (behavioral coupling) を反映していない。

## Changed Files

- `skills/code/SKILL.md`: Behavioral Change Detection check 2 の一致方式をベア名一致からフルパス一致に変更

## Implementation Steps

1. `skills/code/SKILL.md` の Behavioral Change Detection check 2 (Step 9 内、"Are there existing tests that reference the modified file(s) outside the directly-associated test?" の箇条書き) を以下の通り変更する (→ acceptance criteria A):
   - 変更前: "For each modified existing file, extract the filename (without path) and run (bash 3.2+ compatible): `grep -rl "<filename>" tests/`"
   - 変更後: 変更ファイルのファイル名 (パスなし) を抽出する代わりに、check 1 で既に得ているリポジトリルート相対のフルパス (`git diff --name-only HEAD` 等で取得したもの) をそのまま使用し、`grep -rl "<path>" tests/` を実行する旨に書き換える。あわせて、grep パターンとして使う前に `<path>` 中の正規表現メタ文字 (例: `.` → `\.`) をエスケープする旨を明記する。
   - 直属テストの例示 (`tests/run-code.bats` for `scripts/run-code.sh`) や `tests/` 不在時のエラーに関する既存の注記はそのまま維持する。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md の Behavioral Change Detection サブセクションが、SKILL.md のような複数ファイルで共有される汎用ファイル名に対して不要な full-suite 発火を避ける仕組み (例: パス込みマッチ、Skill 名を含めた検索パターン等) を持つ" --> Behavioral Change Detection の経験則が汎用ファイル名でも適切なスコープを選択する

### Post-merge

なし

## Notes

- 実装メカニズムは Issue 本文の Auto-Resolved Ambiguity Points (パス込みフルパス一致を第一候補として推奨) にそのまま従った。本 Spec 作成にあたり改めて実測検証したところ、`grep -rl "SKILL.md" tests/` = 22 件 (スコープ: `tests/` 配下の `.bats` + fixture 全ファイル) に対し、`grep -rl "skills/review/SKILL\.md" tests/` および `grep -rl "skills/verify/SKILL\.md" tests/` はいずれも 2 件に絞り込まれ、Issue 本文の実測値と一致することを確認した。
- 副次確認: 同種の効果は `SKILL.md` に限らない。例として `scripts/run-code.sh` はベア名一致で 11 件ヒットするが、フルパス一致 (`scripts/run-code\.sh`) では 2 件 (`tests/run-code.bats`, `tests/run-code-mergeability.bats`) に絞られる。差分の 9 件 (`tests/auto.bats` 等) を調査したところ、いずれも run-code.sh を丸ごとモック化して呼び出し元スクリプトの挙動を検証するテスト、または `--help` 文言・fixture 内の文字列一致であり、run-code.sh 自身の振る舞いへの依存 (behavioral coupling) を反映したものではないことを確認した。フルパス一致への切替はこれらの偽陽性を取り除きつつ、真の参照 (直属テスト) は保持する。
- `modules/verify-patterns.md` §24 (Behavioral Changes — Prefer Full Test Suite for Verify Commands) は `/issue` の verify command 生成向けの近縁ガイドラインだが、具体的な `grep` コマンド例を含まないため本 Issue のスコープ対象外と判断した (変更不要)。
- `skills/code/SKILL.md` を参照するテストファイル (`tests/code.bats`, `tests/run-code.bats`, `tests/run-code-mergeability.bats`, `tests/reconcile-phase-state.bats`, `tests/operate-route.bats`) を確認したが、Behavioral Change Detection の文言に対する文字列アサーションは存在しないため、テストファイルの変更は不要と判断した。
