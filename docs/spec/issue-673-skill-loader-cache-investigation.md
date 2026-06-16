# Issue #673: skill-loader: Skill Loader Cache Behavior Investigation

## Overview

Claude Code の Skill tool がセッション開始時に SKILL.md をスナップショットして保持する挙動を調査し、文書化する。2026-06-15 のセッションで `Skill(skill="wholework:audit", args="stats --retention --no-save")` を起動した際、Skill tool が古い版の `skills/audit/SKILL.md`（`--retention` flag 等を含まない約 700 行版）を読み込んだ。ディスク上の実体は最新版（1241 行）であったにもかかわらず、セッション内では更新が反映されなかった。

調査結果を `docs/reports/skill-loader-cache-behavior.md` にまとめ、「いつ snapshot されるか」「reload trigger は何か」を明記する。

## Reproduction Steps

1. セッション開始直後にコミット時点の `skills/foo/SKILL.md` がロードされる
2. セッション中に同 SKILL.md を `git pull` / 別セッションマージ等で更新する
3. 同セッションで `Skill(skill="foo", args=...)` を再起動する
4. 起動された skill 内容が更新前の版になっていることを確認する

完全な再現には skill loader 実装の知識が必要なため、再現性確認は Post-merge AC に含める。

## Root Cause

**観測されている挙動**: Claude Code は Skill（プラグイン）の SKILL.md をセッション開始時にロード（スナップショット）し、セッション中はそのまま保持する。ファイルシステム上の変更はセッション内で再ロードされない。

**既存文書への記載**: `docs/workflow.md:131` に `/auto` セッション向けの同現象が既に文書化されている（「`/auto` loads `skills/auto/SKILL.md` (and other Skills/Modules) at session start and keeps this snapshot throughout the run」）。Issue #673 で確認されたのは、この挙動が `/auto` だけでなく対話型 `Skill(...)` 呼び出しにも同様に適用されることである。

**推定メカニズム（2案）**:
1. Claude Code セッション開始時にプラグイン配下の全 SKILL.md が LLM コンテキストに注入されるため、セッション中は更新が反映されない（セッション内スナップショット）
2. `~/.claude/plugins/cache/` 等のプラグインキャッシュ層が古いコピーを保持し、ファイル変更が透過されない（キャッシュ層起因）

どちらのメカニズムかは外部ツール（Claude Code）の内部実装に依存するため、現時点では観測的証拠のみで文書化する。修正アプローチは「仕様として明文化し、ユーザー / 自動化に周知」（Issue 目的の Option 3）が現実的。

## Changed Files

- `docs/reports/skill-loader-cache-behavior.md`: 新規ファイル — Skill loader キャッシュ挙動の調査レポート

## Implementation Steps

1. `docs/reports/skill-loader-cache-behavior.md` を作成する（→ 受入条件 1, 2, 3）

   以下のセクションを含める:

   **概要と背景**: Issue #673 で観測された症状（セッション起動版と実体の乖離）と関連事例（#485: `/auto` セッション内 SKILL.md self-apply risk）を記述する。

   **snapshot のタイミング（"snapshot" キーワード必須）**: Claude Code は Skill（プラグイン）の SKILL.md をセッション開始時にスナップショットして LLM コンテキストに注入する。セッション中のファイル変更は反映されない旨を明記する。`docs/workflow.md:131` の既存文書と一貫した記述にする。

   **reload trigger（"reload" キーワード必須）**: セッションを終了して新規セッションを起動することが唯一の reload trigger であることを明記する。セッション内でのホットリロード手段は確認されていない旨を記述する。

   **影響シナリオ**: (a) `/auto` セッション中に SKILL.md を変更するマージが走った場合、(b) 対話セッション中に SKILL.md が更新された場合（今回の事例）を列挙する。

   **推定メカニズム**: 上記 2 案（セッション内スナップショット vs キャッシュ層）を仮説として記述し、確定的な結論は Post-merge 再現テストに委ねる旨を記載する。

   **推奨ワークアラウンド**:
   - `docs/workflow.md:131` の既存ガイダンス（SKILL.md を変更するマージは `/auto` と同セッションで処理しない）を参照リンクで示す
   - 対話セッションでも同様: SKILL.md 更新後は新規セッションを開始する

   **結論**: 「session 内 snapshot は仕様」として扱い、docs/guide/troubleshooting.md への注記追加を Post-merge タスクとして推奨する旨を記述する。

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/skill-loader-cache-behavior.md" --> Skill loader の挙動を調査し、session 中の SKILL.md 変更が反映される条件を `docs/reports/skill-loader-cache-behavior.md` に文書化
- <!-- verify: grep "snapshot" "docs/reports/skill-loader-cache-behavior.md" --> 上記文書に「いつ snapshot されるか」が明記されている
- <!-- verify: grep "reload" "docs/reports/skill-loader-cache-behavior.md" --> 上記文書に「reload trigger は何か」が明記されている

