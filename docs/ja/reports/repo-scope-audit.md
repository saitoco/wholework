[English](../../reports/repo-scope-audit.md) | 日本語

# リポジトリ外ファイルシステムアクセス調査レポート

**Issue**: #378 skills: 実行時のリポジトリ外ファイルシステムアクセスを調査・抑止
**Date**: 2026-04-24
**Status**: 対策実施済み（pre-merge）

---

## 再現手順

1. macOS で Claude Code を新規セッションとして起動する
2. システム設定 > プライバシーとセキュリティで Claude Code の「写真」「Apple Music」「メディアと Apple Music」許可を revoke してから開始する（TCC プロンプトを再発火させるため）
3. Wholework をプラグインとして有効化し、リポジトリを開いた状態にする
4. 任意の skill（例: `/issue "dummy"` または `/spec 378`）を実行する
5. 実行中に「"Claude" が写真ライブラリ/Apple Music/メディアライブラリにアクセスしようとしています」等の TCC プロンプトが順次表示されるのを観測する

---

## 原因

### macOS TCC (Transparency, Consent, and Control) の仕組み

macOS TCC は以下の保護対象ディレクトリへのアクセスを監視し、初回アクセス時に許可ダイアログを表示する:

- `~/Pictures/Photos Library.photoslibrary`（写真ライブラリ）
- `~/Music/`（Apple Music / ミュージックライブラリ）
- `~/Movies/`（メディアライブラリ）

TCC は Python/SQLite の明示的な読み取りだけでなく、**`opendir()` / `readdir()` などのファイルシステム列挙 API が保護対象パスをまたぐ**際にも発動する。したがって、`grep -r .` や `find . -name "*"` のような再帰スキャンが TCC 対象パスを含む親ディレクトリを起点に実行されると、明示的にそれらのファイルを読もうとしていなくても TCC プロンプトが表示される。

### 仮説の評価

静的解析の結果、3つの仮説を評価した:

| 仮説 | 内容 | 評価 |
|------|------|------|
| a | Claude Code の Glob/Grep/Read ツールがスコープ未指定の呼び出しで広範囲をスキャン | **該当可能性あり**（後述） |
| b | bash スクリプト内の `grep -rn ... .` が意図しない CWD で実行 | **部分的に該当**（後述） |
| c | Claude Code ランタイム側の挙動（Spotlight/mdfind 連携等） | **主要因と推定**（後述） |

#### 仮説 a: Glob / Grep ツール呼び出し

`skills/doc/SKILL.md` に以下の記述がある:

```
Search with Glob `**/*.md` ...
```

`path` パラメータなしの `Glob("**/*.md")` 呼び出しは、Claude Code 内部でカレントディレクトリ（CWD）を起点とする。通常 CWD はリポジトリルートなので安全だが、スキル実行コンテキストによっては CWD がリポジトリ外に設定される可能性がある。`modules/filesystem-scope.md` にガイダンスを追加することでこのリスクを文書化した。

#### 仮説 b: bash スクリプトの `grep -rn '^<<<<<<' .`

`scripts/worktree-merge-push.sh:89` に以下のコードが存在した:

```bash
conflict_output=$(grep -rn '^<<<<<<' . 2>/dev/null || true)
```

このスクリプトはリポジトリルート（`git rev-parse --show-toplevel`）から実行されるため、通常は `.` = リポジトリルートとなりリポジトリ外には出ない。ただし:

- `grep -rn` はシンボリックリンクをたどる可能性がある
- `.git/` ディレクトリ内のオブジェクトファイルも対象になる
- git submodule がリポジトリ外を参照している場合にも波及する

この箇所は `git grep -l '^<<<<<<'` に置き換えることで、**git が管理するトラックされたファイルのみ**に検索スコープを限定できる。

#### 仮説 c: Claude Code ランタイムの挙動（主要因と推定）

静的解析でリポジトリ外パスへの明示的なハードコードは発見されなかった。TCC プロンプトが**任意の skill 実行の初期段階**で現れる（特定の bash コマンド実行後ではなく、LLM がツールを起動し始めた段階で発生）ことから、以下が主要因として推定される:

