# Issue #1058: code: Spec ファイルの編集先を一貫させ並行編集コンフリクトを防ぐ

## Overview

Spec ファイル (`docs/spec/issue-N-*.md`) への追記先が、実行主体によって base ブランチと PR ブランチに分かれている。結果として同一ファイルが両側で並行編集され、merge 時にコンフリクトする (#1186 / #1163 / downstream 1 件で実測)。

書き込み先が分岐する正確な位置は 2 経路ある。本 Issue は **経路 (a)** を扱う。

| 経路 | 内容 | 扱い |
|---|---|---|
| (a) bash wrapper の post-processor | `scripts/run-code.sh:367-374` / `scripts/run-spec.sh:202-209` が `_append_consumed_comments_section()` を `claude` subprocess の **exit 後** に呼ぶ。その時点の CWD は worktree ではなく main repository のため、`append-consumed-comments-section.sh` は main の Spec を編集し `git push origin HEAD` で base へ直接 push する | **本 Issue** |
| (b) SKILL.md のステップ順序 | `skills/code/SKILL.md` の Comment Consumption が Step 1、Worktree Entry が Step 2 の順で、LLM が worktree 作成前に main の Spec を Edit する | #1078 (別 Issue) |

`/code` の **pr route** では LLM 側の Spec 追記 (Code Retrospective) が PR ブランチに載るのに対し、(a) の post-processor は main に載るため、同一ファイルが 2 ブランチに分岐する。これがコンフリクトの構造的原因である。

さらに副次的な欠陥として、pr route では post-processor の発火判定 (`_POST_COUNT <= _PRE_COUNT`) が **main の Spec ファイルを見ている**ため worktree 側の追記を観測できず、LLM が正しく書いた場合でも常に fallback が発火する。#1186 の `aa416dfe Add consumed comments fallback ...` はこの誤発火である。

## Changed Files

- `scripts/append-consumed-comments-section.sh`: `--no-push` フラグ追加 (フラグ指定時は commit のみ行い push しない)。main tree で実行された場合の `git push origin HEAD` を `worktree-merge-push.sh --base "$(git rev-parse --abbrev-ref HEAD)"` によるロック付き push に置換 — bash 3.2+ 互換 (`mapfile` 等の bash 4+ 構文を導入しない)
- `scripts/run-code.sh`: post-processor fallback ブロック (L367-374) を `ROUTE_FLAG != "--pr"` の場合のみ実行するようゲート。pr route では Spec の書き込み先が PR ブランチであり main repository からは観測も安全な書き込みもできないため — bash 3.2+ 互換
- `skills/code/SKILL.md`: Step 12 の `git add` 直前に `append-consumed-comments-section.sh $NUMBER code --no-push` の必須 bash 呼び出しを追加。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` を追加 (現在は未登録)
- `skills/spec/SKILL.md`: Step 13 の `git add` 直前に `append-consumed-comments-section.sh $NUMBER spec --no-push` の必須 bash 呼び出しを追加。frontmatter `allowed-tools` に同エントリを追加 (現在は未登録)
- `modules/worktree-lifecycle.md`: Notes に「Spec file write destination」節を新設 — 「Spec ファイルはフェーズ自身の作業ブランチ (worktree ブランチ / PR ブランチ) 上でのみ編集し、base へは既存の Exit 経路 (`worktree-merge-push.sh` または PR merge) 経由でのみ反映する」という規約を明文化する。`## Consumed Comments` との相互作用にも言及する
- `modules/l0-surfaces.md`: L248-255 の「Bash wrapper fallback (Issue #811)」の 2 bullet を、新しい配置 (`/spec` `/code` `/verify` いずれも in-session mandatory call、wrapper post-processor は非 pr route のみ) に合わせて書き換え
- `tests/append-consumed-comments-section.bats`: `--no-push` 指定時に push されないこと、main tree 実行時に `worktree-merge-push.sh` が呼ばれることを検証するテストを追加。`setup()` の `$MOCK_DIR` に `worktree-merge-push.sh` のモックを追加する (`WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` が設定済みのため必須)
- `tests/run-code.bats`: pr route で `_append_consumed_comments_section` が呼ばれないことを検証するテストを追加 (既存の L511 "fallback: no consumed comments section before and after claude → _append_consumed_comments_section called" と同じモック構造を流用)
- `docs/structure.md`: L172 の `scripts/append-consumed-comments-section.sh` の説明文を新しい呼び出し構成に更新 [Steering Docs sync candidate]
- `docs/ja/structure.md`: L165 の同じ行を日本語ミラーとして同期 (`docs/translation-workflow.md` の Sync Procedure に従う) [Steering Docs sync candidate]

## Implementation Steps

1. `scripts/append-consumed-comments-section.sh` に `--no-push` フラグを追加し、main tree 判定 (既存の `_git_dir == _git_common_dir` チェック) が真のときの push を `worktree-merge-push.sh --base "$(git -C "$_repo_root" rev-parse --abbrev-ref HEAD)"` に置き換える。失敗時は既存同様 best-effort 警告のみ (→ acceptance criteria 2)
2. `scripts/run-code.sh` の post-processor fallback ブロックの条件を `if [[ $EXIT_CODE -eq 0 && "$ROUTE_FLAG" != "--pr" ]]; then` に変更し、pr route では wrapper が Spec を編集しないようにする。スキップ理由を同ブロックのコメントに記載する (→ acceptance criteria 2)
3. `skills/code/SKILL.md` Step 12 の Steps 6 (`git add $SPEC_PATH/issue-$NUMBER-*.md` を含む commit ブロック) の直前に、`bash ${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh $NUMBER code --no-push` の必須呼び出しを追加する。あわせて frontmatter の `allowed-tools` に該当エントリを追加する (after 1) (→ acceptance criteria 2)
4. `skills/spec/SKILL.md` Step 13 の Steps 5 (Phase Handoff write) の直後・Steps 6 (commit) の直前に、`bash ${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh $NUMBER spec --no-push` の必須呼び出しを追加する。あわせて frontmatter の `allowed-tools` に該当エントリを追加する (after 1, parallel with 3) (→ acceptance criteria 2)
5. `modules/worktree-lifecycle.md` の `## Notes` に「Spec file write destination」節 (見出しレベル `###`) を追加し、Spec ファイルの書き込み先規約とフェーズ別の base 反映経路 (`/spec`・`/code` patch/operate・`/verify` は `worktree-merge-push.sh`、`/code` pr は PR merge) を表で明文化する。表には `**(exhaustive)**` マーカーを付す (`modules/skill-dev-checks.md` "Exhaustive/Example Markers") (→ acceptance criteria 1)
6. `modules/l0-surfaces.md` の「Bash wrapper fallback (Issue #811)」節を、新しい 2 層構成 (in-session mandatory call が第一の安全網、wrapper post-processor は非 pr route の第二の安全網) に書き換え、Step 5 で追加した `worktree-lifecycle.md` の節を参照させる (after 5) (→ acceptance criteria 1)
7. `tests/append-consumed-comments-section.bats` の `setup()` に `worktree-merge-push.sh` モックを追加し、`--no-push` 指定時に push されないテストと main tree 実行時に `worktree-merge-push.sh` が呼ばれるテストを追加する (after 1)
8. `tests/run-code.bats` に pr route で `_append_consumed_comments_section` が呼ばれないことを検証するテストを追加する (after 2)
9. `docs/structure.md` と `docs/ja/structure.md` の `append-consumed-comments-section.sh` 説明行を新しい呼び出し構成に更新する (after 1, 2, 3, 4)

## Verification

### Pre-merge

- <!-- verify: rubric "Spec ファイルへの追記先 (base ブランチ / PR ブランチ) が全フェーズで一貫するよう設計が明文化されている" --> `modules/worktree-lifecycle.md` の新設節と `modules/l0-surfaces.md` の書き換えにより、Spec ファイルの書き込み先規約が全フェーズ横断で明文化されている
- <!-- verify: rubric "append-consumed-comments-section.sh と code フェーズの retrospective 追記が同一ブランチを対象とするようになっている" --> `skills/code/SKILL.md` Step 12 の in-session 呼び出しと `scripts/run-code.sh` の pr route ゲートにより、両者が worktree ブランチ (= PR ブランチ) を対象とする

### Post-merge

- pr route の Issue を 1 件通しで実行し、Spec ファイルのコンフリクトが発生しないことを確認する

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` — `skills/code/SKILL.md` と `skills/spec/SKILL.md` の `allowed-tools` に追加が必要 (両者とも現在未登録。`skills/verify/SKILL.md` には登録済み)

### Built-in Tools

- なし (既存の `Read` / `Edit` / `Write` で足りる)

### MCP Tools

- なし

## Notes

### 新設する分岐の挙動全列挙 (`skills/spec/skill-dev-constraints.md` #642)

**`scripts/append-consumed-comments-section.sh` の push 分岐 (exhaustive):**

| 分岐条件 | 挙動 | 終了コード |
|---|---|---|
| `--no-push` 指定あり | commit まで実行し push をスキップ。スキップした旨を stderr に出力しない (通常経路のため) | 0 |
| `--no-push` なし かつ worktree 内 (`_git_dir != _git_common_dir`) | 従来どおり `git -C "$_repo_root" push origin HEAD` | 0 (push 失敗時も best-effort 警告のみで 0) |
| `--no-push` なし かつ main tree (`_git_dir == _git_common_dir`) | 既存の defense-in-depth 警告を stderr に出力したうえで、`worktree-merge-push.sh --base "$(git -C "$_repo_root" rev-parse --abbrev-ref HEAD)"` を実行 | 0 (`worktree-merge-push.sh` が非 0 で終了しても best-effort 警告のみで 0) |
| Spec ファイルに差分なし (`git diff --quiet` が真) | commit も push も実行しない | 0 |

スクリプト全体の best-effort 契約 (常に exit 0) は既存どおり維持し、呼び出し側をブロックしない。

**`scripts/run-code.sh` の post-processor 分岐 (exhaustive):**

| 分岐条件 | 挙動 |
|---|---|
| `EXIT_CODE != 0` | 従来どおり post-processor をスキップ |
| `EXIT_CODE == 0` かつ `ROUTE_FLAG == "--pr"` | **新規**: post-processor をスキップ。Spec の書き込み先は PR ブランチであり main repository からは観測も安全な書き込みもできないため。安全網は `skills/code/SKILL.md` Step 12 の in-session 呼び出しが担う |
| `EXIT_CODE == 0` かつ `ROUTE_FLAG != "--pr"` (patch / operate / 未指定) | 従来どおり pre/post カウント比較を行い、増えていなければ `_append_consumed_comments_section` を実行 |

### `validate-skill-syntax.py` の制約

`skills/code/SKILL.md` / `skills/spec/SKILL.md` への追記は bash コードフェンス内に閉じ、本文プロース中に半角感嘆符・3 連バッククォート・小数点付き Step 番号を導入しない。`allowed-tools` に追加するのは `Bash(...)` 内のパターンのみで新規ベースツール名を導入しないため、`scripts/validate-skill-syntax.py` の `KNOWN_TOOLS` (L19-26) の更新は不要。`.claude/settings.json.template` も `Bash(${WHOLEWORK_ROOT}/scripts/*.sh *)` のワイルドカードで既にカバーされているため変更不要。

### 案 A / 案 B の評価 (Issue コメント issuecomment-5201930509 の指示に対する回答)

**採用: 案 B (Spec は常にフェーズの作業ブランチ)**。ただし「PR ブランチ」を「フェーズ自身の worktree ブランチ」へ一般化し、base へは既存の Exit 経路経由でのみ反映する形とする。

**評価軸 1 — 並行セッション耐性:**

案 A (Spec は常に base) は「並行セッションが base に commit/push する」ことを設計として正当化するため、コメントで実測された 3 事象 (ff-only merge 失敗 → rebase fallback がセッション全体で 4 回以上、進行中セッションの dirty による `git pull --ff-only` 失敗、`check-verify-dirty.sh` exit 2) の頻度をいずれも押し上げる。加えて案 A を `/code` pr route に適用すると、worktree ブランチにコミットする実装差分とは別に Spec だけを base へ運ぶ第 2 の経路が必要になり、**pr route の全実行が新たに base への push を 1 回追加する**。並行耐性の観点では案 A は明確に劣る。

案 B では base への書き込みが `worktree-merge-push.sh` (patch lock + fetch-after-lock + push retry + #1076 の rebase fallback) に一本化される。これは `/verify` が Issue #1037 で既に到達した結論と同一であり、`skills/verify/SKILL.md` L130 に「Step 3 (Worktree Entry) をスキップすると `append-consumed-comments-section.sh` が worktree 外のブランチへ直接 commit/push し、`worktree-merge-push.sh` のロック機構をバイパスして race のリスクがある」と明記されている。本 Issue はこの既存規約を `/spec` と `/code` にも適用するもので、新規の設計判断ではなく**既存パターンへの整合**である。

**評価軸 2 — patch route での案 B の実現コスト:**

triage は案 B を「patch route (PR なし) との整合を新たに設計する必要があり変更範囲が広い」として退けたが、実測すると**追加設計はほぼ不要**だった。patch route は既に worktree で作業し `worktree-merge-push.sh` で base へ merge する構造を持つため (`skills/code/SKILL.md` Step 14 "patch route (merge-to-main pattern)")、Spec 追記も同じ経路にそのまま載る。本 Spec の patch route 向け変更は Step 3 の in-session 呼び出し 1 行のみで、`worktree-merge-push.sh` 側の変更は不要。

**triage が挙げた案 A の論拠に対する応答:**

- 「`/spec` は既に base へ直接コミットしている」— 正確には `ENTERED_WORKTREE=false` のときのみ直接 push であり、`ENTERED_WORKTREE=true` (`run-spec.sh` 経由の通常経路) では `worktree-merge-push.sh --from` を通す。つまり `/spec` の主経路は既に案 B 側である
- 「変更対象が `/code` 側の 1 経路に閉じる」— 案 B も変更対象は同じ 1 経路 (wrapper post-processor) に閉じており、変更ファイル数の差はない
- 「案 C は根治しない」— 同意。案 C は不採用

### 棚卸しスコープの判断 (Issue Related セクションの未確定事項に対する回答)

**別 Issue へ切り出す。本 Issue には含めない。**

- 本 Issue の AC 2 件はいずれも「Spec ファイルの書き込み先」に限定されており、全 skill / script 横断の監査は AC が要求する範囲を超える
- 監査は「調査 → 発見ごとに個別の修正」という発散型の作業で、発見のそれぞれが独立した Issue になる性質を持つ。本 Issue の pr route ゲートと in-session 呼び出しの着地を待たずに並行させると、監査結果と本 Issue の変更が衝突する
- 監査の**方針**にあたる部分 (Spec ファイルの書き込み先規約) は本 Issue の AC1 で `modules/worktree-lifecycle.md` に明文化されるため、切り出し先の Issue はその規約を前提に**掃き出し**だけを行えばよい

切り出し先の Issue を起票する際は以下を前提として引き継ぐこと:
- #1078 (`/code` Step 1 の Consumed Comments 追記が worktree fresh 作成時に失われうる) と重複しないこと。#1078 は同じ症状の別経路 (SKILL.md のステップ順序) を扱う
- 本 Issue が扱う wrapper post-processor 経路も既に処理済みとして除外すること
- 監査起点リストは issuecomment-5200989170 に記載済み (Worktree Entry より前のファイル書き込み / subprocess exit 後の後処理 / repo root を解決する 8 スクリプト / 意図的に main へ書く箇所)

起票そのものは本 Spec の実装範囲外とし、`/verify` の Improvement Proposal 集約 (`modules/retro-proposals.md`) に委ねる。

### pr route の wrapper fallback を「無効化」とした理由 (自動解決)

pr route で書き込み先を揃える手段は 2 つある。

| 案 | 内容 | 判定 |
|---|---|---|
| 無効化 (採用) | wrapper post-processor を pr route ではスキップし、安全網を `skills/code/SKILL.md` Step 12 の in-session mandatory call に一本化する | 採用 |
| PR ブランチへ書き込む | wrapper が `git fetch origin <pr-branch>` → 一時 worktree 作成 → 追記・commit → `git push origin HEAD:refs/heads/<pr-branch>` を行う | 不採用 |

不採用の理由: (1) main repository 側から他ブランチへ書き戻す新しい経路を増やすことになり、本 Issue が解消しようとしている「書き込み先の分散」を別の形で再導入する、(2) 一時 worktree の作成・削除は並行セッション下で `git worktree` の競合を新たに生む、(3) `/verify` が Issue #1037 で確立した in-session パターンで同じ保証が得られる。

なお pr route の wrapper fallback は現状ほぼ常に誤発火しており (Overview 末尾参照)、無効化による安全網の実質的な損失はない。

### AC を rubric のまま維持した理由

`modules/verify-patterns.md` §9 は rubric に決定的な `file_contains` を併記することを推奨するが、Issue コメント (issuecomment-5201930509) が「結果指向の rubric AC は変更不要」と明示しているため、Pre-merge AC 2 件は Issue 本文からそのまま転記し、決定的 verify command の追加は行わない。Spec 側の Verification 項目本文で対象ファイルを具体的に示すことで、`/review` / `/verify` 時の判定材料を補っている。

### `origin/worktree-*` ブランチの残留 (`--no-push` を導入する理由)

`append-consumed-comments-section.sh` は現在 worktree 内で実行されると `git push origin HEAD` により worktree ブランチを origin へ push する。本リポジトリ (`saitoco/wholework`) の `git branch -r` 実測 (2026-08-06 時点、リモートブランチ計 60 本) では、この経路により `origin/worktree-verify+issue-*` が 16 本残留していた。`/spec` と `/code` patch route にも同じパターンを無条件に適用すると Issue 1 件あたり最大 2 本の残留ブランチが追加されるため、新規呼び出し箇所には `--no-push` を指定する。

`--no-push` でも base への反映は損なわれない: `/code` pr route は Step 12 で直後に `git push origin HEAD` を実行し、`/code` patch/operate route と `/spec` は Step 14 の `worktree-merge-push.sh` で base へ merge される。

既存の `skills/verify/SKILL.md` L153 の呼び出しは本 Issue では変更しない (`/verify` の挙動変更は AC の要求範囲外)。`/verify` 側の残留ブランチ解消は独立した改善候補として spec retrospective に記録する。

### base ブランチ非 `main` 時の扱い

`worktree-merge-push.sh` の `--base` 既定値は `main` だが、`run-code.sh` は `--base` フラグをサポートする。main tree での実行時は HEAD が base ブランチそのものであるため、`--base "$(git -C "$_repo_root" rev-parse --abbrev-ref HEAD)"` を渡すことで非 `main` base でも正しく動作する。`append-consumed-comments-section.sh` に新たな `--base` フラグを追加する必要はない。

### Issue 本文との整合

Issue 本文 Related の「`scripts/append-consumed-comments-section.sh` (base ブランチへ書き込み)」は、スクリプト自体は `git rev-parse --show-toplevel` で CWD からリポジトリルートを解決する worktree 対応済み実装 (L21) であり、base へ書くのは呼び出し位置の帰結である。この訂正は 2026-08-06 のコメントと Issue 本文 Background に既に反映されており、未解決のコンフリクトはない。

### bats テストの前提

- `tests/append-consumed-comments-section.bats` は `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定済みのため、`append-consumed-comments-section.sh` が新たに呼び出す `worktree-merge-push.sh` は `$MOCK_DIR` にモックを置かないと解決できない。Step 7 でモック追加を必須とする
- `$MOCK_DIR/git` モックは `rev-parse --git-dir` / `rev-parse --git-common-dir` に異なる値を返して「worktree 内」を模擬している (L47-54)。main tree 経路のテストでは両者が同値を返すようモックを分岐させる必要がある
- `tests/run-code.bats` は `_append_consumed_comments_section() { echo "CALLED \$*" >> "${FALLBACK_LOG}"; }` でスタブ化する既存パターン (L511-) を持つため、pr route での非呼び出しは同じログファイルが空であることで検証できる

## Consumed Comments

- saito / MEMBER / first-class / `## Issue Retrospective` — `/issue` の自動解決ログ (案 A 推奨、post-merge verify-type を observation へ変更) / https://github.com/saitoco/wholework/issues/1058#issuecomment-5201478146
- saito / MEMBER / first-class / `## /spec への申し送り: 案 A / 案 B を並行耐性の軸で再評価すること` — 並行セッション耐性と patch route コストの 2 軸追加、棚卸しスコープの判断依頼 / https://github.com/saitoco/wholework/issues/1058#issuecomment-5201930509

cutoff: 2026-08-06T07:00:47Z (`phase/issue` ラベル付与時刻)。cutoff 以前の issuecomment-5200989170 (2026-08-06T06:04:28Z) は Issue 本文 Background に既に反映済みのため、本フェーズの前提として参照した。
