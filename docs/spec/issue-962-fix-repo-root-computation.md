# Issue #962: scripts: 自身の格納先リポジトリを誤操作する repo-root 算出パターンを複数スクリプトで修正

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (`/issue 962 --non-interactive` 実行結果: Auto-Resolve Log、AC を 1 件の rubric から 5 件の機械検証 + 1 件の rubric に再構成した経緯) — Issue 本文にはすでに全内容が反映済みで、Spec 設計に影響する新規アクションアイテムなし / https://github.com/saitoco/wholework/issues/962#issuecomment-4929064398

## Overview

tofas リポジトリで `/verify` 実行中 (2026-07-09)、`append-consumed-comments-section.sh` が呼び出し元プロジェクトではなく wholework 自身の `main` ブランチに誤ってコミット・push した事故の再発防止。原因は「スクリプト自身の格納パスから repo root を算出する」パターンが `_repo_root`/`_REPO_ROOT` 系の変数計算で複数スクリプトに存在すること。呼び出し元の実際の CWD から `git rev-parse --show-toplevel` で算出する既存の正しい実装パターンに統一する。対象は Issue 本文の Cross-scan Findings で確認された5ファイル: `append-consumed-comments-section.sh` / `spawn-recovery-subagent.sh` / `run-spec.sh` / `run-code.sh` / `apply-fallback.sh`。

**Issue #966 との関係 (Spec 作成時に判明した重要な先行事例)**: `scripts/run-auto-sub.sh` の同型パターン (8箇所) は Issue #966 で既に修正・マージ済み (`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` への統一、および `tests/run-auto-sub.bats` の `$MOCK_DIR/git` モック14箇所への `rev-parse --show-toplevel` ハンドラ追加、`bats tests/` フルスイート 1115 件 PASS 確認済み)。#966 の Root Cause 調査時点 (2026-07-09) では本 Issue は未修正だったため #966 側では参照できなかったが、現時点では確立済みの実装・テスト修正パターンとして参照できる。本 Spec はこのパターンに完全準拠する。#966 は `spawn-recovery-subagent.sh`/`apply-fallback.sh` を「`-C $_repo_root` 形式の git commit/push を自身で行わない」という理由でスコープ外としており、本 Issue (#962) 側のスコープと重複しないことも確認済み。

## Reproduction Steps

1. tofas の worktree (`/Users/saito/src/tofas/.claude/worktrees/verify+issue-12`) で `/verify` を実行中、Step 4 の comment-consumption フォールバックとして `append-consumed-comments-section.sh 12 verify` が CWD をそこに置いたまま実行される
2. スクリプトが `_repo_root="$(dirname "$SCRIPT_DIR")"` (スクリプト自身の格納場所の親、常に `/Users/saito/src/wholework`) を算出し、`docs/spec/issue-12-*.md` を wholework 側で探索する
3. たまたま番号が一致した wholework 自身の Issue #12 用 Spec (`docs/spec/issue-12-replace-bats-command-with-github-check.md`) がヒットし、末尾に `## Consumed Comments` を誤追記する
4. `git -C "$_repo_root" commit` → `git -C "$_repo_root" push origin HEAD` が実行され、wholework `main` に直接 push される (commit `d7d35001`、`git revert` で復旧済み: commit `e37b4e8b`)

