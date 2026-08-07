# L3 Session Retrospective: 89790-1786027911

## Metrics

**Session start**: 2026-08-06T14:51:51Z
**Session end**: 2026-08-07T02:15:00Z
**Wall-clock**: 11:23:09
**Route mix**: pr: 1 (#1206) · patch: 1 (#1202、post-spec M→S 降格) · skipped: 1 (#1205)

### Summary

| Metric | Value |
|---|---|
| Issues processed | 3 (#1206 / #1205 / #1202) |
| Throughput | 0.18 issues/hr (CI 障害による停止時間を含む) |
| Tier 1/2/3 recoveries | 0 / 0 / **1 (result=failed)** |
| Watchdog kills | 0 |
| **External kills** | **0** |
| Max silent window | 2360s (#1206 code-pr) |
| Concurrent commits detected | 4 |
| **Parent session manual interventions** | **1** (#1206 review、`review-rerun`) |
| verify FAIL → reopen fix cycles | 0 |
| Merge conflicts | 0 |
| Post-spec Size refresh | 1 (#1202: M → S) |

### Wrapper 一覧

| Issue | phase | exit |
|---|---|---|
| #1206 | code-pr | 0 |
| #1206 | **review** | **1** |
| #1202 | code-patch | 0 |

exit 1 は CI インフラ障害に起因する `run-review.sh` exit 2 (PENDING) の伝播であり、外部 kill シグネチャ (トレーラ欠落 + `wrapper_exit` 欠落) には該当しない。

## What worked

- **CI インフラ障害からの復旧が成立した**。`Validate skill syntax` が `Failed to resolve action download info. Error: Service Unavailable` で Set up job 段階から失敗し、`macOS shell compatibility` は QUEUED のまま停滞。CI ジョブの再実行のみで全 9 ジョブ pass に回復し、**コード修正・spec 見直しは一切不要**だった。障害当時から `Run bats tests` は SUCCESS で、実質的な検証は最初から通っていた
- **batch checkpoint が既完了 Issue を正しく扱えた**。#1205 は開始前に並行セッションが `phase/done` まで完走させており、`get-blocked-by.sh` / ラベル確認で検出して completed に記録し skip した
- **#1200 で新設した `get-blocked-by.sh` が実運用で機能した**。batch 開始時の blocked-by チェックに使用し、3 件ともブロッカーなしを GraphQL 経由で確認できた
- **#1202 の post-spec 降格 (M → S) が適切だった**。実変更は `skills/verify/SKILL.md` の 1 ファイル・14 挿入 7 削除に収まり、patch route で完走

## Findings

- **Skill 本文が会話単位でキャッシュされ、会話中の skill 更新が反映されない**。`/verify 1202` に渡された `skills/verify/SKILL.md` は「Re-verify even if already checked」という旧版だったが、ディスク上は #1186 (`9ccba45d`、2026-08-06 12:54 JST) のチェック済み AC スキップを既に持っていた。本会話で最初の `/verify` は同日 10:30 頃、`/compact` による再読込が 11:30 頃 — **以降 7 回の `/verify` がすべて 11:30 時点の版を使い回した**。#1186 が削減しようとしたフル bats スイート再実行のコストがそのまま残っていた。影響範囲は **wrapper を持たない `/verify` のみ** (spec/code/review/merge は `claude -p` の新プロセスでディスクから読み直す)。`#1206` の修正 (ローカル main 同期 + origin 比較) では救えない別機構 [No action: wholework 利用者ではなく self-hosting 開発者固有の問題のため Issue 化不要とユーザーが判断 (2026-08-07)。メモリ `feedback_skill_body_cached_per_conversation` に保存済み]
- **`/auto` の Tier 1/2/3 が CI インフラ障害を分類できない**。Tier 1 (reconciler) は `matches_expected: false` と正しく報告し Tier 3 が `action=retry` を選んだが、障害が継続していたためリトライも失敗 (`result=failed`)。`skills/verify/SKILL.md` Step 5 には既に **CI Infrastructure Failure Detection** の判定表 (steps が空 / timeout / runner error / network error) が存在するが `/verify` 内でのみ使われ、`run-review.sh` の exit 2 経路や `/auto` の recovery ラダーからは参照されない。結果として**親セッションが `gh run view --log-failed` を手で読んで初めて切り分けられた** [No action: `/verify 1206` の Verify Retrospective に Improvement Proposal として記録済み。同じ障害を別セッションも #1214 で踏んでおり (`cause: ci-infra-outage-during-ci-wait`)、頻度が上がれば起票を再検討]
- **#1206 の提案 C は本 batch では発火しなかった**。#1202 が post-spec で patch route に降格し PR を持たなかったため、`gh pr merge` 後の PR ファイル一覧を見る実装は適用対象外だった。初回発火は次に `skills/` を含む pr route の PR が merge される時で、それが #1206 の post-merge observation AC の観察対象そのもの [No action: observation AC が追跡済み]
- **#1202 の新経路 (Step 2 の closes 突き合わせ) を守るテストがない**。`tests/verify.bats` には SKILL.md の構造テストが既に 21 件あるが (Step 2 guard / Step 5 / Step 8c)、今回追加された突き合わせ経路は対象外。将来の編集で静かに失われても現状どのテストも落ちない。Phase Handoff が「bats テストは存在しない (SKILL.md プローズが対象)」と意識的に記録している [No action: `/verify 1202` の Verify Retrospective に記録。次に Step 2 を触る Issue で回収するのが自然]
- **Tier 3 失敗後の親セッション手動復旧を、記録し忘れかけた**。本日 #1174 でも同じ omission があり、そちらは `manual_intervention` が別セッションに誤帰属した (PGID ポインタ再生成を忘れたため)。本件は L3 retrospective 作成時の集計 (`recovery_tier2_3: 1`) で気づき、`--write-manual-recovery` をポインタ再生成つきで実行して正しい `session_id` で記録できた [Resolved directly: `docs/reports/orchestration-recoveries.md` に `manual-recovery-review-rerun` として記録 (commit `5933b1ea`)、`manual_intervention` イベントも本セッションに正しく帰属]

## Auto Retrospective

### Improvement Proposals

N/A — 上記 Findings はいずれも既存の記録先 (メモリ / 各 Issue の Verify Retrospective / observation AC) で追跡済み、または本セッション内で解決済み。新規起票なし。

## Skill Self-Update Propagation Note

Session 中に以下の skill が origin 上で更新されました (比較対象: `origin/main`)。ローカル main が追従できていない場合、本 session 内の以降の実行や次回セッションが更新前の版を使う可能性があります:

- `skills/auto/SKILL.md`: `ac2af751` → `12339eec`
- `skills/code/SKILL.md`: `6a08557c` → `9a8b3c55`
- `skills/spec/SKILL.md`: (no change)
- `skills/verify/SKILL.md`: `7c6c0437` → `9a8b3c55`
- `skills/review/SKILL.md`: (no change)
- `skills/merge/SKILL.md`: (no change)
- `skills/issue/SKILL.md`: `8e317b92` → `9a8b3c55`
- `skills/audit/SKILL.md`: `0028ad27` → `12339eec`

**本 Note 自体が #1206 の成果である。** 比較対象がローカル HEAD から `origin/${BASE_BRANCH}` に変わり (`skills/auto/SKILL.md:877-884`)、文言も「本 session には未適用」という誤った前提から上記の条件付き表現に修正された。旧実装のままなら、ローカル main が origin に追従していない状況でこの 5 件の差分は「no change」と報告され、乖離が不可視になっていた。

ただし **`/verify` については別機構のキャッシュ問題が残る** — 上記 Findings の 1 件目のとおり、ディスク上のファイルが最新でも、会話単位でキャッシュされた skill テキストは更新されない。本 Note はディスク/origin の乖離しか検出できない。
