# Issue #1141: worktree-lifecycle: worktree 実行内の main-repo 限定 Step の扱いを明文化

> Size XS のため `/spec` フェーズはスキップされた。本ファイルは `/auto` Step 4b (XS route の issue retrospective 転記) により作成され、`/verify` が retrospective を追記している。

## Issue Retrospective

`/issue 1141 --non-interactive` によるリファインメント結果。

### 事実確認 (advisory)

Background 内のコードベース参照 (`modules/worktree-lifecycle.md`, `scripts/emit-event.sh` の `emit_event`/`restore_auto_session_pointer`, `skills/verify/SKILL.md` Step 1/11 の `phase_start`/`phase_complete`) はすべてコードベースに実在を確認済み。訂正なし。

### Auto-Resolve Log (非対話モード)

優先度順 (影響度の大きい順) に 2 件を自動解決:

1. **`source` 経由呼び出しブロック時の推奨順序**: 「Worktree Exit 後に実行する」を主パターン、「ベストエフォートとして飛ばす (欠落リスクを明記)」を Exit 直前の自然な区切りがない場合 (例: Step 8b の `verify_user_confirm`) の代替パターンとして記載する方針とした。根拠: Background 記載済みの #1179 の実際の回避策 (Step 13 完了後に emit) が前例として存在し、AC3 の rubric 文言も両方の選択肢を許容しているため AC テキストへの影響はない (auto-resolve 条件を充足)。
   - 不採用候補: 常に best-effort skip のみを記載 (イベント欠落リスクの説明が弱くなる)
2. **新規記載の配置**: `modules/worktree-lifecycle.md` の既存 `## Notes` セクション配下に新規サブセクションとして追加する方針とした。根拠: 同セクションには類似の worktree 制約サブセクション (`.claude/` files editing、Edit/Write path conventions) が既に 2 件存在し一貫性がある。AC4 の要件とも整合し、AC テキストへの影響はない。
   - 不採用候補: 新規トップレベルセクションとして追加 (既存構成との一貫性が下がる)

両ポイントとも Issue 本文に `## Auto-Resolved Ambiguity Points` として記録済み。

### Acceptance Criteria 変更

- Post-merge の observation 条件に `session=next` を付与 (`scripts/check-skill-change-observation-ac.sh` の検出による)。理由: Background が `skills/verify/SKILL.md` を参照しており、この Issue を処理する会話セッションでは変更後のスキルがロードされないため、次回セッションでの評価が必要と判定した。

### スコープ評価

Size=XS、Pre-merge/Post-merge のセクション構成は既存のまま維持 (分割不要)。非対話モードのためサブ Issue 分割評価 (Step 12) はスキップ。タイトルドリフトなし。

> 転記元: https://github.com/saitoco/wholework/issues/1141#issuecomment-5199181398 (`/auto` Step 4b)

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC4 の verify command が heading 引数を `"## Notes"` と先頭に `#` を含む形で記述しており、**実装の成否に関わらず恒久的に UNCERTAIN** になる状態だった。しかも Auto-Resolve Log の 2 番目の項目が「AC4 (`section_contains ... "## Notes" "ExitWorktree"`) の要件とも整合し」と、この欠陥のある form を**根拠として引用**していた
- **`/issue` の AC 監査はこの欠陥を指摘しなかった**。本 Issue は `triaged` ラベル済みだったため Step 2 の triage auto-chain がスキップされ、`skills/triage/skill-dev-verify-audit.md` の Pattern 表監査に到達しなかった。#1083 が同 batch の直前に Pattern 6 (常時 UNCERTAIN、サブパターン 1 = heading 引数の `#`) を追加していたにもかかわらず、参照経路が開かなかった
- `session=next` の自動付与 (`check-skill-change-observation-ac.sh` による検出) は適切。Background が `skills/verify/SKILL.md` を参照しており、実装が本セッション中に landed する以上、observation の評価は次セッション以降でないと成立しない

#### spec
- Size XS のため `/spec` フェーズはスキップ (該当なし)

#### code
- 実装は `modules/worktree-lifecycle.md` の `## Notes` 配下に 3 サブセクション (main-repo 限定 Step の往復手順 / `mv` 拒否時の `cp` 代替 / `source` 経由呼び出しのブロック) を追加、25 行。AC1〜3 の要求をすべて満たしている
- 特に AC3 の記述は、扱いを 2 パターン (Worktree Exit 後に実行 / best-effort skip) に整理したうえで、後者では「明示的にスキップした旨を記録すること。黙って握り潰すと L3 retrospective メトリクスや session 境界検出が劣化する」と欠落リスクまで書いており、Issue の意図を正確に汲んでいる

#### review / merge
- patch route のため未実行 (該当なし)

#### verify
- **本 Issue の Background 事例 2 が、この `/verify` 実行でそのまま再現した**。Step 11 の `phase_complete` emit が `source` 経由のためブロックされ、実装が追加した「Worktree Exit 後に実行する」パターンを適用して回避した。記載内容が実運用で機能することの確認になっている
- AC4 の verify command はユーザー指示により `"## Notes"` → `"Notes"` へ訂正した (`/verify` は通常 Issue 本文を自動編集しないが、明示指示を優先)。訂正後は `## Notes` セクション (97〜159 行) 内の `ExitWorktree` の有無で PASS / FAIL が正しく判定される
- 訂正判定の際、簡易スクリプトがコードブロック内の `# Example: modify a .claude/ file via Python` を見出しと誤認し、セクション範囲を 97〜103 行と誤って算出した。コードフェンスを考慮して再評価し 97〜159 行に修正した。`section_contains` を手で再現する際の落とし穴として記録する
- `/auto` Step 4b (XS route の issue retrospective 転記) を実行し忘れており、`/verify` の途中で気づいて本ファイルを作成した。#1083 では Spec が既に存在したため転記のみで済んだが、本 Issue は Spec 自体が存在せず、`append-consumed-comments-section.sh` が "no spec file for issue #1141, skipping" を出したことで発覚した

### Improvement Proposals

- N/A (新規起票なし)。検出した 2 点はいずれも既存の記録先で処理済み:
  - **`triaged` 済み Issue で AC 監査が走らない構造** → #1083 のコメントに記録済み。ユーザー判断により「サポート方法は別途検討」として保留 (メモリにも保持)
  - **`/auto` Step 4b の実行漏れ** → 本セッション内で検出し復旧済み。手順自体は skill に明記されており、実装・記述の欠陥ではなく実行時の見落とし
