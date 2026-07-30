# Issue #1052: spec: 大量アセット追加時の content filtering 回避ガイドラインを追加

XS patch route のため `/spec` フェーズを経ておらず、本ファイルは `/verify` の improvement proposal パイプラインが issue retrospective を収集できるようにするために作成された (`skills/auto/SKILL.md` Step 4b)。実装は `f3743d46` (`chore: verify-patterns: add bulk asset ingestion content-filtering guideline (closes #1052)`) を参照。

## Issue Retrospective

### 実行モード

`--non-interactive` (三層ポリシー: auto-resolve / skip / hard-error) で実行。

### 曖昧ポイントの自動解決 (Auto-Resolve Log)

- **ガイドライン追加先ファイル: `modules/verify-patterns.md` に一本化** — reason: 元の AC2 (`grep` verify command) が既に `modules/verify-patterns.md` を検証対象に固定しており、同ファイルは既存の §1–§26 が spec 設計ガイドライン (Implementation Steps 記述パターン) を番号付きセクションとして蓄積する慣例を持つ (§7, §16, §19 等が類例)。また `skills/spec/SKILL.md` の Step 10 (Create Spec) は既に `modules/verify-patterns.md` を複数箇所で参照する構成になっており、同ファイルへの追加だけで `/spec` の設計ガイドラインへの反映として機能する。AC1 (rubric) の文言を「spec スキルまたは verify-patterns」から `modules/verify-patterns.md` 明記に修正し、AC1/AC2 間の対象ファイル不整合を解消した。
  - Other candidates: `skills/spec/SKILL.md` への直接追記 (Step 10 が既に長く、これ以上の肥大化を避けるため見送り)、両ファイルへの重複追記 (メンテナンスコスト増のため見送り)
- **「関連」節の worktree 中断復帰の話をスコープ外として維持** — reason: 本 Issue の Purpose は「大量アセット追加時の content filtering 回避ガイドライン追加」に限定されており、`modules/worktree-lifecycle.md` の変更は独立した改善提案であるため、AC化はせず情報提供コメントのまま残した。
  - Other candidates: 本 Issue の AC に追加 (スコープ拡大により Size 判定・実装範囲に影響するため見送り)

### AC 変更の理由

- AC1 (rubric) の文言を「spec スキルまたは verify-patterns」→「modules/verify-patterns.md」に修正。理由は上記の自動解決ログの通り。文言修正のみで、検証の意図・厳格さは変わらない。
- AC2 (grep) は変更なし。

### その他の判断

- Size XS のためサブIssue分割は評価不要 (非対話モードでも high-stakes decision として一律スキップ対象)。
- Blocked-by 関係は検出されなかった (`gh-check-blocking.sh` exit 0)。
- Background 内の事実主張 (content filtering インシデントの記述) はコードベース照合対象パターン (生成/呼び出し/依存の主張) に該当せず、advisory チェックはスキップした。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC1 (rubric) と AC2 (grep) で対象ファイルが食い違っていた (「spec スキルまたは verify-patterns」vs `modules/verify-patterns.md` 固定) 点を検出し、grep 側の具体性に合わせて rubric を修正することで解消した。AC 間の整合を issue フェーズで潰せた good case。
- 「関連」節の worktree 中断復帰の話をスコープ外として維持する判断も、Purpose との対照で明示的に記録されている。

#### spec
- Size=XS のため `/spec` フェーズは実行されていない。本 Spec ファイルは Step 4b (issue retrospective 転記) のために `/verify` 側で作成したもの。

#### code
- single-pass で完了 (`f3743d46`)。pre-merge AC 2 件が初回評価で PASS、rework なし。
- 追加された §27 は、背景に実インシデント (126 SVG 取り込みで ~360s の無音後に content filtering で wrapper exit 1) と、そこから導いた根本原因 (ファイルの存在自体ではなくバイト列が LLM 出力を経由することが引き金) を併記しており、ガイドラインとしての説得力が高い。

#### review
- patch route (XS) のため review フェーズなし。

#### merge
- patch route のため merge フェーズなし (main 直コミット)。

#### verify
- pre-merge 2 件すべて PASS、FAIL / UNCERTAIN なし、auto-retry 発火なし。
- post-merge の opportunistic 1 件は未チェックのまま `phase/verify` 留置 (設計どおり)。

### Improvement Proposals

- **`/issue` が同じ Size=XS の Issue に対して異なる `phase/*` ラベルを付けており、それが下流の spec 実行要否を左右している** (既存 Issue #1108 に追記する形で扱う): 本 batch 内で連続して処理した 2 件の XS Issue で、`/issue` 完了後のラベルが割れた。
  - #1054 (XS): `triaged phase/issue retro/verify` → `run-auto-sub.sh` の spec dispatch 条件 (`phase/ready` が無い) を満たすため **spec が実行され Spec ファイルが作成された**
  - #1052 (XS): `triaged phase/ready retro/verify` → `phase/ready` があるため **spec がスキップされ Spec ファイルは作られなかった** (その結果 Step 4b の転記が必要になった)

  つまり #1108 で報告した「`run-auto-sub.sh` が Size を見ない」問題は、`/issue` が XS に対して `phase/issue` を付けるか `phase/ready` を付けるかによって、発現したりしなかったりする。#1108 の対応方針を検討する際は、`run-auto-sub.sh` 側の Size 判定だけでなく、**`/issue` の XS 時ラベル付与が非決定的である点**も併せて見る必要がある。どちらか一方だけを直すと、もう一方の経路で同じ不整合が残る。本観察は #1108 にコメントとして追記済み。

### 観察

- 本 Issue も #1054 と同様、kill を含むオーケストレーション異常ゼロで issue → code → verify が完走した。batch 内で XS/patch route は 2/2 完走、M/L の pr route は #1066 が kill 3 回という対比が続いている。

## Consumed Comments
No new comments since last phase.
