# Issue #1412: code: bats の裸 [[ ]] アサーションの bash 3.2 検出漏れ対策ガイダンスを追加

## Overview

`#1410` の実装調査で判明した pitfall への対策。bats の `@test` 本体内で裸の `[[ ... ]]` を単独文として書いた場合、macOS のシステム bash (3.2.57(1)-release) では `set -e` がその失敗を正しく伝播せず、本来 FAIL すべきアサーションが "ok" (PASS) として報告される。bash 4.x 以降では発生しない、bash 3.2 特有の制限。

対応は Issue Proposal の 2 段階のうち、可視化のみを対象とする第1段階:
1. 今後の新規テストへの周知 — `skills/code/skill-dev-validation.md` に pitfall と安全なパターンを追記
2. 既存 (`tests/*.bats` 125 ファイル中 79 ファイル、約 1000 箇所) の可視化 — 新規チェックスクリプトを作成し、CI と `/code` Additional validation の両方から呼び出す

既存 1000 件の一括修正は Out of Scope (Issue 本文に明記)。

## Reproduction Steps

1. bats の `@test` 本体内に `[[ "$output" == *"x"* ]]` のような裸の `[[ ]]` を単独文として書く（`||` や `&&` で連結しない）
2. 条件が偽になる入力を与えて macOS システム bash (`/bin/bash`, 3.2.57(1)-release) 上で bats (1.13.0) を実行する
3. 期待: FAIL。実際: "ok" (PASS) として報告される
4. 同じ条件を `[ "a" = "b" ]` (単一角括弧) または `[[ ... ]] || false` の形にすると、期待通り FAIL する

## Root Cause

bash 3.2 系の `set -e` (errexit) は、`[[ ... ]]` という compound command が単独文として書かれた場合にその失敗を正しく伝播しない既知の制限を持つ（bash 4.x 以降では発生しない）。bats はテスト本体を `set -e` 相当の仕組みで実行するため、この制限下では条件が偽でもテスト関数が正常終了し "ok" と報告される。`[ ]` (POSIX `test`) や `[[ ... ]] || false` の形であれば、この制限の影響を受けずに正しく失敗が伝播する。

## Changed Files

- `scripts/check-bare-bracket-assertions.sh`: new file — `tests/*.bats` 全体をスキャンし、`|| false` を伴わない裸の `[[ "$output"` / `[[ "$status"` 形の assertion を検出し警告として一覧出力する（可視化のみ・常に exit 0）。bash 3.2 互換
- `tests/check-bare-bracket-assertions.bats`: new file — 上記スクリプトの新規テストケース（クリーン検出・検出・自己参照除外）
- `skills/code/skill-dev-validation.md`: add — bash 3.2 での裸 `[[ ]]` 単独文の `set -e` 非伝播について、安全なパターンの具体例とともに新セクションを追記
- `skills/code/bare-bracket-assertions-check.md`: new file — `/code` Additional validation 用ドメインファイル（`load_when: file_exists_any: [scripts/check-bare-bracket-assertions.sh]`）。`skills/code/forbidden-expressions-check.md` と同型
- `skills/code/SKILL.md`: change — Step 9 Additional validation に、上記ドメインファイルを条件付きで読み込む行を追加（`scripts/check-forbidden-expressions.sh` の既存行の直後）
- `.github/workflows/test.yml`: change — 新規 CI ジョブ `bare-bracket-assertions` を追加。同ジョブ内に bash バージョン + `[[ ]]` 再現診断ステップを含める（Post-merge AC の調査用）
- `docs/structure.md`: change — Directory Layout の `scripts/` ファイル数コメントを `(90 files)` → `(91 files)`、`tests/` を `(126 files)` → `(127 files)` に更新。Tooling の script 一覧に `scripts/check-bare-bracket-assertions.sh` の一行説明を追加（`check-forbidden-expressions.sh` の既存エントリに倣う）

## Implementation Steps

