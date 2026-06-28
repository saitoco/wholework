# L3 Session Retrospective: 64057-1782615135

## What worked

- **List mode batch** で 11 Issue を 1 セッション中に直列処理し、全件で pre-merge AC を PASS させ phase/done または phase/verify (opportunistic/manual 残存) に着地できた。
- Post-spec Size demotion (M→S, M→XS, S→XS) が複数 Issue (#432, #434, #442, #443, #457) で発火し、不要に重い pr route を回避できた。Spec 段階での Size 再評価のフィードバックが効果的。
- Patch route の単純 verify (grep / section_contains / rubric / file_not_contains / command bats) は wholework 内部の文書 + SKILL.md 改修 Issue にうまく適合。
- Heartbeat と orphan spec stub (`issue-N-code.md`) の cleanup を毎 verify 前に手動コミットする運用で、`check-verify-dirty.sh` のブロックを回避できた。

## Limits and gaps

- **Orphan spec stub の頻発**: `run-auto-sub.sh` の patch route で spec phase を経ない場合、Consumed Comments セクションだけ書き込まれた `docs/spec/issue-N-code.md` という非標準ファイル名のスタブが untracked のまま残る。これにより毎 verify 前に rename + commit の手作業が発生 (#449, #453, #456 など 4 件)。`issue-N-<short-title>.md` への自動命名が望ましい。
- **Loop-state heartbeat の dirty 状態**: `docs/sessions/_daily/loop-state-2026-06-28.md` が auto-sub 完了時点で常に modified 状態になり、`check-verify-dirty.sh` exit 1 を引き起こす。verify 前に毎回手動コミットが必要。heartbeat の append 後に auto-sub が commit/push する運用にすれば本セッションのような batch でも摩擦が消える。
- **Loop-state heartbeat の duplicated row**: 例えば `loop-state-2026-06-28.md` で同じ `#796 spec→code` の行が連続 2 回出現するなど、重複行が記録されている。run-auto-sub.sh の append タイミングか、retry/recover 時の二重 append が原因の可能性。

## Improvement candidates

- **`run-auto-sub.sh` orphan spec stub の命名/抑制**: patch route で spec を経由しないとき、Consumed Comments のみのスタブを作らないか、Issue title から kebab-case の正式ファイル名で作成する。
- **Loop-state heartbeat の auto-commit**: heartbeat 追加直後にバックグラウンドで commit/push し、後続の verify が dirty 状態に巻き込まれないようにする (best-effort、batch 並列化時の競合は要検討)。
- **Loop-state heartbeat の重複行抑制**: append 時に同 timestamp+issue+from→to の組み合わせを deduplicate する。

## Auto Retrospective

### Improvement Proposals

- `run-auto-sub.sh` が patch route で生成する orphan spec stub `docs/spec/issue-N-code.md` を、Issue title 由来の kebab-case ファイル名 (`issue-N-<short-title>.md`) で作成するか、Consumed Comments のみであれば作成自体をスキップする。現状は 11 件中 4 件で手動 rename + commit を要した。
- `append-loop-state-heartbeat.sh` の呼び出し後に、heartbeat 差分を auto-commit + push する (best-effort)。これにより `check-verify-dirty.sh` が verify 直前で exit 1 になるのを回避し、batch の friction が解消される。
- `append-loop-state-heartbeat.sh` で同一 (issue, from→to, snapshot) の組合せが直前行と一致する場合は append をスキップする。重複行は機械可読性を損ねる。

---

## Filed Issues

- #819 — auto: XS patch route の orphan spec stub (issue-N-code.md) の命名/抑制
- #820 — scripts: append-loop-state-heartbeat.sh の同 transition 重複行を抑制

Note: #798 (heartbeat dirty による /verify ブロック解消) は CLOSED だが本セッションでも friction が再発した。改めて effectiveness を再評価する余地あり。

---

## See also

- [Data layer report](data-layer.md)
