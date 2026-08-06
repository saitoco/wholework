# L3 Session Retrospective: 11623-1785995193

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-06T05:47:36Z
**Session end**: 2026-08-06T10:35:22Z
**Wall-clock**: 04:47:46
**Route mix**: patch: 0, pr: 3, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 8 |
| Throughput | 1.7 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 2580s |
| Phase silent windows > threshold | 2 (review:1, spec:1) |
| Total token usage | input 9214 / output 302593 |
| Concurrent commits detected | 21 |
| Parent session manual interventions | 2 |
| verify FAIL → reopen fix cycles | 0 |
| Retro proposal tiers (1/2/3) | 1 / 1 / 1 (実測と乖離 — Findings 参照) |
| Merge conflicts | 0 |
| Commits since session start | 51 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-pr | 6 |
| issue | 4 |
| merge | 6 |
| review | 6 |

## What worked

**バッチが 1 つの観測系を成立させた。** 本セッションの 7 Issue のうち 4 件 (#1179 / #1191 / #1098 / #1152) が recovery 可観測性という単一のテーマで連鎖しており、最後に `/audit stats --retention` Section 10 の出力として結実した。

| Issue | 役割 |
|---|---|
| #1179 | 自動起票を opt-out にして発散を止めた |
| #1191 | 起票の代わりに可視化で穴を埋めた (Section 10) |
| #1098 | Tier 2 の永続記録を復元して母数を正した |
| #1152 | 誤検知と再発見落としを解消して精度を上げた |

Section 10 の最終出力 (20 group-key、tracking 情報付き) は 4 件すべての成果が反映された状態になっている。個別に着地させていたら、この「全部揃って初めて意味を持つ」構造は見えにくかった。

**同一セッション内での前後比較が最良の検証になった。** #1152 は実装前後の `collect-recovery-candidates.sh` 出力を同じセッションで比較でき、誤検知の解消 (`review-tier3-recovery` / `manual-recovery-review-rerun` の消滅) と再発見落としの解消 (`manual-recovery-respawn` 21 件 / `code-pr-tier3-recovery` 6 件の出現) を 1 回の比較で同時に実証した。observation AC が「次セッションを待つ」ものではなく即座に評価できた。

**skill 変更が同一セッション内で伝播することを確認した。** #1185 が新設した `/issue` Step 15 は、着地直後の `run-issue.sh 1098` で実運用初発火し、Step 7 が authoring した欠陥 verify command (`section_contains` の heading 引数に `###`) を自己検出して修正した。`session=next` 修飾子は「新しい会話セッションを待つ」意味ではなく「skill を新プロセスで読み直すこと」で満たされる、という運用解釈が確定した。#1141 (是正前、監査に到達せず欠陥がそのまま残った) との対比が明快。

**#1188 の効果を版差で実測できた。** `/verify 1152` の Step 1 で `check-verify-dirty.sh` が exit 2 (並行セッションの Spec に対し stash 提案) を返したが、これはローカル main が 4 commit 遅れた古い版だった。worktree (origin/main ベース) 内で再実行すると exit 0。並行セッション破壊経路が塞がれたことを同一セッション内の版差で確認した。

**verify の retrospective が上流の回帰を検出した。** `/verify 1185` の Step 12 skip 判定が「Tier 2 recovery が発火したのに `## Auto Retrospective` がない」という不整合を拾い、そこから #1181 が `_write_tier2_recovery_to_spec()` を削除した際に recoveries log への書き込み追加をセットで行わなかった回帰 (= Tier 2 の永続記録喪失) を特定した。`docs/spec/issue-1015-fix-recovery-spec-split.md` の Notes が事前にこの前提条件を警告していたことも判明し、#1098 のスコープ拡大につながった。

## Findings

- **event の session_id が並行セッション間で双方向に誤帰属する。** 本セッションで emit した #1191 の retro proposal 分類 2 件が別セッション `63129-1785977471` に記録され、逆に本セッションが扱っていない #1163 の分類 1 件が本セッションの events に流入した。原因は `.tmp/auto-session-current` が PGID 非依存の単一ファイルで並行セッションが互いに上書きすること。`restore_auto_session_pointer()` は PGID 別ファイルを先に見るが、Bash tool 呼び出しごとに PGID が変わるため in-session emit では常にフォールバック経路に落ちる。実害として Metrics の `Retro proposal tiers` が実測 (Tier1×3 / Tier2×2 / 計 5 件) に対し `1/1/1` (計 3 件) を示し、数も内訳も一致しない。[Filed: #1075]

- **`worktree-merge-push.sh` の base-checkout 経路に rebase fallback がなかった。** `main` がメインリポジトリに checkout されている通常運用では、FF 失敗時に in-place merge を試して即 `exit 1` していた (L88-95)。非 checkout 経路 (L96-116) には ancestry チェックと worktree rebase の fallback があり、`modules/worktree-lifecycle.md` L68 も「fallback あり」と記述していたため、ドキュメントと実装が乖離していた。本日 4 セッションで再発 (#1180 / #1179 / #1152 / #1098)。[Filed: #1076]

- **blocked-by 判定の SSoT が Issue body テキストで、GraphQL 関係が効かない。** #1191 に GraphQL で blocker 2 件 (#1152 / #1098) を正式設定していたが、body に `Blocked by #N` テキストがないため `/auto` List mode Step 4 の gate が素通りした。同 gate は body を grep する実装。`modules/l0-surfaces.md` は blocked-by relationships を L0 surface として列挙しており、実装が表の記述に追随していない。GitHub UI から設定した関係も同様に効かない。[Filed: #1200]

- **Section 10 の `tracked:#N` が対応 Issue の open/closed を区別しない。** `manual-recovery-respawn` は `tracked:#1014` と表示されるが #1014 は CLOSED (2026-07-13) であり、実態は「対応後に 21 件再発」。#1152 の entry 単位判定で検出はできるようになったが表示が追随しておらず、最も注意を要する状態が最も安全そうな表示になっている。[Filed: #1205]

- **`/issue` の AC 監査 (Step 15) の実行痕跡が Issue Retrospective に残らない。** #1098 のリファインで Step 15 が Pattern 6.1 違反を検出・修正したが、その事実は完了報告 (ターミナル出力) と AC の変化にしか残らず、Issue Retrospective コメントには言及ゼロ。#1141 の実測時に「Issue Retrospective 内の AC 監査への言及」を判定材料にしていた経緯を踏まえると追跡性に改善余地があるが、監査自体は機能しており AC の判定には影響しない。[No action: 追跡性の改善であり機能欠陥ではない。#1156 の verify retrospective にも同種の観察を記録済みで、2 件目の実例として蓄積した]

- **`scripts/check-translation-sync.sh` が drift 検出時も exit 0 を返す。** #1179 の AC 4 (`command "bash scripts/check-translation-sync.sh"`) は exit 0 で PASS 判定されたが、標準出力には `Summary: 2 OUTDATED, 1 MISSING_JA` が出ていた。`skills/triage/skill-dev-verify-audit.md` Pattern 2 (exit code 設計に起因する常時 PASS) に該当する可能性がある。[No action: 観測 1 件のみで、スクリプトの exit code 設計が意図的か未確認。同スクリプトを `command` 型 AC に使う際の注意点として #1179 の verify retrospective に記録済み]

- **`## Phase Handoff` セクションが 2 つ残存した (#1152 Spec)。** `<!-- phase: review -->` と `<!-- phase: merge -->` の両方が残っており、`modules/phase-handoff.md` の「最新 1 phase のみ保持 (rotation)」仕様に反する。review の Key Decisions に記録された Spec の "changed in both" 3-way merge が原因と推測される。[No action: 観測 1 件、実害は「verify がどちらを読むか曖昧」に留まる。再発したら phase-handoff 側に重複検出を入れる判断材料にする]

- **`/spec` の Worktree Exit で手動 rebase 復旧した際、`--write-manual-recovery` の呼び出しが一貫しない。** 同日の #1152 spec phase では記録されたが #1098 spec phase では記録されず、後者は `orchestration-recoveries.md` にも Spec にもエントリが残らなかった (#1098 が新設した Step 12 判定ルールがこれを notable content として検出した)。[No action: 手順自体は機能しており (記録された事例がある) LLM の判断ばらつきの問題。観測 1 件のため起票せず]

- **~~`manual-recovery-respawn` が 21 件積み上がっている。~~ (2026-08-06 訂正: 誤り)** 当初「#1014 (CLOSED 2026-07-13) の着地後に 21 件再発した」と記録したが、**この数字は #1152 の実装バグの産物**だった。同日中に #1152 が reopen され (session `74631-1786005349`)、`orchestration-recoveries.md` が newest-first であるのに cutoff となる `起票済み` entry を**ファイル出現順の最後 (= 最古)** で選ぶ実装が原因と特定された。cutoff が最古に落ちるため「cutoff より後」がほぼ全件カウントされる。検算では 22 entry 全件 marked / 最古の起票済み 2026-07-13 16:58 / それより後 21 件 が出力の 21 と一致する。`code-pr-tier3-recovery` (6) も同じ機序。[Resolved directly: #1205 に訂正コメントを投稿し、起票根拠が無効であることと今後の 3 案 (保留 / スコープ縮小 / close) を記載した]

- **本セッションの `/verify 1152` は AC 10 を誤って PASS と判定した。** AC 10 は「close 済みの対応 Issue が存在する group-key が候補として現れない」だが、出力に現れた `manual-recovery-respawn` (tracked:#1014 CLOSED) と `code-pr-tier3-recovery` (tracked:#799 CLOSED) は明確にこれに違反していた。`--with-tracking` の出力で tracking 情報を取得しており、続く `/verify 1191` では「#1014 は CLOSED」と明記までしていながら、AC 10 の文言と突き合わせていない。実装前後の出力変化 (2 件消えて 2 件現れた) が劇的だったため「誤検知の解消 + 再発見落としの解消」という解釈に合わせて読み、出力に現れた group-key 側の対応 Issue state を AC の条件に照らさなかった。rubric grader として「PASS より UNCERTAIN を優先」すべき場面だった。なお #1152 の verify-fail marker は、AC 10 の例示 (`manual-recovery-review-rerun` / `review-tier3-recovery` の 2 件) が「最新エントリのみ marked」という例外的な形だけを挙げており、`run-auto-sub.sh` が entry 書き込み時に自動刻印する結果として常態である「全 entry marked」の一般ケースを捕捉できていなかったことも指摘している。[No action: AC の文言は #1152 側で一般ケースを含む形へ更新済み。判定手順そのものへの改善提案は、同種の見落としが再発した場合に検討する]

- **Steering Doc sync candidate の抽出に `docs/product.md` が含まれなかった (#1191)。** `docs/structure.md` / `docs/tech.md` (+ `docs/ja/` 対訳) は正しく同期されたが、同じ Steering Document である `docs/product.md` の用語集エントリは候補から漏れていた。[No action: 観測 1 件、影響範囲も限定的。memory proposal として terminal 出力済み]

## Auto Retrospective

### Improvement Proposals

- event の session_id が並行セッション間で双方向に誤帰属する。`.tmp/auto-session-current` が PGID 非依存の単一ファイルで並行セッションが互いに上書きするため、in-session emit の帰属先がタイミング依存になる。Metrics の `Retro proposal tiers` が実測と一致しない実害を確認した
- `worktree-merge-push.sh` の base-checkout 経路 (`current_branch == BASE_BRANCH`) に rebase fallback がなく、FF 失敗時に即 exit 1 する。非 checkout 経路には fallback があり `modules/worktree-lifecycle.md` L68 の記述とも乖離していた
- blocked-by 判定の SSoT が Issue body テキストであり、GraphQL に正式設定した関係が `/auto` の batch gate に反映されない
- `/audit stats --retention` Section 10 の `tracked:#N` が対応 Issue の open/closed を区別せず、post-fix recurrence が「追跡済み」に埋もれる

## Filed Issues

- #1076
- #1075
- #1200
- #1205