### Post-merge

- 仕様として固定する場合は CLAUDE.md または docs/guide/ に "session 中の skill 更新は反映されない" 旨を注記 <!-- verify-type: manual -->
- 別セッションで意図的に再現テスト（コミット → pull → 同セッション skill 起動）し、想定通り snapshot されることを確認 <!-- verify-type: manual -->

## Uncertainty

- **メカニズムの詳細**: セッション内スナップショット（LLM コンテキスト注入）なのか、キャッシュ層起因なのかは Claude Code の内部実装に依存する。
  - **検証方法**: Post-merge AC の再現テスト（コミット → pull → 同セッション skill 起動）で、snapshot がセッション開始時点に固定されることを確認する。
  - **影響範囲**: Implementation Steps 1（レポートの記述精度）。確定的な結論が出ない場合は仮説形式で記述する。

## Notes

- `docs/reports/` は翻訳同期義務対象外（`docs/translation-workflow.md` の Exclusions セクション参照）。Japanese mirror 不要。
- `docs/workflow.md:131` に `/auto` 向けの同現象と対策が既に記述されており、本レポートはそれを補完する形（対話 `Skill(...)` 呼び出しへの適用を明記）。
- Post-merge 手動 AC「docs/guide/troubleshooting.md への注記追加」は本 PR のスコープ外。調査レポート内で推奨として記述するにとどめる。

### Auto-Resolve Log (non-interactive mode)

- **調査の深さ**: WebFetch による Claude Code 公式ドキュメント調査は不要と判断。既存コードベース（`docs/workflow.md:131`、`docs/routines-adoption.md:221`）に観測事実が記録されており、実装内容を文書化するのに十分な証拠がある。
- **レポート形式**: `docs/reports/ultrareview-spike.md` を参考に研究スパイク形式を採用（Markdown、英語ヘッダー + 日本語本文混在は既存スパイクレポートのパターンを踏襲）。
- **コンフリクトなし**: Issue 本文の前提記述（「Skill tool が古い版を読み込んだ」）は既存コード（`docs/workflow.md:131` の snapshot 記述）と整合している。

## issue retrospective

### 判断根拠と変更内容

**非対話モード (non-interactive) での自動実行。`AskUserQuestion` 不使用。**

#### Auto-Resolve Log

以下の 3 点を自動解決しました。

**1. AC2 verify command: BRE `\|` + `-q` フラグ問題の修正**

- **選択**: `grep "snapshot|reload"` の OR 条件ではなく、`grep "snapshot"` と `grep "reload"` の 2 AC に分割
- **理由**: コメント #1 の指摘通り `grep -q "snapshot\|reload"` は (1) `-q` が verify-executor の 2-arg 形式で非対応、(2) BRE `\|` が ripgrep (ERE) では `|` リテラルとして扱われ OR alternation として機能しない。修正として ERE 形式 `grep "snapshot|reload"` に直すこともできるが、OR 条件だと `snapshot` のみ存在しても PASS してしまう。AC の要件は「いつ snapshot される"か"」と「reload trigger は何か"」の両方の明記なので、2 AC に分割して独立検証する判断をした。
- **Other candidates**: 単一 `grep "snapshot|reload"` で `-q` と BRE のみ修正（OR 条件の弱さが残る）

**2. AC1: `file_exists` のパス引用符追加**

- **選択**: `file_exists "docs/reports/skill-loader-cache-behavior.md"` に修正
- **理由**: verify-executor の `file_exists "path"` 構文はパスを引用符で囲む形式が正しい。
- **Other candidates**: なし

**3. AC3: Pre-merge → Post-merge へ移動**

