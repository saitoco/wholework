# Skill Loader Cache Behavior — Investigation Report

**Issue**: #673
**Date**: 2026-06-16
**Status**: Documented (mechanism is an external-tool constraint; workaround identified)

---

## 概要と背景

2026-06-15 のセッションで `Skill(skill="wholework:audit", args="stats --retention --no-save")` を起動した際、Skill tool が古い版の `skills/audit/SKILL.md` を読み込む事象が発生した。

- ディスク上の実体: `skills/audit/SKILL.md` は **1224 行**（`--retention` flag、`progress <XL>` / `auto-session <id>` subcommand を含む現行版）
- Skill tool に届いた system prompt: **`--retention` flag を含まない古い版**（Usage 文字列に `progress` / `auto-session` / `--retention` がすべて欠落、行数 ~700）

同様の事象は以前にも観測されている。`docs/workflow.md:131` に `/auto` セッション向けの記述がある（「`/auto` loads `skills/auto/SKILL.md` (and other Skills/Modules) at session start and keeps this snapshot throughout the run」）。Issue #673 で確認されたのは、この挙動が `/auto` だけでなく対話型 `Skill(...)` 呼び出しにも適用されることである。

---

## Snapshot のタイミング

**Claude Code は Skill（プラグイン）の SKILL.md をセッション開始時にスナップショット（snapshot）して LLM コンテキストに注入する。セッション中のファイル変更は反映されない。**

具体的には以下のタイミングで snapshot が固定される:

1. `claude` セッション（または `claude -p` プロセス）の起動時
2. プラグイン配下の `SKILL.md` 群が LLM システムプロンプト / コンテキストに読み込まれる
3. 以降、同セッション内では SKILL.md のディスク上の変更が透過されない

この挙動は `/auto` セッション（`run-*.sh` 経由の子プロセス）でも、対話型 `Skill(skill="...", args="...")` 呼び出しでも同一である。セッションをまたぐ（新規 `claude` プロセスを起動する）場合のみ、更新後の SKILL.md が読み込まれる。

---

## Reload Trigger

現時点で確認されている唯一の reload trigger は**セッションの終了と新規セッションの開始**である。

| 操作 | SKILL.md 再ロード | 備考 |
|------|-----------------|------|
| 同セッション内で `Skill(...)` を再呼び出し | **なし** | session-start snapshot が維持される |
| 同セッション内で `git pull` / マージ後に再呼び出し | **なし** | ファイルが更新されても session snapshot は変わらない |
| `claude` セッションを終了して新規セッションを起動 | **あり** | 起動時に最新の SKILL.md が読み込まれる |
| `claude -p` として新規プロセスを起動 | **あり** | run-*.sh 経由の子プロセスも起動時に snapshot |

セッション内でのホットリロード（`/plugin reload` 相当のコマンド）は現時点で確認されていない。

---

## 影響シナリオ

### シナリオ (a): `/auto` セッション中に SKILL.md を変更するマージが走った場合

`docs/workflow.md:131` に既述。`/auto` は `skills/auto/SKILL.md` をセッション開始時に snapshot するため、セッション途中でマージされた SKILL.md 変更は後続フェーズに反映されない。Issue #485 / PR #498 で実際に観測された（`run-verify.sh` が削除された PR を `/auto` で自己適用した際、verify フェーズが削除済みスクリプトを呼び出してクラッシュ）。

### シナリオ (b): 対話セッション中に SKILL.md が更新された場合（今回の事例）

1. セッション開始時に `skills/audit/SKILL.md` の旧版（~700 行）が snapshot される
2. セッション中に別セッション / CI マージ等で `skills/audit/SKILL.md` が最新版（1224 行）に更新される
3. 同セッションで `Skill(skill="wholework:audit", args="stats --retention ...")` を起動
4. Skill tool は session-start snapshot（旧版）を使用するため `--retention` flag を認識しない

---

## 推定メカニズム（仮説）

メカニズムの詳細は Claude Code の内部実装に依存するため、現時点では 2 つの仮説を記載する。確定的な結論は Post-merge 再現テスト（AC）に委ねる。

**仮説 1: セッション内スナップショット（LLM コンテキスト注入）**

Claude Code セッション起動時にプラグイン配下の全 SKILL.md が LLM コンテキスト（システムプロンプト）に注入される。LLM コンテキストはセッション中固定されるため、ファイルシステム上の更新は反映されない。

**仮説 2: プラグインキャッシュ層**

`~/.claude/plugins/cache/` 等のキャッシュ層が古いコピーを保持し、ファイル変更が透過されない。セッション再起動時にキャッシュが更新される。

両仮説で「セッション再起動が唯一の reload trigger」という観測事実と整合する。

---

## 推奨ワークアラウンド

### 1. `/auto` セッションでの SKILL.md 自己適用を避ける

`docs/workflow.md:131` のガイダンスを参照。SKILL.md / Module を変更する PR は `/auto` の単一セッションで自己適用しない。

推奨フロー（2択）:
- **merge まで実行 → 新規セッションで verify**: `/auto` を `/merge` まで実行後、新規 `claude` セッションで `/verify N` または `/auto --resume N` を実行する
- **手動フロー**: `/code` → `/review` → `/merge` → 新規セッションで `/verify`

### 2. 対話セッションでの SKILL.md 更新後

SKILL.md を更新（コミット / マージ）した後、同セッションで更新後の機能を使用したい場合は **新規 `claude` セッションを開始する**。

---

## 結論

「セッション開始時 snapshot は仕様」として扱う。Claude Code の外部ツール挙動であるため、wholework 側での制御は困難。

対応方針:
- **現在**: 本レポートと `docs/workflow.md:131` の既存ガイダンスで周知
- **推奨 Post-merge**: `docs/guide/troubleshooting.md` に「session 中の skill 更新は反映されない」旨を注記する（Post-merge 手動 AC）

本報告は観測的証拠に基づく。メカニズムの確定（仮説 1 vs 仮説 2）は Post-merge 再現テストで確認する。
