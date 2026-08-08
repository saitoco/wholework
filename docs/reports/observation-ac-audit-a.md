# observation AC 実査: 区分 A (#1163 由来 29 AC 行) — #1274

親 #1270 の sub-issue。#1163 が `verify-type: manual` → `verify-type: observation` へ再型付けした **29 AC 行** (`event=auto-run` 27 / `event=fix-cycle` 2、対象 Issue 29 件) を対象に、「指定 event が発火したとき、何を根拠に PASS/FAIL を判定できるか」を 1 行ずつ実査し、A/B/C/D/E に分類して処理した記録。

## 実行前提と対象集合

**baseline 確認**: 親 #1270 の baseline レポート `docs/reports/observation-ac-audit-summary.md` (2026-08-08 計測、母集団 85 AC 行 / 82 Issue) が sub-issue 着手前に存在することを確認済み。分類 D の retire に着手してよい実行前提が充足されている。

**29 行の内訳**: #1163 の再型付けマッピング (`docs/spec/issue-1163-manual-ac-retype-a.md`) が出典。`event=auto-run` 27 行、`event=fix-cycle` 2 行 (#707 / #700)。対象 Issue は 29 件 (#719 は条件2 のみが対象、条件1 は `manual` 維持で対象外)。Issue 本文の「対象 Issue 34 件」は #1163 の全体スコープ (36 AC 行 / 34 Issue) 由来の数字であり、実査対象は 29 Issue が正 (差分 5 件 #708 #704 #501 #500 #479 は `manual` 維持対象外行のみを持つ)。

**着手前の GitHub 実状態再スキャン (2026-08-09 実測)**: 対象 29 行のうち **3 行が既に `- [x]` (PASS)** — #869 (`phase/verify` 継続、他条件が未チェックのため)、#759 (`phase/done`)、#520 (`phase/done`)。この 3 行は分類 **A** として記録し (「指定 event の発火時に判定できた」ことの直接的な実証)、追加処理は行わない。残り **26 行**が本セッションでの実査対象。26 行はすべて CLOSED + `phase/verify` の状態だった。

## dispatch 経路の制約

`observation-trigger.sh`/`opportunistic-search.sh` のゲート属性 (`keyword=` / `config=` / `when=`) が `auto-run` / `fix-cycle` の各 dispatch 経路で実際に有効かどうかをまとめる (`modules/observation-trigger.md` および各発火元コードを確認して確定)。

| event | 発火元 | `--session` 渡し | `when=route/mode/recovery-tier` | `when=execution-context` | `config=<key>` | `keyword=<text>` |
|---|---|---|---|---|---|---|
| `auto-run` | `skills/auto/SKILL.md` の Post-completion event scan | あり | 有効 (run facts から解決) | 有効 | 有効 (`.wholework.yml` を直接参照、session 不問) | **無効** (`--context-file` を渡さない) |
| `fix-cycle` | `skills/verify/SKILL.md` の FAIL→reopen 経路 | **なし** | **fail-open (無条件マッチと同義)** | 有効 (発火 skill 自身の `--execution-context` 引数から解決) | 有効 | **無効** (`--context-file` を渡さない) |

したがって、分類 B の条件文書き換えで付与してよいゲート属性は **`when=` と `config=` の 2 つのみ**であり (`fix-cycle` では `when=route/mode/recovery-tier` は実質無意味)、`keyword=` はいずれの経路でも付与しても不活性となる。本実査ではこの制約に従い、#769 (`event=auto-run`) にのみ `when=mode:batch` を追加した (batch 実行が条件の必須前提のため)。

## 分類サマリ