- **選択**: 「仕様として固定する場合は CLAUDE.md または docs/guide/ に注記」を Post-merge に移動
- **理由**: 「仕様として固定する場合は」という条件が調査結果（AC1/AC2 の文書化後）に依存するため、Post-merge が意味的に正しい。`verify-type: manual` の条件付き AC は Post-merge に置くのが適切。
- **Other candidates**: Pre-merge に残す（`verify-type: manual` なので自動フローへの影響は軽微だが、ステータスの見通しが悪い）

#### 受入条件の変更点

| 変更 | 旧 | 新 |
|------|----|----|
| AC1 引用符追加 | `file_exists docs/reports/...` | `file_exists "docs/reports/..."` |
| AC2 分割 | `grep -q "snapshot\|reload" ...` (単一 AC) | `grep "snapshot" ...` + `grep "reload" ...` (2 AC) |
| AC3 セクション移動 | Pre-merge に配置 | Post-merge に移動 |

## spec retrospective

### Minor observations

- Issue #673 は Bug タイプだが実質 Task（調査・文書化）のため、Reproduction Steps と Root Cause セクションを追加しつつ「fix」ではなく「document」方針で記述した。ISSUE_TYPE=Bug でも調査タスクは適切に扱える。
- `docs/workflow.md:131` に既存の snapshot 文書があったため、WebFetch 不要で設計を完了できた。既存コードベース調査が設計の短絡化に大きく寄与した。

### Judgment rationale

- **Option 3（仕様として明文化）を採用**: 外部ツール（Claude Code）の内部挙動を wholework 側で制御できないため、「session 内 snapshot は仕様」として文書化し周知するアプローチが最もリスクが低い。
- **WebFetch 不要の判断**: Issue 本文の観測（症状・乖離）は `docs/workflow.md:131` と `docs/routines-adoption.md:221` の既存記述で十分説明できるため、公式ドキュメント調査は不要と判断した。

### Uncertainty resolution

- **メカニズム詳細（セッション内スナップショット vs キャッシュ層）**: 外部ツールの内部実装に依存するため解決不可能。Post-merge の再現テスト AC で観測的に確認する。実装時は仮説形式で記述することにした。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- Spec で「研究スパイク形式を採用（英語ヘッダー + 日本語本文混在）」と記載されていたが、既存レポート（`ultrareview-spike.md`等）を参照した結果、日本語ヘッダーの方がコンテキスト上自然と判断し、日本語ヘッダーで統一した。Pre-merge verify command（grep "snapshot" / grep "reload"）はヘッダー言語と無関係なので影響なし。

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

- Spec Implementation Steps に「`docs/workflow.md:131` の既存ガイダンスを参照リンクで示す」と記載されていたが、実装ではプレーンテキスト参照（バッククォート）になっており、Markdown ハイパーリンクではなかった（CONSIDER レベル）。文書間の cross-reference はリンク形式が望ましいが、参照先が明確なため機能的影響はない。
- ヘッダー言語の偏差（英語→日本語）は Code Retrospective に記録済みで、verify command への影響はなかった。

### Recurring Issues

- 特になし。今回の PR は Markdown ドキュメント 1 ファイルの新規作成のみで変更スコープが小さく、同種の問題の繰り返しは観測されなかった。

### Acceptance Criteria Verification Difficulty

- 3件すべて `file_exists` / `grep` の自動検証可能コマンドで構成されており、UNCERTAIN なし。verify command の品質は高い。
- 本 Issue は Bug タイプだが実質 Task（調査文書化）であり、実行コード変更がないため regression test の観点は適用外。このパターン（Bug タイプ + document-only 変更）では review-light の Perspective 2（edge case/robustness）の観点がスコープ外になることを確認した。

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- MUST/SHOULD issue なし。2件の CONSIDER 所見のみ（Spec の参照リンク未設定 + ヘッダー言語偏差）。
- 受入条件 3件すべて PASS、CI 全 9 件 SUCCESS。
- 修正作業なし → Step 12/13 スキップ。

### Deferred Items

- docs/guide/troubleshooting.md への注記追加は Post-merge 手動 AC として残留。
- メカニズム確定（session-start snapshot vs キャッシュ層）は Post-merge 再現テストに委任。

### Notes for Next Phase

- PR #683: merge 準備完了。MUST issue 0 件。
- Post-merge AC: `docs/guide/troubleshooting.md` への注記追加（手動）、再現テスト（手動）の 2 件が残留。
