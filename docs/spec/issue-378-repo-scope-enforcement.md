# Issue #378: skills: 実行時のリポジトリ外ファイルシステムアクセスを調査・抑止

## Overview

Claude Code 上で Wholework の skill（`/auto`, `/issue`, `/spec`, `/code`, `/verify` など）を macOS で実行すると、写真ライブラリ・Apple Music・ミュージックとビデオの履歴・メディアライブラリに対する macOS TCC (Transparency, Consent, and Control) 権限プロンプトが表示される事象を観測した。プライバシー／セキュリティ上、skill 実行時のファイルシステムアクセスはリポジトリ配下に限定すべき。本 Spec では実機トレースで原因箇所を特定し、該当箇所への scope guard 追加と再発防止ガイダンスの整備を行う。

## Reproduction Steps

1. macOS で Claude Code を新規セッションとして起動する（TCC 許可ダイアログを再度トリガーするため、システム設定 > プライバシーとセキュリティから Claude Code の「写真」「Apple Music」「メディアとApple Music」項目を revoke しておくと良い）
2. Wholework を pulgin として有効化し、リポジトリを開いた状態にする
3. 任意の skill（例: `/issue "dummy"` or `/spec 378`）を実行する
4. 実行中に「"Claude"が写真ライブラリ/Apple Music/メディアライブラリにアクセスしようとしています」等の TCC プロンプトが順次表示されるのを観測する

## Root Cause

静的コード調査（`/issue` フェーズで実施）では以下が判明している:

- `scripts/`, `skills/`, `modules/` にリポジトリ外（`~/Pictures/`, `~/Music/`, `~/Library/`, `/Users/*/Documents/` 等）を指すハードコードパスは存在しない
- worktree は `.claude/worktrees/` 配下に作成されており、リポジトリ外には広がらない
- `scripts/worktree-merge-push.sh:89` と `modules/orchestration-fallbacks.md` で `grep -rn '^<<<<<<' .` が使われる。CWD が worktree 内であれば安全
- `skills/spec/SKILL.md:235` の rename-issue grep 検査に `grep -rn 'old-name' .` が documented されている

静的調査だけでは "どの tool invocation が実際に media library に触れているか" は確定できないため、**Implementation Step 1 で実機トレース（`fs_usage` / Console.app のプライバシーログ）を取り、再現条件と該当コードパスを特定**した上で修正を入れる。現時点の仮説:

- a) Claude Code の Glob/Grep/Read ツールが、pattern や base path 未指定の呼び出しで広範囲にスキャンしている
- b) Bash ツール内の `grep -rn ... .` や `find .` が意図しない CWD（HOME 付近）で実行されている
- c) Claude Code ランタイム側の挙動（Spotlight/mdfind 連携など）で、skill 指示書と独立にアクセスが発生している — この場合は skill 側では対処不能なので、レポートに記録して Issue に追記

## Changed Files

- `docs/reports/repo-scope-audit.md`: new file — 再現結果・原因箇所・対策をまとめた調査レポート。`## 再現手順`, `## 原因`, `## 該当箇所`, `## 対策`, `## 検証結果` を含む
- `scripts/worktree-merge-push.sh`: 必要に応じて `grep -rn '^<<<<<<' .` のスキャン起点ガード追記（CWD 検証や `git ls-files | xargs grep` への置換など。調査結果次第）
- `skills/spec/SKILL.md`: rename-issue grep 検査の `grep -rn 'old-name' .` について、リポジトリルート配下からの実行であることを明示する注記を追記
- `modules/` 配下の適切なモジュール（調査結果次第で `domain-loader.md` / `adapter-resolver.md` / 新規 `filesystem-scope.md` のいずれか）: Glob/Grep/Read を skill から使う際のスコープ制限ガイダンス追加

## Implementation Steps

1. 実機再現とトレース取得 — Reproduction Steps に沿って TCC プロンプトを再現し、`sudo fs_usage -w -f filesystem | grep -i -E 'Photos|Music|Library'` や Console.app のプライバシーサブシステムログを取得、どのプロセス（Claude Code 本体 / subprocess / bash）が何のパスに触れているかを切り分ける（→ `## 原因` 特定の前提）
2. `docs/reports/repo-scope-audit.md` に調査結果を記録 — Step 1 で得られた実機トレース結果、仮説 a/b/c のどれに該当するか、該当コードパスをファイル名:行番号で列挙し、「原因」セクションに macOS TCC の仕組みと関係を含めて記述（→ AC `file_exists "docs/reports/repo-scope-audit.md"`、AC `section_contains "## 原因" "TCC"`）
3. Scope guard 実装 — Step 1-2 で特定した該当箇所に修正を入れる。bash 側の場合は `grep -rn` の起点パスを明示／`find` に `-maxdepth` を追加／CWD アサート。skill 側の場合は Glob の base path を repo 相対で固定（→ AC `scripts/ 配下でリポジトリ境界を越える再帰スキャンが存在しない`）
4. ガイダンスの追加 — skill/modules 側で Glob/Grep/Read を使う場合に「リポジトリ配下を base にすること」「pattern は明示的にスコープ限定すること」を文書化（→ AC `skill 指示書に filesystem スコープ制限ガイダンスが追加されている`）
5. 再現確認と `## 検証結果` 追記 — Step 1 の再現手順を再実行し、TCC プロンプトが出ないことを確認、`docs/reports/repo-scope-audit.md` の `## 検証結果` セクションに結果を記録（→ Post-merge AC）

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/ 配下の bash スクリプトで、Glob/find/grep のスキャン起点がリポジトリルート配下に限定されている。$HOME や ~/ を起点にツリーを再帰探索する箇所が存在しない（設定ファイル単体の存在確認や .wholework 設定読み込みなど、単一パスへのアクセスは除く）" --> scripts/ 配下でリポジトリ境界を越える再帰スキャンが存在しない
- <!-- verify: rubric "modules/ および skills/ の SKILL.md で、Glob/Grep/Read ツールの利用時にスコープをリポジトリ配下に限定するガイダンスが追加されている、あるいは明示的に範囲を狭める記述が含まれている" --> skill 指示書に filesystem スコープ制限ガイダンスが追加されている
- <!-- verify: file_exists "docs/reports/repo-scope-audit.md" --> `docs/reports/repo-scope-audit.md` に調査結果（原因・該当箇所・対策）がまとめられている
- <!-- verify: section_contains "docs/reports/repo-scope-audit.md" "## 原因" "TCC" --> 調査レポートの「原因」セクションで macOS TCC の関与について言及されている