| 分類 | 件数 | 内訳 |
|---|---|---|
| **A** (判定可能、維持) | **19** | 既 PASS 3 (#869 #759 #520) + 実査で維持 16 (#1045 #856 #852 #822 #807 #806 #804 #778 #770 #765 #761 #760 #758 #755 #724 #719) |
| **B** (条件文書き換えで判定可能) | **7** | #769 #737 #736 #732 #731 #707 #700 |
| **C** (event 差し替え) | **0** | 該当なし |
| **D** (判定不能・retire) | **1** | #762 |
| **E** (`manual` へ差し戻し) | **2** | #861 #859 |
| **合計** | **29** | — |

## 実査表

| Issue | AC 行要約 | event | 分類 | 判断根拠・変更内容・retire 理由・差し戻し理由 |
|---|---|---|---|---|
| #869 | silent no-op 観測時に `code_retry_fire` が記録される | auto-run | A (既 PASS) | 2026-08-09 時点で `- [x]` 済み。`/auto` 実行内で実証済み |
| #759 | Tier 2/3 自動回復発生 Issue の `/verify` で新基準判断が一意 | auto-run | A (既 PASS) | 2026-08-09 時点で `- [x]` 済み、`phase/done` |
| #520 | skill mis-dispatch 由来の silent no-op が観察されない | auto-run | A (既 PASS) | 2026-08-09 時点で `- [x]` 済み、`phase/done` |
| #1045 | 次回 external kill 発生時に control-flow/subprocess kill を `.tmp/auto-events.jsonl` の `wrapper_alive` イベントとの時刻差分から判別 | auto-run | A | `.tmp/auto-events.jsonl` は Step 8c の評価対象 (「関連 session_id の .tmp/auto-events.jsonl イベント、ファイルが現存する場合」)。`run-auto-sub.sh` は `wrapper_alive` を 6 箇所で emit しており、kill 発生時にファイルが現存すれば時刻差分計算が可能。ファイル不在時の SKIPPED は正常挙動 |
| #861 | 並列セッション環境で phase 開始時に他セッション由来 dirty が warning 表示される | auto-run→**manual** | **E** | `run-*.sh` 全 5 種の dirty-check 分岐 (`run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh`) を確認したところ、other-session 検出時の warning は `echo ... >&2` のみで `emit_event` も git-tracked ファイルへの記録も行わない。ターミナル出力が消えると後から異なるセッションが遡って確認できる痕跡が残らない。`/verify` 実行時に Claude が意図的に別 worktree/session 由来の dirty ファイルを構築して `check-verify-dirty.sh` を実行すれば直接確認できるため E |
| #859 | 並列セッション環境で他セッションの作業ファイルと自セッションの作業中ファイルを区別して判定 | auto-run→**manual** | **E** | `check-verify-dirty.sh` の `classify=self-worktree/other-worktree/other-session/parent-main` 出力は呼び出し単位の stderr のみで永続化されない。#861 と同根の理由で E。`/verify` 実行時に 4 パターンのダミーファイルを構築し `check-verify-dirty.sh` を直接実行すれば判定可能 |
| #856 | merge なし reopen Issue に `/auto $N` 実行時、fix-cycle と誤判定されず通常の issue/spec phase に進む | auto-run | A | reopen 状況は GitHub timeline (`ClosedEvent` → `ReopenedEvent`、間に `MergedEvent` なし) から確定可能。誤判定の有無は reopen 後の Spec 生成・phase ラベル遷移という git-committed な証跡から判定できる |
| #852 | reopen 後の Issue に `/auto $N` 実行時、code phase が正しく実行される | auto-run | A | `reconcile-phase-state.sh` の `_completion_code_patch` (`reopen_ts != null` gate) の挙動は、reopen 後の commit/PR 有無という永続的な git/GitHub 履歴から確認可能。fix-cycle は日常的に発生するため機会も豊富 |
| #822 | manual recovery 発生時、対象 sub-issue の Spec に `## Auto Retrospective` が自動追記される | auto-run | A | 追記対象は git-committed な Spec ファイル自身。`docs/reports/orchestration-recoveries.md` の "parent session manual recovery" エントリと突合すれば判定可能 (#882 #893 等の先例あり) |
| #807 | batch session で run-*.sh kill 発生時、wrapper レベル自動 retry が `docs/reports/orchestration-recoveries.md` に記録される | auto-run | A | 条件文が自身の証跡先を名指ししている。`run-auto-sub.sh` の `_write_wrapper_retry_recovery` が同ファイルへ commit することを確認済み |
| #806 | run-auto-sub.sh kill 発生時、`/auto --resume N` で manual recovery 不要に正常完走 | auto-run | A | #1045 と同型。`.tmp/auto-events.jsonl` の phase_start/phase_complete 系列 (中断→resume 後の完了) に加え、`orchestration-recoveries.md` に manual recovery エントリが存在しないことの両方から確認可能 |
| #804 | migration/rename/削除を伴う Issue の `/spec` で Changed Files に symbol grep 結果が反映 | auto-run | A | `skills/spec/SKILL.md` の 3 段階 symbol-grep 手順 (#771 #770 #775 の先例参照) を確認済み。生成される Spec の `## Changed Files` は git-committed な永続的成果物 |
| #778 | migration Issue (path 変更) で Spec 生成時に SKILL.md + script の対称的 `file_not_contains` AC が含まれる | auto-run | A | `modules/verify-patterns.md` §16 に該当ガイダンスが存在。生成 Spec の内容確認で判定可能 |
| #770 | 2 つの `/auto --batch` 同時起動で各 session の report が他 session の Issue を含まない | auto-run | A | `modules/observation-trigger.md` が「時系列比較」型として明示的に許容するパターン (#1159 と同型)。実際に重複起動が発生した場合、`docs/sessions/{id}-{date}/session.md` のタイムスタンプと Issue 一覧が git-committed な証跡として残る |
| #769 | batch 実行後の `/audit auto-session --full` で Per-Issue Durations table が実処理 Issue 数と一致 (乖離率 < 10%) | auto-run | **B** | #875 (commit `78116b16`) でスタンドアロンのデータ層レポートが廃止され `session.md` の `## Metrics` に統合済み。「Per-Issue Durations table」という名称は現行の `### Sub-Issue Completion Timeline` に一致せず Form 1 (参照ファイル名指し) を満たさない。条件文を現行実装に合わせて書き換え、`when=mode:batch` を追加した |
| #765 | PR で正当な `per-Issue Spec` 等の記述が commit に含まれた際、Forbidden Expressions check が PASS | auto-run | A | `check-forbidden-expressions.sh` の hyphen/backtick 隣接除外ロジックと `tests/check-forbidden-expressions.bats` の拡張を確認済み。CI 実行結果 (`gh pr checks`) は GitHub state として Step 8c の評価対象 |
| #762 | batch/XL session で両レポート生成時、データ層レポート末尾に L3 retrospective への See also リンクが出力 | auto-run | **D (retire)** | #875 (commit `78116b16`) によりスタンドアロンのデータ層レポート自体が廃止されたため、リンクを張る対象が存在しない。原理的に判定不能 |
| #761 | Tier 2 fallback catalog 適用 Issue の Spec に `## Auto Retrospective` の anomaly エントリが含まれる | auto-run | A | `run-auto-sub.sh` の `_write_tier2_recovery_to_spec` を確認済み。`docs/reports/orchestration-recoveries.md` は 13 件の Tier 2 発生を記録しており、頻度も十分 |
| #760 | batch session で Tier 2 リカバリ発生時、`/audit auto-session <id>` レポートの Improvement Candidates Surfaced に symptom 表示 | auto-run | A | `get-auto-session-report.sh` の Tier 2 表面化ロジック (`recoveries-auto-fire.threshold` 参照、`IMPROVEMENT_CANDIDATES` 出力) と `### Improvement Candidates Surfaced` セクションが #875 後も現存することを確認済み |
| #758 | 新 SSoT モジュール作成時、新 checklist が実行され review phase で SSoT 乖離 SHOULD が出ない | auto-run | A | `skills/code/SKILL.md` の SSoT Module Cross-Check (Reference consistency / "How to Reference" accuracy) を確認済み。新規 SSoT モジュール作成有無と review コメント履歴は repo/GitHub state から判定可能 |
| #755 | 新 skill 作成時、`execution-context.md` を参照して context check が標準化される | auto-run | A | `modules/execution-context.md` は既に複数 skill から参照されており (`skills/code/SKILL.md` 等)、新規 skill の SKILL.md に同参照が含まれるかは repo state で確認可能 |
| #737 | `get-sub-issue-progress.sh` 変更 Issue で direct test が regression を検出 | auto-run | **B** | 「regression を検出することを観察」は反証不能な表現 (テストが green のまま完了しても「バグがなかった」のか「テストが検出できない」のか区別できない)。「変更途中で少なくとも一度 FAIL し修正後 green 化」という判定可能な形へ書き換えた (Form 3) |
| #736 | get-auto-session-report.sh 変更 Issue で direct unit test が regression を検出 | auto-run | **B** | #737 と同根の反証不能性。当該スクリプトは #763 #766 #805 #848 #870 #875 #900 #1007 #1098 #1159 #1279 で繰り返し変更されており機会は十分だが、条件文自体を書き換えた |
| #732 | phase-handoff.md 変更 Issue で `bats tests/phase-handoff.bats` が regression を検出 | auto-run | **B** | 同根の反証不能性。#1041 (commit `ee81181c`) で共変更の先例が既にあるが、それが実際に regression を捕捉したかは条件文からは判定できないため書き換えた |
| #731 | test-runner.md 変更 Issue で `bats tests/test-runner.bats` が regression を検出 | auto-run | **B** | 同根の反証不能性。#843 #1097 #1123 #1213 で繰り返し共変更されているが、同様に書き換えた |
| #724 | git diff ベース比較ロジックの Spec で該当節が参照され、code phase で marker file 追加 rework がゼロ | auto-run | A | 「`base/head 比較 bats テスト`」節への参照有無と Code Retrospective の rework 記述は、いずれも git-committed な Spec ファイルから確認可能な永続的事実。該当 Spec が二度と現れなくても SKIPPED のまま維持されるのが正しい挙動 (「事前排除できない条件」に該当) |
| #719 (条件2) | `issue-710` の Forbidden Expressions pre-existing FAILURE 解消後、`pre-merge-check.sh` が baseline=PASS 状態で正常動作 | auto-run | A | `bash scripts/check-forbidden-expressions.sh` は 2026-08-09 実測でも exit 0 を維持しており前提は充足済み。`run-merge.sh` は PR route の全 merge で `pre-merge-check.sh` を呼び CLEAN/FIXED/PRE_EXISTING/NEW_FAILURE を分類するため、直近の merge 履歴から判定可能 |
| #707 | `/verify N` を意図的に FAIL させ、機械可読 marker 付き comment が append される | fix-cycle | **B** | `skills/verify/SKILL.md` の FAIL→reopen 経路が `type=verify-fail` marker を実際に投稿していることを #998 の実コメントで確認済み。「意図的に FAIL させ」という表現は不要な前提を課しており、通常運用中の自然発生 FAIL でも成立する旨へ書き換えた (Form 3) |
| #700 | `auto-retry-on-fail.enabled: true` 下で `/verify N` を意図的に FAIL させ、`/code` 再発火→再検証→PASS または budget 枯渇で停止 | fix-cycle | **B** | 本リポジトリの `.wholework.yml` は既に `auto-retry-on-fail.enabled: true`。#998 (`Retry Count: 1/3` → PASS)・#702 (`Retry Count: 2/3` → PASS) の Spec `## Verify Retrospective § Retry Count` に実例が既に存在することを確認済み。「意図的に FAIL させ」を「自然発生 FAIL でも可」へ書き換え、判定に使うファイル (Spec の Retry Count セクション) を明示した (Form 1, 3) |

## 分類 B/C: 変更内容とマッチ集合再確認

分類 C (event 差し替え) は該当なし (0 件)。分類 B は 7 件、変更後も同一 `event=` のままとした (#769 のみ `when=mode:batch` を追加)。

**マッチ集合再確認** (Step 6、event ごとに 1 回のみ実行):

- `bash scripts/opportunistic-search.sh --event auto-run --dry-run` (2026-08-09 実行、母集団 77 Issue、実行時に `run facts carry no run context (empty issues, mode=unknown), disabling when= condition check gate` の警告により `when=mode:batch` は fail-open — 単体 dry-run では意図通りマッチする): 変更した #769 / #737 / #736 / #732 / #731 の **5 件すべてが個別にマッチ集合へ含まれることを確認**
- `bash scripts/opportunistic-search.sh --event fix-cycle --dry-run` (2026-08-09 実行、母集団 5 Issue): 変更した #707 / #700 の **2 件すべてが個別にマッチ集合へ含まれることを確認**

意図的にマッチ集合から外した行はない (`when=mode:batch` を付与した #769 も、実 `/auto --batch` 実行時の `--session`/`--facts-file` 経由では `mode:batch` の facts が解決されるため、batch 実行時にのみマッチする設計どおりに機能する見込み)。

## 分類 D: retire 実施記録

| Issue | retire 理由 (要約) | コメント URL | 本文非編集の確認 | 遷移後ラベル |
|---|---|---|---|---|
| #762 | データ層レポート (`docs/reports/auto-session-*.md`) は #875 で廃止済みであり、リンク先そのものが存在しないため原理的に判定不能 | https://github.com/saitoco/wholework/issues/762#issuecomment-5228250155 | 確認済み — `### Post-merge` 節の該当 AC 行は編集せずそのまま残した (`- [ ]` のまま) | `phase/verify` → `phase/done` (retire 後に他の未チェック post-merge 条件が残らないことを確認したうえで遷移) |

## 分類 E: 差し戻し記録

| Issue | 差し戻し理由 | `/verify` 実行時の判定手順 | capability |
|---|---|---|---|
| #861 | dirty-check の other-session warning は `echo ... >&2` のみで永続化されず、`auto-run` 発火時に別セッションが遡って確認できる証跡がない | `/verify` 実行時に、別 issue 番号の worktree パス (例: `.claude/worktrees/code+issue-999999/dummy.txt`) や `docs/sessions/<foreign-id>-*/dummy.md` にダミーファイルを作成し、`bash scripts/run-spec.sh <test-issue>` または直接 `bash scripts/check-verify-dirty.sh <issue番号>` を実行して `classify=other-worktree`/`classify=other-session` と warning 文言 (フェーズは中断されない) を確認する。確認後はダミーファイルを削除する | 装備待ちではない (即判定可能、ただし `/verify` 実行時に Claude が能動的に構築する必要がある) |
| #859 | `check-verify-dirty.sh` の `classify=` 出力は呼び出し単位の stderr のみで永続化されない。#861 と同根 | `/verify` 実行時に 4 パターン (self-worktree / 他 worktree / 他セッション `docs/sessions/` / parent-main) のダミーファイルをそれぞれ作成し `bash scripts/check-verify-dirty.sh <自 issue 番号>` を実行、各パターンで正しい `classify=` 値が出力され、self-worktree のみブロックされず他は warning のみであることを確認する。確認後はダミーファイルを削除する | 装備待ちではない (即判定可能、ただし `/verify` 実行時に Claude が能動的に構築する必要がある) |

いずれも `.wholework.yml` の capability 不足によるものではなく、「`auto-run` の受動的な発火待ちでは証跡が残らないが、`/verify` 実行時に Claude が能動的にシナリオを構築すれば判定できる」という理由による差し戻しのため、`capability=<key>` の対象はゼロ件。

## 親 #1270 への引き継ぎ

- **D/E 内訳**: D (retire) 1 件 (#762)、E (`manual` へ差し戻し) 2 件 (#861 #859)。observation waiting の減少 3 件のうち、**純減は 1 件 (#762 の retire)**、**型間移動 (observation → manual) は 2 件 (#861 #859)** であり、型間移動分は `manual` waiting の増加として現れる (純減とは区別が必要)。
- **E の「即判定可能」と「装備待ち」の分離**: 差し戻した E 2 件はいずれも `.wholework.yml` capability 不足が理由ではなく「即判定可能 (ただし `/verify` 実行時に Claude が能動的にシナリオを構築する必要がある)」に分類される。装備待ち (`capability=<key>`) の E は **0 件**。
- B 7 件は event を維持したまま条件文のみ書き換えたため、observation waiting の総数には影響しない (退避・型間移動のいずれにも該当しない)。
- A 19 件 (既 PASS 3 件を含む) はそのまま観察継続。

## Consumed Comments

cutoff は本 Spec 側 (`docs/spec/issue-1274-observation-ac-audit-a.md`) の `## Consumed Comments` 節を参照。