- **Claude Code の内部ファイルインデックス処理**: Claude Code（Electron アプリ）が新規セッション開始時やプロジェクト読み込み時に、ファイルシステムをインデックスするために FSEvents API を利用する。この際、`$HOME` 配下を走査する場合がある
- **Glob ツールの OS-level 実装**: `Glob("**/*.md")` 等の呼び出しが OS の `opendir()/readdir()` を通じてファイルシステムを列挙する際、pattern が十分に制限されていないと TCC 対象ディレクトリをまたぐ

この仮説が正しい場合、skill 側だけでは完全な対処は困難だが、以下の対策でリスクを低減できる:

1. すべての Glob/Grep 呼び出しに明示的なスコープ付き `path` を指定する
2. bash スクリプトで `git grep` を使用してスコープを tracked files に限定する

---

## 該当箇所

| ファイル | 行番号 | 問題内容 | 優先度 |
|----------|--------|----------|--------|
| `scripts/worktree-merge-push.sh` | 89 | `grep -rn '^<<<<<<' .` — スコープが CWD 配下全体 | High |
| `modules/orchestration-fallbacks.md` | 176, 184 | `grep -rn '^<<<<<<' .` のドキュメント（スクリプトは修正済み、ドキュメントは歴史的参照として残す） | Low |
| `skills/spec/SKILL.md` | 235 | `grep -rn 'old-name' .` — リポジトリルートからの実行であること未明示 | Medium |
| `skills/doc/SKILL.md` | 333 | `Glob **/*.md` — `path` パラメータが明示されていない | Medium |

---

## 対策

### 実施済み（本 PR）

1. **`scripts/worktree-merge-push.sh`**
   `grep -rn '^<<<<<<' .` を `git grep -l '^<<<<<<'` に変更。
   `git grep` は git が管理するトラックされたファイルのみを検索するため、リポジトリ境界を越えたスキャンが発生しない。

2. **`modules/filesystem-scope.md`（新規）**
   Glob/Grep/Read ツールおよび bash スクリプトのファイルアクセススコープ制限ガイダンスを追加。許可されるベースパス・禁止パターン・推奨パターンを文書化。

3. **`skills/spec/SKILL.md`**
   rename-issue grep（`grep -rn 'old-name' .`）の実行条件として「リポジトリルートから実行すること」を明記し、`modules/filesystem-scope.md` への参照を追加。

4. **`docs/structure.md`**
   modules 数カウント更新（31 → 32）と `filesystem-scope.md` エントリ追加。

### 未対処（フォローアップ推奨）

- `skills/doc/SKILL.md:333` の `Glob **/*.md` に `path` パラメータを明示する（優先度: Medium） — [#382](https://github.com/saitoco/wholework/issues/382) で追跡中
- `modules/orchestration-fallbacks.md:184` のドキュメントを `git grep` 推奨に更新する（優先度: Low） — [#383](https://github.com/saitoco/wholework/issues/383) で追跡中
- Claude Code ランタイム側の挙動については Claude Code 本体 Issue として起票が必要（skill 側での対処不能） — 未起票

---

## 検証結果

### Pre-merge 検証

| 項目 | 状態 | 備考 |
|------|------|------|
| `scripts/worktree-merge-push.sh` での `grep -rn` 使用なし | ✅ PASS | `git grep -l` に変更済み |
| `modules/filesystem-scope.md` 作成済み | ✅ PASS | スコープ制限ガイダンス記載 |
| `skills/spec/SKILL.md` に scope 注記追加済み | ✅ PASS | CWD 明示注記追加済み |
| `docs/reports/repo-scope-audit.md` 存在 | ✅ PASS | 本ファイル |

### Post-merge 検証

新規 Claude Code セッションで TCC プロンプトが表示されなくなるかを以下で確認:

1. システム設定 > プライバシーとセキュリティで Claude Code の写真・Apple Music・メディアアクセスを revoke
2. 新規セッションで `/issue "dummy title"` を実行
3. `/code N` および `/verify N` を実行
4. TCC プロンプトが表示されないことを確認

**注意**: 仮説 c（Claude Code ランタイム挙動）が主要因の場合、本 PR の変更のみでは post-merge の手動検証で TCC プロンプトが解消しない可能性がある。その場合は `modules/filesystem-scope.md` に "Claude Code 本体への Issue 起票が必要" と追記し、Issue #378 の post-merge AC を「ガイダンス追加のみ」に縮小する。
