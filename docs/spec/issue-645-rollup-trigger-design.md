# Issue #645: auto-events-rollup: 自動実行トリガー（cron / git hook / Actions / 手動）の設計議論

Size XS — Spec は省略。設計議論型 Issue で Issue body 内に設計決定を直接記録。

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| issue | -     | SUCCESS | triage + 設計決定の Issue body 記録 |
| code  | patch | FAILED (exit 1) | silent no-op — 設計決定はすでに Issue body に記載済みで code 変更不要 |
| verify | -    | SUCCESS | claude-execute で manual AC 3 件 PASS 判定 → phase/done + close |

### Orchestration Anomalies
- **discussion-only Issue の routing 問題**: `/auto --batch` で discussion-only Issue (#645) が patch route に進入し、code phase が silent no-op で exit 1。recovery sub-agent (Tier 3) は abort を返したが、実態は code 変更不要な設計議論型 Issue であり、verify 段階で manual AC が PASS 判定可能だった。
- **Tier 3 abort 判定の False Negative**: recovery sub-agent の rationale「Human review of issue #645 is required」は正しいが、verify フェーズで manual AC を claude-execute して PASS と判定する経路がリカバリー枠外だった。

### Improvement Proposals
- (HIGH) Issue body に `<!-- implementation-type: metadata-only -->` または新規 `<!-- implementation-type: discussion-only -->` マーカーを `/issue` triage が自動付与する仕組みを追加。Size XS かつ AC が manual 中心の場合に検出して付与する。`/auto` 側で marker を見て code phase を skip し直接 verify に進む。
- (MEDIUM) `orchestration-fallbacks.md` に `discussion-only-no-op` パターンを追加 — code phase が silent exit で reconcile commits_found=false、かつ Issue body に「## 設計決定」「## Design Decision」相当のセクションがあれば skip 扱いに recover。
- (CONSIDER) Spec 不要かつ code 不要の "discussion-only" routing を auto に追加（Size XS の subtype として扱う）。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- triage が `/issue` 段階で AC 整備 + 設計決定の body 記録までを完遂。AC 全 3 件は `verify-type: manual` で pre-checked 状態に。
- 「設計議論型 Issue」の triage アウトプットが Issue body そのもの、という良パターン。

#### spec
- 省略 (Size XS)。

#### code
- silent no-op (exit 1)。実装変更不要な設計議論型のため。orchestration 異常として retrospective に記録。

#### review/merge
- 該当なし (patch route + no commit)。

#### verify
- manual AC 3 件を claude-execute (本セッション内 AI 判断) で PASS。recovery sub-agent の abort 判定を verify が補正した形。
- `phase/done` 遷移 + Issue close 実行。

### Improvement Proposals
- 上記 Auto Retrospective の Improvement Proposals と同内容。重複起票せず、retro-proposals collection 時に統合扱い。