### Post-merge

- 新規 Claude Code セッションで `/issue "<dummy title>"` を実行した際、写真ライブラリ・Apple Music・メディアライブラリに対する macOS 権限プロンプトが表示されない
- `/code N` および `/verify N` を実行した際、上記ディレクトリに対する権限プロンプトが表示されない
- 本 Issue で追加されたガイダンスに従って既存 skill の修正が行われ、`/auto` の代表シナリオで再現しない

## Notes

- 静的調査では root cause を確定できないため、Implementation Step 1 の実機トレースが本 Spec の成否を左右する最重要ステップ
- トレース結果が仮説 c（Claude Code ランタイム側の挙動）だった場合は skill 側で対処不能。その場合は `docs/reports/repo-scope-audit.md` に "wholework では対処不能。Claude Code 本体への issue 起票が必要" と記録し、Issue #378 の post-merge AC を "ガイダンス追加のみ" に縮小する旨を親 Issue にコメントする
- `docs/reports/repo-scope-audit.md` は既存の `docs/reports/` 配下への追加のため、`docs/structure.md` の Directory Layout の tree 更新は不要（既に `reports/` エントリが存在）
- Size M のまま進行。Step 1 のトレース結果で影響範囲が拡大した場合（複数 scripts / module への大規模修正が必要など）は L に re-size
- bash compat note: `scripts/worktree-merge-push.sh` を編集する場合、bash 3.2+ 互換を維持する（macOS 標準 bash 対応）

## Code Retrospective

### Deviations from Design

- 実機トレース（Step 1: `fs_usage` / Console.app）は `--non-interactive` モードのため実施不可。代わりに静的解析と macOS TCC の挙動原則から仮説評価を行い、`docs/reports/repo-scope-audit.md` に記録した
- Step 3 の「scope guard 実装」は `worktree-merge-push.sh` の `grep -rn` → `git grep` 変換のみ実施（他に bash 側の `$HOME` 起点スキャンは発見されなかったため追加変更なし）
- Step 5（再現確認）は post-merge 手動検証として defer（非インタラクティブモードでの TCC 再現は困難）

### Design Gaps/Ambiguities

- Spec の「実機トレース（Step 1）」が非インタラクティブ実行では不可能な前提で設計されていた。`--non-interactive` 時は静的解析 + 仮説評価で代替する旨を Spec に記録すべきだったが、実装時に auto-resolve した

### Rework

- テスト `tests/worktree-merge-push.bats` の conflict marker テストが `grep -rn '^<<<<<<' .` ベースのモックを使用しており、`git grep -l '^<<<<<<'` への変更後に FAIL。モックを git サブコマンドルーティング方式に更新した

## review retrospective

### Spec vs. implementation divergence patterns

実装は Spec の受け入れ基準をすべて満たした（4 条件 PASS）。ただし以下の構造的パターンを記録する:
- `worktree-merge-push.sh` の `grep -rn` → `git grep -l` 変換は動作的に正しいが、変数名 `conflict_output` が内容の変化（行番号付き → ファイル名のみ）を反映していない。Spec の実装ステップに「変数命名も更新すること」を明記すべきだった。

### Recurring issues

- CONSIDER 指摘 2 件がいずれも同一行 (`worktree-merge-push.sh:90`) に集中し、変数名 + exit code 処理の 2 観点から同一の変更を指している。この種の「関連する複数 CONSIDER が同一箇所に集まる」ケースは `/review` でなく `/verify` フォローアップとして積み残すのが適切。

### Acceptance criteria verification difficulty

- 4 条件すべてが `rubric`, `file_exists`, `section_contains` で自動判定可能であり、UNCERTAIN なし。verify command の設計として良い事例：`rubric` で意味的判定、`file_exists`/`section_contains` でファイル存在・内容を補完する組み合わせが機能した。

## Auto-Resolved Ambiguity Points（`/issue` phase より転記）

- **Issue タイプを「バグ調査 + 修正」として定式化** — 理由: 観測事象は意図しない副作用であり修正対象と判断
- **原因仮説を「広範囲の Glob/find/grep によるリポジトリ境界越えスキャン」に絞り込み** — 静的調査で外部ハードコードが無いことを確認したため
- **成果物として `docs/reports/repo-scope-audit.md` を要求** — 原因特定と該当箇所マッピングを検証可能な形で残すため
- **対象 skill を特定せず「代表シナリオ」で検証** — ユーザー入力が特定 skill を指定していないため、一般化したガイドライン整備を優先
