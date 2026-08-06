# Issue #1191: audit: /audit stats --retention に recovery 候補頻度セクションを追加

## Consumed Comments

| login | authorAssociation | trust tier | 要旨 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/issue 1191 --non-interactive` の Issue Retrospective。着手時点で blocked-by #1152 / #1098 が両方 CLOSED 済みであることを確認。N/A エントリ除外を本 Issue のスコープに含める判断 (却下した代替案を含む) と Size S→M への変更理由を記録。内容は既に Issue 本文の `## Auto-Resolved Ambiguity Points` に反映済みで、Spec 設計に対する新規のアクション項目はなし。 | https://github.com/saitoco/wholework/issues/1191#issuecomment-5202756688 |

## Overview

`/audit stats --retention` に **Section 10: Recovery Candidate Frequency** を追加し、`collect-recovery-candidates.sh` が検出する recovery 候補の頻度を可視化する。#1179 で `recoveries-auto-fire` が既定 opt-out になったことで、閾値超過の group-key が誰にも気づかれず埋もれるリスクを解消する。起票は復活させず、Section 8 (phase/verify Retention Metrics) / Section 9 (Icebox Retention Metrics) と同じ「表 + 閾値超過の列挙」形式に揃えた読み取り専用の表示を追加する。

あわせて `scripts/collect-recovery-candidates.sh` に entry 単位の除外規則を追加する: `### Improvement Candidate` が `N/A` 系文言のみで構成される entry (Tier 2 fallback が「対応不要」として自動記録するもの) を候補集計から除外し、Section 10 の Untracked 閾値超過に誤って計上されないようにする。

## Changed Files