1. `scripts/check-bare-bracket-assertions.sh` と `tests/check-bare-bracket-assertions.bats` を追加する。スクリプトは `tests/*.bats` を対象に `grep -nE '^[[:space:]]*\[\[ "\$(output|status)"'` で裸のアサーションを検出し、`|| false` を含む行と自ファイル (`tests/check-bare-bracket-assertions.bats`) を除外したうえで警告として一覧出力する。検出件数に関わらず常に `exit 0`（可視化のみ、CI をブロックしない設計 — Issue の Out of Scope に合致）。bash 3.2 互換（裸の `[[ ]]` を使わず `[ -n ... ]` 等で実装する）。bats テストはクリーンケース（`|| false` 付き・単一角括弧）、検出ケース（`$output`/`$status` 双方）、自己参照除外ケースをカバーする新規 `@test` を追加する (→ acceptance criteria 3)
2. `skills/code/skill-dev-validation.md` に新セクション「Bash 3.2: Bare `[[ ]]` Assertions Do Not Propagate `set -e`」を追加する。bash 3.2 での非伝播の説明、Principle、Unsafe/Safe (単一角括弧・`grep -q`・`|| false`) の具体例コードブロック、検出スクリプトへの参照を含める (→ acceptance criteria 1, 2)
3. `skills/code/bare-bracket-assertions-check.md` を新規作成する（`skills/code/forbidden-expressions-check.md` と同型: frontmatter `load_when: file_exists_any: [scripts/check-bare-bracket-assertions.sh]`、Processing Steps に `bash scripts/check-bare-bracket-assertions.sh` のローカル実行手順）。`skills/code/SKILL.md` の Step 9 Additional validation に、`scripts/check-forbidden-expressions.sh` の既存行の直後、`scripts/check-bare-bracket-assertions.sh` が存在する場合に同ドメインファイルの Processing Steps を読み込む行を追加する (→ acceptance criteria 3, Auto-Resolved 統合先方針)
4. `.github/workflows/test.yml` に新規ジョブ `bare-bracket-assertions` (`check-forbidden-expressions` ジョブと同型) を追加する。同ジョブ内に、`bash --version` を出力したうえで `bash -c 'set -e; [[ "1" == "2" ]]; echo UNREACHABLE'` をサブプロセスとして実行し、その終了コードから「このランナー上で bare `[[ ]]` の失敗が `set -e` を伝播したか」を `REPRO-CHECK:` 行としてログに出す診断ステップを追加する。続けて `bash scripts/check-bare-bracket-assertions.sh` を実行するステップを追加する (→ acceptance criteria 3 統合, Post-merge acceptance criteria)
5. `docs/structure.md` の Directory Layout ツリーで `scripts/` のファイル数コメントを `(90 files)` → `(91 files)`、`tests/` のファイル数コメントを `(126 files)` → `(127 files)` に更新する。Key Files > Scripts > Tooling の一覧に `scripts/check-forbidden-expressions.sh` エントリの直後、`scripts/check-bare-bracket-assertions.sh` — detect bare `[[ "$output"/"$status"` bats assertions without `|| false` (informational; does not fail the build) の一行説明を追加する (→ Steering Docs 整合性, Key Files maintenance rule)

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/code/skill-dev-validation.md" "bash 3.2" --> `skill-dev-validation.md` に bash 3.2 での `[[ ]]` 単独文の `set -e` 非伝播について明記されている
- <!-- verify: rubric "skill-dev-validation.md が裸の [[ ]] アサーションの危険性と、[ ] または || false を使う安全なパターンを具体例とともに説明している" --> 安全なパターンの記述がある
- <!-- verify: rubric "既存テストの裸の [[ \"$output\" アサーションを検出する仕組み (チェックスクリプトまたは既存スクリプトへの追加) が実装されている" --> 既存 assertion を可視化する仕組みがある

### Post-merge

- CI (GitHub Actions) ランナーの bash バージョンでこの問題が再現するかどうかの調査結果が Issue コメントとして記録されている <!-- verify-type: manual -->

## Notes

### Auto-Resolved Ambiguity Points からの引き継ぎ

Issue 本文の `## Auto-Resolved Ambiguity Points (Non-Interactive Mode)` セクションで既に以下が決定済み。本 Spec はこれに従う:
- 検出の実装方式: `scripts/validate-skill-syntax.py` への機能追加ではなく、`scripts/check-forbidden-expressions.sh` に倣った新規専用スクリプトとする
- 統合先: CI (`test.yml` 新規ジョブ) と `/code` Additional validation (ドメインファイル経由) の両方

### allowed-tools 明示エントリについて

`skills/code/SKILL.md` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-bare-bracket-assertions.sh:*` の明示エントリは追加しない。前例の `scripts/check-forbidden-expressions.sh` も同様に明示エントリを持たず (`bash scripts/check-forbidden-expressions.sh` 形の呼び出しは既存の `allowed-tools` パターンではカバーされていないが、本番で問題なく機能している既存状態)、本 Issue のスコープでこの構造を変更する理由はないため、前例と同じ扱いとする。

### 新規分岐ロジックのテストケース要件について

`scripts/check-bare-bracket-assertions.sh` 自体の検出ロジック（クリーン/検出/自己参照除外の分岐）は `tests/check-bare-bracket-assertions.bats` の新規 `@test` で直接カバーする。一方、`skills/code/SKILL.md` に追加する条件分岐行（"If `scripts/check-bare-bracket-assertions.sh` exists, Read ...") は LLM が実行時に解釈する prose 分岐であり、`check-forbidden-expressions.sh` 統合時の既存行と同様、bats で単体テスト可能な対象ではない。CI ワークフロー YAML への診断ステップ追加も同様の理由で bats 対象外。

### 外部ドキュメント調査について

Issue 本文に bash 3.2.57(1)-release と bats 1.13.0 での実機再現が既に記録されており、これは bash 公式ドキュメントよりも直接的な一次情報であるため、追加の WebFetch/WebSearch 調査は行わなかった。

### 検出スクリプトが常に exit 0 である理由

Issue の Purpose・Out of Scope は「既存 1000 件の可視化のみ」を明示しており、一括修正や新規追加分の強制 (ratchet) は本 Issue の対象外。既存違反がある状態で CI を fail させると全 PR がブロックされるため、`scripts/check-bare-bracket-assertions.sh` は検出件数に関わらず常に `exit 0` とし、警告出力のみを行う設計とした。
