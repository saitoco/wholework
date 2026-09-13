# Issue #1468: verify: stale skill body 検出が行数不変の変更を取りこぼす (内容ハッシュ併用)

## Overview

`/verify` Step 1 の stale skill body 検出 (#1447 で導入) は、`skills/verify/SKILL.md` 本文に埋め込まれた `<!-- skill-body-lines: N -->` マーカーの値と `wc -l` の実測値を比較する**行数のみ**の軽量チェックである。2026-09-13、#1461 の `/verify` 実行で実際に取りこぼしが発生した: `scripts/emit-verify-event.sh` を `scripts/emit-skill-event.sh` にリネームする置換 (SKILL.md 内 15 箇所) は行数を変えないため、マーカー値とディスク上の実測値が一致し `STALE_SKILL_BODY_DETECTED=false` と誤判定され、会話セッションにキャッシュされていた旧本文が実行されて最初の emit 呼び出しが `No such file or directory` (exit 127) で失敗した。

本 Issue は、行数マーカーと並べて内容ハッシュ (`<!-- skill-body-sha: H -->`) マーカーを追加し、Step 1 の自己整合チェックに行数比較とハッシュ比較の両方を組み込むことで、リネーム・語句置換・同行数の書き換えなど行数不変の編集に対しても stale 検出を可能にする。対象は `skill-body-lines` マーカーを持つ唯一のファイルである `skills/verify/SKILL.md` に限定される (`/issue` 時点の `grep -rl "skill-body-lines" skills/ modules/ scripts/` 調査で確認済み、Issue Retrospective コメントで再確認済み)。

## Reproduction Steps

1. `/verify` セッションが `skills/verify/SKILL.md` を会話コンテキストにキャッシュした状態で開始する (キャッシュ時点の行数マーカー: `<!-- skill-body-lines: 996 -->`)。
2. 同一会話セッション中に、別 Issue の `/code` フェーズが `skills/verify/SKILL.md` 内のスクリプト参照名をリネームする置換を行い、`main` にマージされる (例: `scripts/emit-verify-event.sh` → `scripts/emit-skill-event.sh`、15 箇所)。置換は行数を変えない。
3. 同一会話セッション内で `/verify` の Step 1 自己整合チェックを実行すると、キャッシュされた行数 (996) とディスク上の実測行数 (996) が一致するため `STALE_SKILL_BODY_DETECTED=false` と誤判定される。
4. キャッシュされた本文中の旧スクリプト名を使った最初の emit 呼び出しが `bash: scripts/emit-verify-event.sh: No such file or directory` (exit 127) で失敗する。

## Root Cause

`/verify` Step 1 の stale skill body 検出が、`<!-- skill-body-lines: N -->` マーカーの値と `wc -l` の実測値という**行数のみ**を比較する設計になっているため。行数が変わらない編集 (リネーム、語句置換、同行数の書き換え) は行数比較では原理的に検出不可能であり、内容そのものの変化を捉える指標 (コンテンツハッシュ) が併用されていなかったことが直接の原因。

## Changed Files

- `skills/verify/SKILL.md`:
  - `<!-- skill-body-lines: N -->` マーカーの直後に `<!-- skill-body-sha: H -->` マーカー (内容ハッシュの先頭 8 文字) を追加
  - Step 1 の自己整合チェックを拡張し、行数比較に加えて内容ハッシュ比較を行う (いずれかの不一致で `STALE_SKILL_BODY_DETECTED=true`)
  - Step 9 の stale 警告文言 (Markdown 可視テキスト) にハッシュ値を追加
- `scripts/check-skill-body-hash.sh`: 新規ファイル — `skill-body-sha` マーカーがファイルの実際の計算済みハッシュと一致するか検証する。bash 3.2+ compatible (連想配列・mapfile 不使用)
- `.github/workflows/test.yml`: 新規 CI ジョブ `check-skill-body-hash` を追加 (既存の `check-config-schema` ジョブと同型、`skills/verify/SKILL.md` に対して直接スクリプトを実行)
- `tests/check-skill-body-hash.bats`: 新規ファイル — `scripts/check-skill-body-hash.sh` の一致/不一致/マーカー不在/ファイル不在/同一行数内容変更の回帰テスト
- `tests/verify.bats`: 既存の `"skill-body-lines marker stays in sync with wc -l (Issue #1447)"` テストと対になる新規テストケース `"skill-body-sha marker stays in sync with computed hash (Issue #1468)"` を追加
- `docs/structure.md`: `.github/workflows/test.yml` の Directory Layout コメント行の CI ジョブ列挙に「skill body hash check」を追加
- `docs/ja/structure.md`: `docs/structure.md` の変更に対応する日本語ミラー同期 (`docs/translation-workflow.md` の Sync Procedure に従う)

## Implementation Steps

1. `skills/verify/SKILL.md` の `<!-- skill-body-lines: N -->` マーカー直後に `<!-- skill-body-sha: H -->` マーカーを追加し (`H` は後述の除外ルールで計算した sha256 の先頭 8 文字の16進小文字)、Step 1 の自己整合チェック 4 箇条書きを以下に置き換える。**`N`/`H` は本 Issue の全編集完了後、最後に確定させること** (マーカー自身が行数・内容双方に影響するため):
   - Cached side: `<!-- skill-body-lines: N -->` の数値と `<!-- skill-body-sha: H -->` の16進値の両方を、現在実行中の指示文からそのまま転記する (新規ツール呼び出しで再取得しないこと — 再取得すると両辺が常にディスク上の現在値になり比較が恒真式になって stale 検出が機能しなくなる、既存注意書きと同じ理由)。
   - Disk side: `wc -l < "${CLAUDE_PLUGIN_ROOT}/skills/verify/SKILL.md"` で行数を取得し、`grep -v '<!-- skill-body-' "${CLAUDE_PLUGIN_ROOT}/skills/verify/SKILL.md" | shasum -a 256 | cut -c1-8` でハッシュを取得する (`skill-body-lines`/`skill-body-sha` の両マーカー行は `grep -v` により除外 — マーカー自身がハッシュ対象に含まれる自己参照問題を避けるため)。
   - Mismatch: 行数・ハッシュのいずれかが不一致なら `STALE_SKILL_BODY_DETECTED=true` とし、4値 (cached N行/Hハッシュ、on-disk M行/H'ハッシュ) を保持のうえ terminal 警告を出力する: "Warning: skills/verify/SKILL.md may be stale in this session (cached N lines/H hash, on-disk M lines/H' hash). The instructions currently executing may not reflect the latest merged content. Recommend re-running `/verify $NUMBER` in a new conversation session."
   - Match: 行数・ハッシュの両方が一致したときのみ `STALE_SKILL_BODY_DETECTED=false` とし、何も出力せず継続する。
   (→ 受入基準1, 受入基準2)

2. `skills/verify/SKILL.md` Step 9 の "Stale skill body warning line" 文言を、行数のみの表記からハッシュ併記に変更する: "⚠️ This `/verify` run may have executed a stale, session-cached copy of `skills/verify/SKILL.md` (cached N lines/H hash, on-disk M lines/H' hash) — consider re-running `/verify $NUMBER` in a new conversation session." (→ 受入基準1)

3. `scripts/check-skill-body-hash.sh` を新規作成する。デフォルト対象は `skills/verify/SKILL.md` (第1引数で上書き可能、テスト容易性のため — `scripts/check-allowed-tools.sh [skill-dir]` と同じ位置引数パターン)。ロジック: 対象ファイルが存在しなければ exit 0 (fail-open)。`skill-body-sha` マーカーが存在しなければエラーメッセージを stderr に出力し exit 1 (fail-closed — 本 Issue の実装で必ずマーカーを追加するため、不在は将来の誤削除を示すシグナル)。マーカー値とステップ1と同じ除外ルールで計算した実際のハッシュを比較し、不一致なら期待値を明示した上で exit 1、一致すれば exit 0。`.github/workflows/test.yml` に `check-config-schema` ジョブと同型の新規ジョブ `check-skill-body-hash` を追加し、このスクリプトを引数なしで実行する。(→ 受入基準3)

4. `tests/check-skill-body-hash.bats` を新規作成し、(a) マーカーと計算値が一致 → exit 0、(b) マーカーが stale → exit 1 かつ期待値をメッセージに含む、(c) マーカー不在 → exit 1、(d) 対象ファイル不在 → exit 0、(e) 行数を変えない内容変更 (同一行数のリネーム相当) → exit 1、の5ケースを追加する。`tests/verify.bats` に既存の `"skill-body-lines marker stays in sync with wc -l (Issue #1447)"` と対になる新規テスト `"skill-body-sha marker stays in sync with computed hash (Issue #1468)"` を追加する。既存スイートが PASS することだけでなく、これら新規テストケースを追加したうえで `bats tests/` スイート全体が PASS すること。(→ 受入基準3, 受入基準4)

5. `docs/structure.md` の `.github/workflows/test.yml` 行のコメント (CI ジョブ列挙) に「skill body hash check」を追加する。`docs/translation-workflow.md` の Sync Procedure に従い、対応する `docs/ja/structure.md` の同一行 (現行: 34行目) も日本語で同期する (コードフェンス数の整合も確認)。(ドキュメント同期)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md Step 1 の自己整合チェックが、行数比較に加えて内容ハッシュ (sha 等) の比較を規定しており、行数が一致する変更でも stale を検出できる手順になっている" --> `skills/verify/SKILL.md` Step 1 が内容ハッシュによる比較を規定している
- <!-- verify: grep "skill-body-sha|skill-body-hash" "skills/verify/SKILL.md" --> 行数マーカーと並ぶハッシュマーカーが本文に存在する
- <!-- verify: rubric "ハッシュマーカーの更新漏れを防ぐ CI チェック・生成スクリプトのいずれかが追加されているか、不要と判断した理由が Spec の Notes に記録されている" --> マーカー値の正しさを検証する手段 (CI チェックまたは生成スクリプト) が用意されている、または不要と判断した理由が記録されている
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- 行数を変えない `skills/verify/SKILL.md` の変更が landing した後の `/verify` 実行で、stale 検出が発火することを観察する<!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - `/verify` の Step 9 コメント冒頭に stale 警告行が出力されていること
    - 警告行が cached 値と on-disk 値の不一致を具体的に示していること

## Notes

### ハッシュ設計: 自己参照の回避と「常時両方比較」の採用理由

ハッシュはマーカー自身を含む本文全体から計算すると、マーカー値を書き換えるたびにハッシュも変わり、ハッシュもまた書き換わる…という自己参照が成立しない。これを避けるため、`grep -v '<!-- skill-body-'` で `skill-body-lines`/`skill-body-sha` の両マーカー行を計算対象から除外する設計とした (順序に依存せず、将来マーカーの並びが変わっても安全)。

Issue 本文は「行数一致時のみハッシュを追加検証する二段構え」「常時ハッシュ比較」のどちらでも良いとしていた。本 Spec は後者 (行数比較・ハッシュ比較を常に両方計算し、いずれかの不一致で stale 判定する OR 条件) を採用した。理由: (a) 分岐のない単純なロジックの方がプローズでの記述・実装のいずれでも誤り込みにくい、(b) `wc -l` と `grep|shasum|cut` はいずれも軽量な bash 呼び出しであり、二段構えによる計算コスト削減の実益が小さい、(c) 「行数が一致しつつハッシュ計算だけ何らかの理由で不能」という二段構え特有のフォールスルーを考慮せずに済む。

### `shasum` を採用した理由 (ポータビリティ)

既存コード (`scripts/gh-graphql.sh`) はキャッシュキー生成に `md5sum` を使用しているが、これは GNU coreutils 由来で標準の macOS には同梱されない (本リポジトリの `macos-shell` CI ジョブは `bash -n` の構文チェックのみで実行検証はしないため、この非互換は CI では顕在化しない)。`shasum` は macOS に標準搭載されている Perl 付属ツールであり、Ubuntu 系 CI ランナーにも通常同梱されているため、`sha256sum`/`md5sum` より高いポータビリティを持つ。本 Issue の新規スクリプトは `shasum -a 256 | cut -c1-8` を採用し、既存の `md5sum` 使用箇所には手を入れない (本 Issue のスコープ外)。

### マーカー値検証手段として CI チェックスクリプトを採用した理由 (受入基準3 対応)

自動生成スクリプト (値を自動で書き込む方式) ではなく、検証専用スクリプト + CI ジョブを採用した。理由: (a) 既存の `check-config-schema.sh`/`check-forbidden-expressions.sh`/`check-bare-bracket-assertions.sh` と同型のパターンに従うことで一貫性を保てる、(b) 誤った値を自動上書きする生成スクリプトは実装時の誤字脱字を隠蔽しうるが、検証専用スクリプトはエラーメッセージに期待値を明示するため、人間・LLM いずれが実装する場合も確認しながら反映でき、意図しない自動上書きのリスクがない、(c) CI ジョブとして常時実行されるため、`skills/verify/SKILL.md` を変更する将来のあらゆる PR で機械的に守られる (行数マーカーが `tests/verify.bats` の回帰テストで守られているのと同じ考え方を、人手で計算できないハッシュ値については CI 検証で補う)。

### `check-skill-body-hash.sh` の fail-safe critical 判定とエッジケース

本スクリプトは CI マージゲートの一部となるため fail-safe critical と判断した。エッジケースの扱い: (a) 対象ファイルが存在しない場合は exit 0 (fail-open、`check-config-schema.sh` と同型の防御的スキップ。本番での唯一の呼び出し対象 `skills/verify/SKILL.md` は常に存在するため実質到達しない分岐)。(b) `skill-body-sha` マーカー行自体が存在しない場合は exit 1 (fail-closed — 本 Issue の実装で必ずマーカーを追加するため、マーカー不在は将来の誤削除に対する regression シグナルとして扱う)。(c) `shasum` 等の依存コマンドが失敗した場合は `set -euo pipefail` により非ゼロ終了で fail-closed とする (サイレントスキップより安全側に倒す。`shasum` は標準的に利用可能なため実運用では到達しない想定)。(d) 特殊文字・空/巨大入力: マーカー行は固定フォーマットの HTML コメントであり、`grep -oE '[0-9a-f]{8}'` による厳密な抽出のため任意内容の混入や injection リスクはない。

### New test case requirement (light depth — Step 13 retrospective 省略のため本 Notes に代替記録)

新規分岐ロジック (`check-skill-body-hash.sh` のマーカー一致判定、および `skills/verify/SKILL.md` Step 1 のハッシュ比較追加) に対する新規テストケース要件: `tests/check-skill-body-hash.bats` (新規ファイル、5ケース) と `tests/verify.bats` への新規回帰テスト1件を Implementation Step 4 で要求し、既存スイートと合わせて `bats tests/` 全体が PASS することを Verification > Pre-merge の受入基準4 に含めた。

### Steering Docs sync candidate check

`skill-body-lines`/`STALE_SKILL_BODY_DETECTED` をキーワードに `docs/`, `tests/`, `scripts/`, `modules/` を `grep -rn` したところ、ヒットは `tests/verify.bats` (Implementation Step 4 で対応済み) と、過去 Issue (#1447/#1458/#1461) の disposable Spec ファイル (historical record として同期対象から除外) のみであり、追加の同期対象なし。

### `docs/translation-workflow.md` 同期チェック

`docs/structure.md` (トップレベル `docs/*.md`、`docs/spec/`/`docs/reports/`/`docs/ja/` の除外対象外) を変更するため、`docs/translation-workflow.md` の Sync Procedure に従い対応する `docs/ja/structure.md` (34行目が該当箇所) を Changed Files に追加した。Implementation Steps は SPEC_DEPTH=light の上限 (5件) に既に達していたため、新規ステップを追加せず既存の Step 5 (docs/structure.md 更新) に統合した。

## Consumed Comments
- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1468#issuecomment-5652635164