- `skills/audit/SKILL.md`: `### --retention Option` に Section 10 (Recovery Candidate Frequency) を追加。`RECOVERIES_AUTO_FIRE_THRESHOLD` 取得のため `detect-config-markers.md` 読み込みを追加。Step 4 Save の文言 (「Sections 8 and 9」→「Sections 8, 9, and 10」) を更新
- `scripts/collect-recovery-candidates.sh`: entry 単位の `N/A` 除外ロジックを追加。bash 3.2+ 互換 (既存コードと同じくインデックス配列のみ使用)
- `tests/collect-recovery-candidates.bats`: `N/A` 除外を検証する `@test` を 2 件追加
- `tests/audit-retention.bats`: 変更不要 (Read で確認済み — `scripts/compute-escalation-level.sh` のみを対象とし、本 Issue は同スクリプトに変更を加えない。Pre-merge AC 6 は回帰確認目的)
- `docs/structure.md` [Steering Docs sync candidate]: `collect-recovery-candidates.sh` の一行説明 (187 行目付近) が、既存の `起票済み` 除外と並んで新しい `N/A` 除外にも触れているか確認し、必要なら更新
- `docs/tech.md` [Steering Docs sync candidate]: 「`recoveries-auto-fire` default opt-out (#1179)」の記述 (129 行目付近) が頻度可視化の手段として汎用的な「`/audit stats`」を挙げているのみなので、Section 10 着地後は「`/audit stats --retention`」に絞る更新を検討

## Implementation Steps

1. `skills/audit/SKILL.md` の `### --retention Option` を変更する (→ Pre-merge AC 1, 2, 3):
   - セクション冒頭で `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` を読み込み、`RECOVERIES_AUTO_FIRE_THRESHOLD` を後続手順向けに保持する
   - Section 9 の閾値超過列挙文 (`List trigger fire candidate Issues...`) の直後、`#### Retire-Proposal Comment Posting` 見出しの直前に、以下を追加する:

     ```markdown
     #### Section 10: Recovery Candidate Frequency

     1. Run:
        ```bash
        ${CLAUDE_PLUGIN_ROOT}/scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 1 --with-tracking
        ```
        (`--threshold 1` returns every group-key with count >= 1 after entry-unit exclusion; filtering by `RECOVERIES_AUTO_FIRE_THRESHOLD` happens in this section, not in the script call. Entry-unit exclusion includes group-keys whose `### Improvement Candidate` entries are all `N/A` (resolved by known catalog, or synonymous N/A-family wording) — these are Tier 2 fallback successes that need no action, so the collector drops them before counting and they never surface here as Untracked threshold-exceeding.)
     2. If `docs/reports/orchestration-recoveries.md` does not exist, or the command produces no output: display "No recovery candidates found." and skip the rest of this section.
     3. From the output (`<group-key>\t<count>\t<tracked:#N|untracked>` per line), compute:
        - **Recovery group-keys (total)**: total line count
        - **Threshold-exceeding group-keys**: count of lines whose `<count>` >= `RECOVERIES_AUTO_FIRE_THRESHOLD`
        - **Untracked threshold-exceeding**: of the above, count of lines whose 3rd column is `untracked`
     4. Display the table:

     | Metric | Value | Threshold | Status |
     |--------|-------|-----------|--------|
     | Recovery group-keys (total) | N | — | — |
     | Threshold-exceeding group-keys | N | > 0 | OK / NOTIFY |
     | Untracked threshold-exceeding | N | > 0 | OK / WARNING |

     5. List each threshold-exceeding group-key (if any) with its group-key, count, and tracked:#N / untracked status.

     This section is read-only display only — no comment posting or Issue creation (unlike Section 8/9's Retire-Proposal Comment Posting, which stays scoped to phase/verify and Icebox only; see Notes).
     ```
   - `### Step 4: Save` の一文「When `--retention` is specified, the Sections 8 and 9 retention output is included in the saved file.」を「the Sections 8, 9, and 10 retention output」に更新する

2. `scripts/collect-recovery-candidates.sh` に entry 単位の `N/A` 除外を追加する (→ Pre-merge AC 4, 5):
   - `起票済み` 検出のための配列群 (`ENTRY_TS` / `ENTRY_KEY` / `ENTRY_FILED`) と並べて `ENTRY_NA=()` を宣言する
   - `CURRENT_FILED` と並ぶ per-entry state として `CURRENT_NA=0` を宣言し、新しい H2 ヘッダ検出時のリセット処理 (`CURRENT_CAUSE=""` / `CURRENT_FILED=""` の並び) に `CURRENT_NA=0` を追加する
   - `- 起票済み #[0-9]+` 検出の `if` ブロックの隣に、以下を追加する:
     ```bash
     if echo "$line" | grep -qE '^\- N/A'; then
       CURRENT_NA=1
     fi
     ```
     (`N/A` の後続文言は固定しない — 実データに `N/A (resolved by known catalog)` と `N/A (resolved by known catalog: silent-no-op pattern with auto-retry)` の 2 種の表記揺れが存在するため、`^\- N/A` の前方一致とする)
   - `_flush_entry()` で `ENTRY_NA+=("$CURRENT_NA")` を追加する
   - group-key ごとの集計ループ (`cutoff` モードと `count_all` モード) で、`ENTRY_NA[$i]` が `1` のエントリをカウント対象から除外する条件を追加する (`exclude_all` モードは元々 count=0 のため変更不要)
   - ファイル冒頭のコメントブロックに、既存の Issue #1152 (起票済み entry 単位除外) の説明と並べて、本除外の説明を追記する

3. `tests/collect-recovery-candidates.bats` に `@test` を 2 件追加する (→ Pre-merge AC 5):
   - 全エントリが `N/A` (上記 2 種の表記揺れを両方含む) の group-key が `--threshold 1` でも一切出力されないことを検証
   - `N/A` エントリと通常エントリが混在する group-key で、通常エントリのみがカウントされることを検証 (count が `N/A` 分だけ減ることを確認)

4. `tests/audit-retention.bats` が無変更のまま PASS することを確認する (→ Pre-merge AC 6)。同ファイルは `scripts/compute-escalation-level.sh` のみを対象としており、本 Issue はこのスクリプトを変更しない。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/audit/SKILL.md の --retention Option セクションに、recovery 候補頻度を表示する新しい Section が追加されている。collect-recovery-candidates.sh の出力を集計し、recoveries-auto-fire.threshold を超えた group-key を列挙する旨が記述されている" --> recovery 候補頻度のセクションが追加されている
- <!-- verify: rubric "追加されたセクションが既存の Section 8 (phase/verify Retention Metrics) / Section 9 (Icebox Retention Metrics) と同じ形式 (Metric / Value / Threshold / Status の表 + 閾値超過項目の列挙) に従っている" --> 既存セクションと同じ形式に従っている
- <!-- verify: rubric "閾値超過の group-key について、対応する open Issue の有無が判別できる形で表示される旨が記述されている (既に追跡中のものと未追跡のものを区別できること)" --> 追跡中 / 未追跡が区別できる
- <!-- verify: rubric "追加された Section 10 の手順が、N/A (resolved by known catalog) エントリのみで構成される group-key を『対応不要』として候補集計・Untracked 閾値超過の対象から除外する旨に言及している" --> N/A のみの group-key が誤って Untracked 警告に計上されないことが記述されている
- <!-- verify: command "bats tests/collect-recovery-candidates.bats" --> `N/A (resolved by known catalog)` のみで構成される group-key が候補集計から除外されることを検証するテストケースを含め、`tests/collect-recovery-candidates.bats` が PASS する
- <!-- verify: command "bats tests/audit-retention.bats" --> `tests/audit-retention.bats` が PASS する

### Post-merge

- `/audit stats --retention` を実行し、recovery 候補頻度セクションが出力され、閾値超過の group-key が列挙されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **Blocked-by は解消済み**: #1152 (2026-08-06 closed) / #1098 (それ以前に closed) ともに CLOSED であることを Step 4 の blocked-by 検出 (`gh-check-blocking.sh --dry-run` exit code 0) で確認した。実装のブロッカーはない。
- **Section 10 の挿入位置**: Section 9 の閾値超過列挙文の直後、`#### Retire-Proposal Comment Posting` の直前とした。Section 8/9/10 の「表示のみ」の 3 セクションをまとめて配置し、verify/Icebox に限定されたエスカレーションベースのコメント投稿ロジック (Retire-Proposal Comment Posting) は変更しない。Issue の Purpose が「起票を復活させるわけではない」と明言しているため、Section 10 に同様のコメント投稿・Issue 起票の仕組みは追加しない。
- **`N/A` 検出の正規表現**: `^\- N/A` という前方一致のみとし、後続文言は固定しない。理由は、実データ (`docs/reports/orchestration-recoveries.md`) に `N/A (resolved by known catalog)` (`apply-fallback.sh` の `write_recovery_entry()` が書き込む現行の固定文言) と `N/A (resolved by known catalog: silent-no-op pattern with auto-retry)` (トレイリング文言が異なる過去のエントリ) の 2 種が既に存在することを確認済みで、Issue 本文も「または同義の N/A 系文言」を許容しているため。
- **他 Spec の記述との食い違い確認**: `docs/spec/issue-1185-triaged-issue-ac-audit-gap.md` (別 Issue の使い捨て Spec) に「#1181 により Tier 2 recovery の記録経路が失われ、`collect-recovery-candidates.sh` の閾値判定に Tier 2 が載らない」という記述がある。しかし現行の `scripts/apply-fallback.sh` を直接確認したところ、Tier 2 用の `write_recovery_entry()` (本 Issue が対象とする `N/A (resolved by known catalog)` を書き込む関数) は健在で、`dco-signoff-missing-autofix` / `code-patch-silent-no-op` / `json-mode-silent-hang` の各ハンドラから呼び出されている。上記の記述は古いか、`run-auto-sub.sh` 自身のインライン書き込み経路 (manual / wrapper-retry / Tier 3 のみ) に限定した指摘である可能性が高い。本 Issue のスコープでは追加調査しないが、次の読者向けに記録しておく。

## Code Retrospective

### Deviations from Design
- Implementation Steps に明示されていなかった追加修正として、`skills/audit/SKILL.md` の frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/collect-recovery-candidates.sh:*` を追加した。Section 10 が本文中で同スクリプトを新規参照するため、`scripts/check-allowed-tools.sh skills/` の pre-commit check がこの欠落を検出した。allowed-tools の同期は SKILL.md 本文変更に伴う機械的な追従であり、設計判断の変更ではない。

### Design Gaps/Ambiguities
- N/A。Spec の Notes に記録済みの `N/A` 検出正規表現・Section 10 挿入位置・他 Spec との食い違いの3点で実装上の曖昧さは解消済みだった。

### Rework
- N/A。Implementation Steps の4ステップ (SKILL.md 変更、collect-recovery-candidates.sh 変更、bats テスト追加、既存テスト無変更確認) はいずれも Spec の記述通り一度で実装が完了し、手戻りは発生しなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC 6 件は `check-pre-merge-ac.sh` により全件チェック済みと確認し、AskUserQuestion なしで squash merge を実行した (`--non-interactive` 経路)
- `reconcile-phase-state.sh review --check-completion` で `review_incomplete_fallback` が立っていないことを確認し、review フェーズの完了が fallback 経由ではなく organic Step 14 完了であることを検証した
- `gh-pr-merge-status.sh` の結果が `mergeable=true, reason=clean` だったため、conflict 解消 (Step 3) をスキップして直接 squash merge に進んだ

### Deferred Items
- Post-merge AC (`/audit stats --retention` の実観察、`verify-type: observation event=auto-run session=next`) は未実行 — 次回 `/auto` 実行時に自動発火する設計のため、merge フェーズでも引き続きスコープ外
- CONSIDER 指摘 (`collect-recovery-candidates.sh:213` の N/A 判定スコープ限定) は review フェーズで見送り済み、merge フェーズでの新規判断なし

### Notes for Next Phase
- `verify` フェーズは Post-merge AC の observation 項目 (`/audit stats --retention` の実行結果確認) を次回 `/auto` 実行時に確認すること
- Issue #1191 の label transition (`phase/verify`) と Issue close は本フェーズの Step 5/6 で処理済み

## review retrospective

### Spec vs. implementation divergence patterns
特筆事項なし。`review-light` の Spec 乖離観点では問題は検出されず、Implementation Steps がほぼ逐語的に実装されていることを確認した。

### Recurring issues
特筆事項なし。今回検出した 2 件 (SHOULD 1 件、CONSIDER 1 件) はいずれも本 Issue 固有の指摘であり、過去の review フェーズで繰り返し検出されているパターンとの一致は確認できなかった。

補足として、CONSIDER 指摘 (`collect-recovery-candidates.sh` の N/A 判定が `### Improvement Candidate` サブセクションにスコープされていない) は、同スクリプトの既存実装 (`起票済み #N`/`cause:` 判定) がもともと同じ非スコープ設計であることに起因する。新規に導入された弱点ではなく、コードベースの既存方針を踏襲した結果である点を記録しておく。

### Acceptance criteria verification difficulty
特筆事項なし。Pre-merge AC 6 件 (rubric 4 件 + bats command 2 件) はいずれも UNCERTAIN を経由せず確定的に判定できた — rubric 4 件は SKILL.md Section 10 の実記述と Issue AC 文言の突き合わせで PASS、bats command 2 件は CI `Run bats tests` ジョブ成功への fallback で PASS。verify command の記述・rubric 文言の精度に起因する追加調査は不要だった。

### Improvement proposal candidates (aggregated at /verify)
- Steering Doc sync candidate の抽出漏れ: 本 PR は `docs/structure.md`/`docs/tech.md` (+ `docs/ja/` 対訳) を正しく同期したが、同じ Steering Document である `docs/product.md` は候補から漏れていた。`/audit` サブコマンドの出力仕様が変わる Issue で、Steering Doc 同期チェックの対象に `docs/product.md` の用語集エントリを明示的に含める運用上の見直し余地がある。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- `/issue 1191` が着手前コメントを読み、**#1098 が書き込む `N/A (resolved by known catalog)` エントリを現行の `collect-recovery-candidates.sh` が除外できず、本 Issue が追加する Section 10 が着手直後から誤検知で埋まる**というリスクを捕捉した。さらに「#1152 の PR レビュー時に拾う」という当初の想定に対し、#1152 が既に CLOSED でその差分を含んでいないことをソースで確認し、除外規則の追加を本 Issue のスコープへ取り込んで Pre-merge AC を 2 件追加した。同一バッチ内で先行 Issue の着地内容を検証してスコープを補正した事例
- 機械チェック 3 種 (checkbox format / observation `session=next` / AC 監査) がすべて通過。これは同バッチの #1156 (形式強制) と #1185 (監査経路) の実装が両方稼働していることの傍証にもなっている

#### spec

- Notes に「`N/A` 検出正規表現」「Section 10 の挿入位置」「他 Spec との食い違い」の 3 点を事前解決として記録しており、code フェーズで Design Gaps がゼロだった

#### code

- Implementation Steps に明示されていなかった `allowed-tools` への `collect-recovery-candidates.sh` 追加が必要になり、`scripts/check-allowed-tools.sh` の pre-commit check がこれを検出した。SKILL.md 本文が新規スクリプトを参照する際の機械的追従であり、設計判断の変更ではない。**Spec に書かれていない追従項目を機械チェックが拾った**good case

#### review

- SHOULD 1 件 + CONSIDER 1 件。CONSIDER (`N/A` 判定が `### Improvement Candidate` サブセクションにスコープされていない) について、**同スクリプトの既存判定 (`起票済み #N` / `cause:`) がもともと同じ非スコープ設計**であることを確認し「新規の弱点ではなくコードベースの既存方針の踏襲」と記録した上で見送っている。既存方針との整合を根拠に見送り判断をした点が明快

#### merge

- Pre-merge AC 6 件全チェック済みで gate 通過。`review_incomplete_fallback` が立っていないことも確認し、review 完了が fallback 経由でなく organic であることを検証している

#### verify

- Section 10 の中核コマンド (`collect-recovery-candidates.sh --threshold 1 --with-tracking`) を実行し、**20 件の group-key が `<group-key>\t<count>\t<tracked:#N|untracked>` 形式で列挙**されることを確認。閾値 3 超過は `manual-recovery-respawn` (21, tracked:#1014) と `code-pr-tier3-recovery` (6, tracked:#799) の 2 件。本 Issue の Purpose (#1179 が閉じた自動起票の穴を可視化で埋める) が達成されている
- `/audit stats --retention` の全体実行は行っていない。Section 10 の手順が上記コマンド 1 本とその集計・表示であることを SKILL.md L504-508 で確認した上で、コマンド出力が期待形式で得られることを直接検証して PASS とした (この限定は Issue コメントにも明記)
- **可視化によって初めて見えた低頻度 untracked group-key**: `manual-recovery-merge-rerun/pre-merge-ac-command-unverifiable` (2)、`manual-recovery-commit-push` (2)、`manual-recovery-push-only` / `push-and-pr` / `respawn-skip-code` (各 2) など。1 件目は 2026-08-06 の `/auto --batch 1179 1181 1180` で #1181 / #1180 が pre-merge AC gate にブロックされた事象に対応すると見られる。閾値未満のため Recommend には出ないが Section 10 では継続的に見える
- **本バッチ全体の連鎖が閉じた**: #1179 (自動起票の opt-out) → #1191 (可視化で穴を埋める) → #1098 (Tier 2 の永続記録を復元して母数を正す) → #1152 (誤検知と再発見落としを解消して精度を上げる)。4 Issue が 1 つの観測系を成立させており、Section 10 の出力はその 4 件すべての成果が反映された状態になっている

### Improvement Proposals

- **Section 10 の `tracked:#N` が対応 Issue の open/closed を区別しない**: `manual-recovery-respawn` は `tracked:#1014` と表示されるが #1014 は CLOSED (2026-07-13) であり、実態は「対応済みの Issue が close された後に 21 件再発している」状態。#1152 の entry 単位判定により**検出**はできるようになったが、**表示**は tracked/untracked の 2 値のままで「tracked だが再発中」が読み取れない。count の大きさで気づける範囲ではあるものの、`--with-tracking` の出力に対応 Issue の state を含めるか、Section 10 側で `tracked:#N (closed)` と表示すれば「解決済みのはずが再発している」group-key が一目で分かる。変更対象は `scripts/collect-recovery-candidates.sh` と `skills/audit/SKILL.md` の 2 ファイルで、同スクリプトは `/verify` Step 15 と `/audit` Section 10 の 2 経路から使われる共有サーフェス
- **Steering Doc sync candidate の抽出漏れ (review フェーズからの集約)**: 本 PR は `docs/structure.md` / `docs/tech.md` (+ `docs/ja/` 対訳) を同期したが、同じ Steering Document である `docs/product.md` は候補から漏れていた。`/audit` サブコマンドの出力仕様が変わる Issue では `docs/product.md` の用語集エントリも同期候補に含める余地がある
