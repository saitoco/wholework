# Issue #1452: check-language-convention: diff-context に依存したフェンス検出漏れを解消

## Overview

`scripts/check-language-convention.py` は unified diff (stdin) を読み取り、フェンスコードブロック (```) の開閉をトラッキングして、フェンス内の CJK 文字を誤検知 (false positive) しないようにしている。しかし、このトラッキングは diff に含まれる行 (追加行 + コンテキスト行) のみを対象としており、呼び出し元 `.github/workflows/test.yml` の2箇所の `git diff` 呼び出しはいずれもデフォルトコンテキスト (`-U3`) のままだった。フェンスの開始マーカーが変更行から3行より前にある場合、その diff hunk には開始マーカー行自体が含まれず、スクリプトはフェンスが開いていることを認識できない。結果としてフェンス内の既存の日本語テンプレート行が、同じ行の無関係な箇所を編集しただけで CJK 違反として誤検知され CI が failure になる、という再現性のあるバグが Issue #1449 (PR #1450) で実際に発生した。

本 Issue は `.github/workflows/test.yml` の2箇所の `git diff` 呼び出しに十分大きい `-U`/`--unified` コンテキストを指定し、フェンスの開閉状態を対象ファイル全体にわたって正しく追跡できるようにする (Auto-Resolved: コンテキスト拡大アプローチ採用、詳細は Issue 本文の `## Auto-Resolved Ambiguity Points` 参照)。

## Reproduction Steps

1. スクラッチ git リポジトリに、1行目を fence 開始マーカー (```) とする27行のファイル (`f.md`) を作成しコミットする。
2. fence 開始マーカーから14行離れた行 (行15) に、既存の日本語テンプレート文言を含む行を追加しコミットする (fence 内の正当な CJK 使用を模擬)。
3. その行の無関係な箇所を編集する (Issue #1449 の実際のインシデントと同型: 同じ行の一部を変更しただけ) コミットを作成する。
4. デフォルトコンテキストで diff を生成し、スクリプトに通す:
   ```
   git diff "HEAD^..HEAD" -- f.md | python3 scripts/check-language-convention.py
   ```
   実行結果: `f.md:既存の日本語テンプレート行です (unrelated edit)` を出力して **exit 1** (誤検知でバグを再現)。
5. `-U100000` を指定して同じ diff を生成しスクリプトに通す:
   ```
   git diff -U100000 "HEAD^..HEAD" -- f.md | python3 scripts/check-language-convention.py
   ```
   実行結果: 出力なしで **exit 0** (修正後の期待動作を確認)。

上記は本 Spec 作成時に実機検証済み (`/tmp` の使い捨てスクラッチリポジトリ、本リポジトリの `scripts/check-language-convention.py` を直接使用)。

## Root Cause

`scripts/check-language-convention.py` の `find_violations()` は、diff テキストに `+++ `/`-`/`+`/` ` (space) プレフィックスの行として実際に現れた行のみを走査し、` ``` ` にマッチする行でフェンス開閉カウンタ (`fence_count`) を更新する (`scripts/check-language-convention.py:61,91-93`)。diff に含まれない行 (デフォルト `-U3` のコンテキスト範囲外) は、スクリプトからは一切観測できない。呼び出し元 `.github/workflows/test.yml` の2箇所の `git diff` (行114, 116) はいずれも `-U` 未指定 (デフォルト3行) のため、変更行から3行を超えて離れたフェンス開始マーカーは diff hunk に現れず、スクリプトはフェンスが「閉じている」ものとして CJK 検査を実行してしまう。

`git diff` の `-U`/`--unified` に、対象ファイルの最大行数を超える値を指定すると、複数の hunk が1つに統合され、ファイル全体がコンテキストとして diff に含まれる (Reproduction Steps で実機検証済み。公式ドキュメント `git-scm.com/docs/git-diff` はこの境界時の挙動を明記していないため、動作を直接検証した)。これにより、フェンス開始マーカーが常に diff に含まれるようになり、本バグは解消する。

## Changed Files

- `.github/workflows/test.yml`: `language-convention` ジョブの2箇所の `git diff` 呼び出しに `-U100000` を追加
- `tests/check-language-convention.bats`: フェンス開始マーカーが diff コンテキスト範囲外にあるため hunk に現れないケースを再現する回帰テストを追加

## Implementation Steps

1. (→ acceptance criteria A, B) `.github/workflows/test.yml` の `language-convention` ジョブ内、2箇所の `git diff` 呼び出しに `-U100000` を追加する (`git diff` の直後、対象 ref 引数の前に挿入):
   - PR diff (行114): `git diff "origin/${{ github.base_ref }}...HEAD" -- skills/ modules/ scripts/` → `git diff -U100000 "origin/${{ github.base_ref }}...HEAD" -- skills/ modules/ scripts/`
   - push diff (行116): `git diff "HEAD^..HEAD" -- skills/ modules/ scripts/` → `git diff -U100000 "HEAD^..HEAD" -- skills/ modules/ scripts/`

2. (→ acceptance criteria C, D) `tests/check-language-convention.bats` の末尾に、以下の回帰テストケースを追加する (既存10ケースはそのまま維持):
   ```bats
   @test "false positive: fence opener beyond diff context is not visible in the hunk exits 1" {
     run bash -c "printf '+++ b/skills/verify/SKILL.md\n@@ -50,3 +50,3 @@\n Print advisory:\n-old english line\n+新しい日本語の行 (再試行)\n \`\`\`\n' | python3 '\$SCRIPT'"
     [ "\$status" -eq 1 ]
     [[ "\$output" == *"skills/verify/SKILL.md:"* ]]
   }
   ```
   このテストは、フェンスの閉じマーカーのみが hunk に含まれ開始マーカーが含まれない (= 本 Issue の実際のバグ形状) 場合、スクリプトが誤検知 (exit 1) することを固定化する回帰テストである。スクリプト自体は本 Issue で変更しない (`## Notes` 参照) ため、このテストは「exit 0 になるべき」ではなく「現状の exit 1 が期待挙動として保存される」ことを検証する — 実際の修正は呼び出し元 (Step 1) 側のコンテキスト拡大であり、スクリプトに渡す diff がそもそも開始マーカーを含むように変わることで問題を回避する。

## Verification

### Pre-merge

- <!-- verify: rubric "`.github/workflows/test.yml` の2箇所の `check-language-convention.py` 呼び出しに渡される `git diff` コマンドが、変更行から3行を超えて離れたフェンスコードブロックの開始マーカーも正しく追跡できるだけの十分なコンテキスト行数 (`-U`/`--unified`) を指定するよう修正されている" --> `.github/workflows/test.yml` の diff 生成コマンドに、変更行からの距離に依存しないフェンス検出を可能にする十分なコンテキスト行数が指定されている
- <!-- verify: grep "-U[0-9]|--unified=[0-9]" ".github/workflows/test.yml" --> (補助チェック) `.github/workflows/test.yml` に `-U`/`--unified` コンテキスト指定が含まれている
- <!-- verify: grep "fence opener beyond diff context" "tests/check-language-convention.bats" --> `tests/check-language-convention.bats` に、フェンス開始マーカーがデフォルトの diff コンテキスト範囲外にあるため diff に含まれないケース (開始マーカー行自体が hunk に現れないケース) を再現する回帰テストが追加されている
- <!-- verify: command "bats tests/check-language-convention.bats" --> `tests/check-language-convention.bats` の全テスト (新規回帰テストを含む) が pass する

### Post-merge

なし

## Notes

- **`-U100000` という値の根拠**: `wc -l skills/**/*.md modules/*.md scripts/*.sh scripts/*.py` (スコープ: `skills/`/`modules/`/`scripts/` 配下の `.md`/`.sh`/`.py` ファイル) で実測した現状の最大ファイルは `skills/auto/SKILL.md` の1449行。将来の増加分を見込んでも十分な余裕を持つ丸めた値として `-U100000` を採用した。この値はファイルの実行数を超えているため、git は複数 hunk を1つに統合しファイル全体をコンテキストとして出力する (Reproduction Steps で実機検証済み)。
- **コンテキスト拡大は新規の誤検知を発生させない**: `check-language-convention.py` は `is_added` (追加行) のみを CJK 検査対象とし、コンテキスト行 (space プレフィックス) はフェンスカウンタ更新にのみ使われ CJK 検査からは常に除外される (`scripts/check-language-convention.py:95-96`)。`-U` を拡大しても diff に含まれる「追加行の集合」自体は変化しない (変化するのはコンテキスト行の量のみ) ため、本修正が新たな誤検知を生むことはない。
- **fail-safe critical 判定**: `.github/workflows/test.yml` の `language-convention` ジョブは CI gate ではあるが、`fail_open()`/`|| true`/`2>/dev/null` のような safe-side デフォルトパターンは対象ファイルに存在しないことを `grep -nF` で確認済み (`modules/costly-step-protocol.md` 系の fail-safe critical 判定基準には該当しない、通常のフラグ追加として扱う)。
- **Pre-merge AC3 の verify command 具体化 (Triage AC audit 対応)**: Consumed Comments (下記) の通り、Triage AC audit コメントが元の AC3 (`command "bats tests/check-language-convention.bats"` 単体) は新規テストケースを1件も追加しなくても既存10ケースの実行だけで常時 PASS してしまう (Pattern 2 型) と指摘し、`bats --filter` への絞り込みを提案した。しかし `/spec` で `bats --filter` を実機検証したところ、フィルタに一致するテストが0件でも exit 0 (成功) を返すケースがあることを確認した (ローカル Homebrew bats 1.14.0 では 0 件マッチ時に exit 1 だったが、本リポジトリの直近の precedent — #1334, #1363, #1103 — は bats 1.13.0 および CI の apt 版 bats (1.10.0 系、`docs/spec/issue-177-ci-bats-speed.md` で確認済み) で 0 件マッチ時に exit 0 になることを確認しており、CI 実行環境はローカルより古いバージョンのため precedent の結果を優先した)。`--filter` 単体は常時 PASS 問題を形を変えて再導入するリスクがあるため不採用とし、`grep "<新規テスト名>" tests/check-language-convention.bats` (存在確認、実装前は不一致) + `command "bats tests/check-language-convention.bats"` (新規テストを含む全件 PASS 確認) の2段構えパターン (#1334 以降の precedent) を採用した。Issue 本文の Pre-merge AC3 も同内容で更新済み (`gh-issue-edit.sh` 経由、本 `/spec` セッション内)。
- **新規テストケース要否**: Implementation Step 1 (`.github/workflows/test.yml` の `-U` 追加) は既存スクリプトへの新規分岐ロジック追加を伴わない (呼び出し元のコマンドライン引数追加のみ)。Implementation Step 2 で追加する回帰テストは、`check-language-convention.py` 自体の新規分岐ではなく、既存ロジックの未カバー入力パターン (フェンス開始マーカーが hunk 外にあるケース) に対するカバレッジ追加であり、上記の「Pre-merge AC3 の verify command 具体化」で必要性を確認済み。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (Autonomous Auto-Resolve Log): `/issue` フェーズでのコンテキスト拡大アプローチ採用の判断根拠を記録。Issue 本文の `## Auto-Resolved Ambiguity Points` に既に反映済みで追加対応不要。 https://github.com/saitoco/wholework/issues/1452#issuecomment-5385872333
- saito / MEMBER / first-class / Triage AC audit: Pre-merge AC3 (`command "bats tests/check-language-convention.bats"`) が新規テスト追加なしでも常時 PASS するリスク (Pattern 2) を指摘、`bats --filter` への絞り込みを提案。本 Spec の `## Notes` の通り、`--filter` 単体は0件マッチ時に exit 0 となるリスクがあるため不採用とし、`grep` (存在確認) + フルスイート実行の2段構えパターンへ具体化して Issue 本文にも反映済み。 https://github.com/saitoco/wholework/issues/1452#issuecomment-5385886533
- (code phase) 新規コメントなし (cutoff: 2026-08-23T12:17:59Z、`phase/ready` ラベル付与時点)
- (review phase) 新規コメントなし (cutoff: 2026-08-23T12:24:37Z、`phase/review` ラベル付与時点)

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1・2 とも Spec の記述通りに実装した。

### Design Gaps/Ambiguities
- Step 9 の Behavioral Change Detection が、`tests/visual-diff-adapter.bats` 内のコメント (`.github/workflows/test.yml` は Node ランタイムを提供する、という無関係な文脈での言及) を検出してフルスイート実行 (`bats --jobs 18 tests/`, 全2011テスト) を要求した。実際には `language-convention` ジョブとは無関係な参照だったが、Behavioral Change Detection のロジックはコメント行と実コード参照を区別しないため、この判定通りフルスイートを実行した (全件 PASS、10分の Bash tool ceiling 内で完走)。Spec 自体には影響なし。

### Rework
- なし

## review retrospective

### Spec vs. implementation divergence patterns
- なし。PR diff (`.github/workflows/test.yml` の2箇所、`tests/check-language-convention.bats` の新規回帰テスト1件) は Spec の Implementation Steps 1・2 と完全に一致していた。

### Recurring issues
- なし。同種の指摘の再発は見られなかった。

### Acceptance criteria verification difficulty
- なし。4件の Pre-merge AC のうち3件 (rubric, grep, grep) は safe mode で決定的に判定でき、残り1件 (`command "bats tests/check-language-convention.bats"`) も CI ジョブ `Run bats tests` の実行範囲 (`bats --jobs $(nproc) tests/`) が対象テストファイルを含むことを identity confirmation で確認したうえで CI 参照フォールバック経由の PASS に到達できた。UNCERTAIN は0件。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- 4件の Pre-merge AC を safe mode で全て決定的に判定 (rubric 1件、grep 2件、CI参照フォールバック経由の command 1件)。UNCERTAIN・FAIL なし。
- review-light エージェント (4観点統合) による軽量レビューを実施し、MUST/SHOULD 相当の指摘なしを確認。CONSIDER 2件 (`-U100000` の将来的な境界条件、ドキュメント根拠の Spec 依存) はインラインコメントとして記録したが、スコープ最小化の方針により今回は対応を見送った。

### Deferred Items
- None (CONSIDER 2件は見送りとして記録済みで、追加のフォローアップ Issue 化は行っていない)

### Notes for Next Phase
- `/merge 1453` で問題なくマージ可能。Pre-merge AC 4件全て PASS 済み、Issue チェックボックスも更新済み。Post-merge AC は「なし」。