追加で、`spawn-recovery-subagent.sh` 経由でも同型の誤書き込み実例が確認されている (2026-07-09、Issue #267/PR #289 という無関係な情報が `docs/reports/orchestration-recoveries.md` に混入。詳細は Issue コメント参照)。

## Root Cause

`SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` は「スクリプトファイルの物理的な格納場所」を指す。この `SCRIPT_DIR` の親ディレクトリ (`dirname "$SCRIPT_DIR"`、または同義の変種) を「呼び出し元プロジェクトの repo root」として使う実装が5ファイルに存在する。wholework がプラグインとして他プロジェクトから呼び出される構成では、`SCRIPT_DIR` は常に wholework プラグイン自身のインストール場所を指すため、この計算式は呼び出し元プロジェクトの実際の CWD/git root と一切連動しない。

既存の正しい実装パターン: `scripts/run-auto-sub.sh:13` の `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` (Issue #966 で導入・検証済み) — CWD 起点で呼び出し元プロジェクトの repo root を正しく算出する。`git rev-parse --show-toplevel` は worktree 内では worktree 自身のルートを返すことが実測確認済みのため (#966 Spec 記載)、`/auto` の並列実行時に worktree 内から呼び出された場合も意図通り動作する。今回の修正はこのパターンへの統一。

## Changed Files

- `scripts/append-consumed-comments-section.sh`: `_repo_root` (line 21) の算出式を `$(dirname "$SCRIPT_DIR")` → `$(git rev-parse --show-toplevel 2>/dev/null || pwd)` に変更 (変数名は維持)。bash 3.2+ 互換 (bash 4+ 構文なし)
- `scripts/spawn-recovery-subagent.sh`: `SCRIPT_DIR` 定義 (line 12) の直後にグローバル `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` を追加。`write_recovery_entry()` の `report_file` (line 208) を `$(dirname "$SCRIPT_DIR")/docs/reports/orchestration-recoveries.md` → `${REPO_ROOT}/docs/reports/orchestration-recoveries.md` に変更。bash 3.2+ 互換
- `scripts/run-spec.sh`: `SCRIPT_DIR` 定義 (line 43) の直後にグローバル `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` を追加。line 148 (`WHOLEWORK_CONFIG_PATH`)・150・191 (`_SPEC_FILE_PRE`/`_SPEC_FILE_POST`) の `$(dirname "$SCRIPT_DIR")` を `${REPO_ROOT}` に置換。line 166 の `--plugin-dir "$(dirname "$SCRIPT_DIR")"` は変更しない (`claude -p` にプラグイン自身のインストール場所を渡す正当な用途)。bash 3.2+ 互換
- `scripts/run-code.sh`: `_REPO_ROOT` (line 131) の算出式を `$(dirname "$SCRIPT_DIR")` → `$(git rev-parse --show-toplevel 2>/dev/null || pwd)` に変更 (変数名は維持)。line 240・242・367 の `$(dirname "$SCRIPT_DIR")` を既存の `$_REPO_ROOT` の再利用に置換 (新規変数は不要)。line 266・278 の `--plugin-dir "$(dirname "$SCRIPT_DIR")"` は変更しない。bash 3.2+ 互換
- `scripts/apply-fallback.sh`: `SCRIPT_DIR` 定義 (line 11) の直後にグローバル `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` を追加。`apply_code_patch_silent_no_op_retry()` 内の `_ww_yml` (line 99) を `$(dirname "$SCRIPT_DIR")/.wholework.yml` → `${REPO_ROOT}/.wholework.yml` に変更 (グローバル変数は関数内から参照可能)。bash 3.2+ 互換
- `tests/append-consumed-comments-section.bats`: `$MOCK_DIR/git` モック (setup() 内) に `rev-parse --show-toplevel` ハンドラを追加し、既存の `$REPO_ROOT` (`$BATS_TEST_TMPDIR/repo`) を echo するようにする — 既存3テストは全てこの解決に依存しているため必須。`cd` の追加は不要 (モックが CWD に関係なく直接パスを返すため)
- `tests/run-code.bats`: setup() 内のデフォルト `$MOCK_DIR/git` モック (line 104 付近) に `rev-parse --show-toplevel` ハンドラを追加し `$BATS_TEST_TMPDIR` を echo する。個別テストで上書きされる他の git モック (stale-branch/signoff/stash 系、計4箇所) は対象外で問題ない (詳細は Notes 参照)
- `tests/apply-fallback.bats`: デフォルト `$MOCK_DIR/git` モック (setup() 内、line 18 付近) に `rev-parse --show-toplevel` ハンドラを追加し `$BATS_TEST_TMPDIR` を echo する

## Implementation Steps

1. `scripts/append-consumed-comments-section.sh` の `_repo_root` を CWD ベースの `git rev-parse --show-toplevel` に修正し、`tests/append-consumed-comments-section.bats` の `$MOCK_DIR/git` モックに `rev-parse --show-toplevel` ハンドラ (`$REPO_ROOT` を echo) を追加する (→ AC1)
2. `scripts/spawn-recovery-subagent.sh` にグローバル `REPO_ROOT` を追加し、`write_recovery_entry()` の `report_file` をそれで算出するよう修正する。テスト側の必須変更はない (検証済み: 既存テストはこのパスに未到達か、到達しても空文字列 `REPO_ROOT` が既存の「ファイル未検出→skip」分岐に無害に帰着する — 同機能は現状も未テストのまま)。任意の追加改善として、2箇所の recover アクション用テスト固有モック (`@test` 内で `$MOCK_DIR/git` を上書きする箇所) にも同ハンドラを足並みを揃えて追加してよい (→ AC2)
3. `scripts/run-spec.sh` にグローバル `REPO_ROOT` を追加し、`_SPEC_DIR`/`_SPEC_FILE_PRE`/`_SPEC_FILE_POST` の算出をそれに置き換える (`--plugin-dir` 用途の line 166 は変更しない)。テスト変更は不要 (検証済み: `tests/run-spec.bats` は git をモックしておらず、setup() で既に `cd "$BATS_TEST_TMPDIR"` 済みのため、修正後の `git rev-parse --show-toplevel` は実 git 経由で正しく失敗し `|| pwd` で意図通り解決される) (→ AC3)
4. `scripts/run-code.sh` の `_REPO_ROOT` を CWD ベースの算出に修正し、`_SPEC_DIR`/`_SPEC_FILE_PRE`/`_SPEC_FILE_POST` (line 240・242・367) をこの変数の再利用に統一する (`--plugin-dir` 用途の line 266・278 は変更しない)。`tests/run-code.bats` のデフォルト `$MOCK_DIR/git` モックに `rev-parse --show-toplevel` ハンドラを追加する (→ AC4)
5. `scripts/apply-fallback.sh` にグローバル `REPO_ROOT` を追加し `_ww_yml` をそれで算出するよう修正する。`tests/apply-fallback.bats` のデフォルト git モックに同様のハンドラを追加する。最後に `scripts/*.sh` 全体を横断確認し、上記5ファイル以外に同種パターンが残っていないか確認する — 除外済み判断 (`--plugin-dir` 用途、および `test-skills.sh`/`validate-permissions.sh` のプラグイン自身のディレクトリ参照) と、対応を見送った残存箇所 (`check-file-overlap.sh`) は Notes に記載済み (→ AC5, AC6)

## Verification

### Pre-merge
- <!-- verify: grep "git rev-parse --show-toplevel" "scripts/append-consumed-comments-section.sh" --> `append-consumed-comments-section.sh` の `_repo_root` が CWD ベースの `git rev-parse --show-toplevel` で算出されるよう修正されている
- <!-- verify: grep "git rev-parse --show-toplevel" "scripts/spawn-recovery-subagent.sh" --> `spawn-recovery-subagent.sh` の `write_recovery_entry()` における `orchestration-recoveries.md` の書き込み先パスが CWD ベースの repo root で算出されるよう修正されている (2026-07-09 の誤書き込み実例に対する直接対応)
- <!-- verify: grep "git rev-parse --show-toplevel" "scripts/run-spec.sh" --> `run-spec.sh` の `_SPEC_DIR`/Consumed Comments 件数比較用ファイル探索パスが CWD ベースの repo root で算出されるよう修正されている (`--plugin-dir` 用途の既存 `dirname "$SCRIPT_DIR")"` は変更しない)
- <!-- verify: grep "git rev-parse --show-toplevel" "scripts/run-code.sh" --> `run-code.sh` の `_REPO_ROOT`/Consumed Comments 件数比較用ファイル探索パスが CWD ベースの repo root で算出されるよう修正されている
- <!-- verify: grep "git rev-parse --show-toplevel" "scripts/apply-fallback.sh" --> `apply-fallback.sh` の `_ww_yml` 読み込みパスが CWD ベースの repo root で算出されるよう修正されている
- <!-- verify: rubric "scripts/ 配下について、上記 5 ファイル (append-consumed-comments-section.sh / spawn-recovery-subagent.sh / run-spec.sh / run-code.sh / apply-fallback.sh) 以外に同種の『スクリプト自身の格納パスからリポジトリルートを誤って算出する』パターンが残っていないか横断的に再確認され、あれば併せて修正されている" --> 上記5ファイル以外の残存箇所についての横断確認が行われている

### Post-merge
- 別プロジェクト (tofas 等) の worktree 内から `/verify` および `/spec`/`/code` (comment-consumption フォールバックが発火するケース) を実行し、Consumed Comments セクション・orchestration-recoveries.md への追記・auto-retry-on-fail 設定判定のいずれもが呼び出し元プロジェクトの正しいリポジトリ/設定に対して行われることを実地確認する <!-- verify-type: manual -->

## Notes

### 横断確認で除外したファイル (正当な用途、対象外と判断)
- `scripts/run-review.sh` / `run-issue.sh` / `run-merge.sh` / `run-spec.sh:166` の `--plugin-dir "$(dirname "$SCRIPT_DIR")"`: Issue 本文で明示的に除外済み (`claude -p` にプラグイン自身のインストール場所を渡す用途)
- `scripts/test-skills.sh:10`・`scripts/validate-permissions.sh:13` の `PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`: 今回の横断確認 (`dirname "\$SCRIPT_DIR"` の文字列一致だけでなく `cd "\$SCRIPT_DIR/.." && pwd` 等の同義変種、および `_?[Rr][Ee][Pp][Oo]_?[Rr][Oo][Oo][Tt]` 系変数代入も対象にした広めの grep) で新たに発見。ただしこれらは wholework プラグイン自身の `skills/` ディレクトリを検証・テストする用途 (呼び出し元プロジェクトの repo ではない) であり、`--plugin-dir` と同じ「プラグイン自身の場所を求める」正当な計算のため対象外と判断した (Auto-Resolve, non-interactive mode judgment)

### 横断確認で発見し、今回は対応を見送った残存箇所 (Auto-Resolve, non-interactive mode judgment)
- `scripts/check-file-overlap.sh:36`: `REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"` が呼び出し元プロジェクトの `docs/spec/` (XL Issue のサブ Issue 間ファイル重複検出用) を探すのに使われており、対象5ファイルと同種の anti-pattern に該当する。以下の理由で本 Issue のスコープには含めず、follow-up Issue での対応を推奨する:
  1. **現状 dead code**: `skills/`・`modules/`・`scripts/run-auto-sub.sh` のいずれからも呼び出されておらず (grep で確認済み)、現時点で実害のリスクはゼロ。対象5ファイルは `/spec`・`/code`・`/verify`・`/auto` の Tier 2/3 リカバリ経路に実際に組み込まれており、うち2件 (`append-consumed-comments-section.sh`・`spawn-recovery-subagent.sh`) は既に実インシデントを起こしている — リスクの性質が異なる
  2. **既存テストとの設計上の緊張関係**: `tests/check-file-overlap.bats` はこの `REPO_ROOT` が `WHOLEWORK_SCRIPT_DIR` 経由でモック可能であること (Issue #188 で意図的に導入) に依存した分離設計になっている。`git rev-parse --show-toplevel` へ変更すると、モック用ディレクトリは git repo ではないため CWD 起点の解決に切り替わり、既存11テストケースのフィクスチャ配置設計を作り直す必要がある — 単純な計算式の置換だけでは済まない
  3. follow-up Issue では (i) `REPO_ROOT` を `git rev-parse --show-toplevel` に統一し、(ii) `tests/check-file-overlap.bats` の分離戦略を CWD ベースに作り直す (本 Issue の `tests/append-consumed-comments-section.bats` 等と同様、モックの `rev-parse --show-toplevel` ハンドラで対応する方式を推奨) の両方をセットで扱うことを推奨する

### テストモック修正の設計根拠 (Issue #966 の確立済みパターンに準拠)
`tests/append-consumed-comments-section.bats`・`tests/run-code.bats`・`tests/apply-fallback.bats` はいずれも `$MOCK_DIR/git` を PATH 経由でモックしており、既存モックは `rev-parse --show-toplevel` を明示的に扱っていない (該当しない呼び出しに対して「exit 0・出力なし」にフォールスルーする)。このため修正後の `$(git rev-parse --show-toplevel 2>/dev/null || pwd)` は「コマンド成功・出力は空文字列」という結果になり、`||` によるフォールバックが発火せず `REPO_ROOT` が空文字列になってしまう。

Issue #966 (`scripts/run-auto-sub.sh` の同型修正、マージ済み) では `tests/run-auto-sub.bats` の14箇所の `$MOCK_DIR/git` モックすべてに次の形のハンドラを追加して解決している:
```bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
```
本 Issue も同じ形のハンドラを採用する (echo 対象パスはテストごとの既存フィクスチャ配置に合わせる: `append-consumed-comments-section.bats` は `$REPO_ROOT`、他2ファイルは `$BATS_TEST_TMPDIR`)。モックが CWD に関係なく直接パスを返すため、`cd` の追加は不要。

`tests/run-spec.bats`・`tests/spawn-recovery-subagent.bats` は対象外 (詳細は Changed Files 参照: 前者は git を一切モックしていないため実 git が正しく機能し、後者は該当テストの結果に影響しない箇所のみ空文字列 `REPO_ROOT` を生むため無害)。

### ドキュメント整合性
`docs/structure.md`・`docs/tech.md`・`docs/product.md` (日本語版含む) で対象5スクリプトの役割が言及されているが、いずれも高レベルな役割説明のみで repo-root 算出方式には触れていないため、更新不要と判断した。

### Size 再評価の見込み
本 Issue は triage 時点で Size=S (patch route) だが、実際の Changed Files は本番スクリプト5件 + テスト3件の計8件となり、`modules/size-workflow-table.md` の Axis 1 (6-10件 → L) に該当する。Axis 2 の「root cause の明確なバグ修正 (-1 step)」を適用しても M 相当となる可能性が高い。Step 18 (Size-to-Workflow Determination) で正式に再評価し、必要であれば pr route (M) に昇格する。参考: Issue #966 (対象1ファイル + テスト1ファイルの計2件、同種の修正) は Size=S/patch route のまま完了しているが、本 Issue は対象ファイル数が5倍のため異なる判断になる可能性がある。

## Code Retrospective

### Deviations from Design
- Spec の Size 再評価見込み (Notes 末尾) を待たず、`--pr --non-interactive` フラグが明示指定されていたため pr route (branch+PR) で実行した。明示フラグは Size 自動判定より優先される既定の挙動であり、逸脱ではなく設計通りの優先順位適用。

### Design Gaps/Ambiguities
- Spec の Changed Files は `tests/append-consumed-comments-section.bats`・`tests/run-code.bats`・`tests/apply-fallback.bats` の3ファイルのみを変更対象として列挙していたが、実装後の `bats tests/` フルスイート実行で `tests/run-verify.bats` (同じく `append-consumed-comments-section.sh` を対象とする別系統のテストスイート) が4件 FAIL した。原因は同ファイルの `setup()` デフォルト `$MOCK_DIR/git` モックと2箇所の個別テスト内モックがいずれも `rev-parse --show-toplevel` 未対応で、`_repo_root` が空文字列に解決されたため。Spec の「横断確認」は `scripts/*.sh` 側のみを対象としており、`tests/` 側で同一スクリプトを参照する別スイートの網羅までは対象にしていなかった。同様の齟齬を避けるため、今後 repo-root 算出パターンを変更する Issue では `git grep -l "<変更対象スクリプト名>" tests/` で影響テストファイルを事前に洗い出すことを推奨する。
- Spec は `tests/run-code.bats` の git モック上書き4箇所 (stale-branch/signoff×2/stash) を「対象外で問題ない」と分類していたが、実際には stash テスト (`auto-retry: preflight stashes parent-main stray untracked file before retry re-invocation`) のみ `_REPO_ROOT` (→ `.wholework.yml` の `auto-retry-on-fail` 判定) に依存しており、ハンドラ追加が必要だった。他の3箇所 (stale-branch/signoff×2) は該当コードパスが `_REPO_ROOT` を経由しないため無害という判定は正しかった。「4箇所とも対象外」という一括判定ではなく、各上書きモックが `_REPO_ROOT`/`_WW_YML` 依存パスに到達するかを個別に確認する必要があった。

### Rework
- なし (実装は Spec Implementation Steps 1-5 の順に一度で完了。上記2件のテストギャップはフルスイート実行時に発見・その場で追加修正し、そのまま最終コミットに含めた)

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Size=S だが `--pr --non-interactive` の明示フラグに従い pr route (branch+PR) で実行した (Size 自動判定より明示フラグを優先する既定ルール通り)。
- 対象5ファイルすべてで `git rev-parse --show-toplevel 2>/dev/null || pwd` パターンに統一し、`#966` (`run-auto-sub.sh`) で確立済みのパターンを踏襲した。
- `bats tests/` フルスイートで behavioral change を検出したため (`grep -rl` で対象スクリプト名が Spec 未記載のテストファイルにもヒット)、narrow scope ではなくフルスイートを実行し、Spec 未記載だった `tests/run-verify.bats` のテストギャップを実装段階で発見・修正した。

### Deferred Items
- `scripts/check-file-overlap.sh:36` の同型パターンは Spec Notes の通り本 Issue のスコープ外とし、follow-up Issue での対応を推奨する (dead code かつ既存テストとの分離設計に緊張関係があるため単純な置換では済まない)。
- Post-merge AC (別プロジェクト実地確認) は manual verify-type のため `/verify` フェーズでの人手確認待ち。

### Notes for Next Phase
- `/review` では Spec Notes の「Size 再評価の見込み」記述 (実際の Changed Files 8件は Axis 1 で L 相当) を踏まえつつ、明示 `--pr` 指定により pr route が既に適用済みである点を前提に進めてよい。
- Code Retrospective の Design Gaps 2件 (テストスイート網羅漏れ、git モック上書き箇所の個別依存判定) は、今後同種の repo-root 修正 Issue のレビュー観点として活用できる。
