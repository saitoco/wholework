# Issue #891: emit-event: SKILL.md からの source 呼び出しを zsh 互換に修正

## Overview

`skills/verify/SKILL.md` (4箇所) と `skills/auto/SKILL.md` (1箇所) には、LLM が Bash tool 経由で直接実行する裸の `source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"` 呼び出しが計5箇所ある。Bash tool の実行シェルはユーザーの `bash` または `zsh` プロファイルに依存するため、zsh をデフォルト shell とする環境 (macOS Catalina 以降のデフォルト) ではこれらの呼び出しが `scripts/emit-event.sh:82: parse error near '>'` で失敗する。本 Issue では、この呼び出しパターンを zsh 環境でも確実に動作する形に修正する。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class — Triage フェーズ (auto-chained) の Issue Retrospective。Title 正規化 (component を根本原因ファイル `emit-event.sh` に合わせて正規化)、Type=Bug・Size=S・Value=3 の判定根拠、AC1 の文言を実装手段非依存 (outcome-based) に補正した自動解決理由、および Background 記載の技術的主張 (`scripts/emit-event.sh` L82 の flock fd リダイレクト構文、`skills/verify/SKILL.md` 内 4箇所・`skills/auto/SKILL.md` 内 1箇所の `source emit-event.sh` 呼び出し) が grep で全て一致確認済みである旨を含む。内容は既に Issue 本文に反映済み。 (https://github.com/saitoco/wholework/issues/891#issuecomment-4883129667)

## Reproduction Steps

1. `zsh -c 'source scripts/emit-event.sh'` を実行する。
2. `` scripts/emit-event.sh:82: parse error near `>' `` が発生し、exit code 126 で失敗する (Issue本文には exit code 127 と記載されているが、Spec作成時の再検証環境 (zsh 5.9.1 / macOS) では 126 を観測した。差異は環境固有の値でありアプローチ選択に影響しないため、参考情報として記録するのみ — Auto-Resolve Log 参照)。
3. 対照として `bash -c 'source scripts/emit-event.sh'` は exit code 0 で成功する。

## Root Cause

`scripts/emit-event.sh` L82:
```bash
(flock -x 200; echo "${json}" >> "${_log}") 200>"${_log}.lock"
```
は、サブシェル `(...)` の直後に複数桁 (2桁以上) のファイルディスクリプタ番号でリダイレクトする構文になっている。zsh (5.9.1 で検証) はこの構文の組み合わせをパースできず `parse error near '>'` で失敗する。切り分け検証の結果、以下を確認した:

- サブシェルなしなら3桁fd (`echo hi 200>file`) でも zsh は正常にパースする
- サブシェル `(...)` 付きでも1桁fd (`(cmd) 9>file`) なら zsh は正常にパースする
- サブシェル付きで2桁以上のfd (`(cmd) 20>file` / `(cmd) 200>file`) はいずれもパースエラーになる

つまり根本原因は「サブシェル + 複数桁fdリダイレクト」の組み合わせに対する zsh パーサーの制約であり、1桁fd に変更すれば zsh・bash 双方で同一構文がパース可能になる。

`run-*.sh` (`run-code.sh` / `run-merge.sh` / `run-review.sh` / `run-spec.sh` / `run-issue.sh` / `run-auto-sub.sh` 等) は `#!/bin/bash` shebang を持つスクリプトとして常に bash プロセス内で実行されるため、これらからの `source` 呼び出しは無関係かつ安全 (`modules/event-emission.md` L91 の記述もこれに該当し、本 Issue のスコープ外)。問題があるのは SKILL.md 内で LLM に Bash tool 経由で直接実行させる bash コードブロックに含まれる裸の `source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"` 呼び出しのみ:

- `skills/verify/SKILL.md`: L500, L518, L582, L784 (計4箇所)
- `skills/auto/SKILL.md`: L1153 (1箇所)

修正方針として、(a) `scripts/emit-event.sh` 自体を zsh 互換に書き換える、(b) 呼び出し側 (SKILL.md 5箇所) を `bash -c '...'` でラップする、の2案があったが、本 Spec では (a) を採用する。理由は Notes 参照。

## Changed Files

- `scripts/emit-event.sh`: L82 の flock fd 番号を `200` (複数桁) から `9` (1桁) に変更 — `(flock -x 200; echo "${json}" >> "${_log}") 200>"${_log}.lock"` → `(flock -x 9; echo "${json}" >> "${_log}") 9>"${_log}.lock"` — bash 3.2+ compatible (zsh でもパース可能な構文になる)
- `tests/emit-event.bats`: `zsh -c` 経由で `source scripts/emit-event.sh && emit_event ...` を実行し、parse error なく JSONL 行が出力されることを検証する新規テストケースを追加 — bash 3.2+ compatible。zsh 未インストール環境で CI を壊さないよう `command -v zsh` 不在時は `skip` するガードを含める
- `docs/structure.md`: [Steering Docs sync candidate] L170 の `emit-event.sh` 説明を確認。本修正は fd 番号という内部実装詳細のみの変更で、インターフェース (`emit_event()` の呼び出し方、利用者一覧) に変更はないため、恐らく変更不要
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記の日本語訳。英語版の変更有無に追従 (恐らく変更不要)

## Implementation Steps

1. `scripts/emit-event.sh` L82 の fd 番号を `200` から `9` に変更する (→ 受入条件 AC1)
2. `tests/emit-event.bats` に、`zsh -c` 経由で `source "$SCRIPT" && emit_event ...` を実行し、parse error なく `AUTO_EVENTS_LOG` に正しい JSONL 行が出力されることを検証する新規テストケースを追加する。テスト冒頭に `command -v zsh >/dev/null 2>&1 || skip "zsh not installed"` のガードを入れ、zsh 未インストール環境でも CI が失敗しないようにする (→ 受入条件 AC1, AC2) (after 1)
3. `bats tests/emit-event.bats` を実行し、新規テストを含む既存全テストが pass することを確認する。あわせて `zsh -c 'source scripts/emit-event.sh'` を手動実行して parse error が発生しないことをログとして記録し、対照として `bash -c` 経由でも同等呼び出しが引き続き exit code 0 で成功することを確認する (→ 受入条件 AC1, AC2) (after 2)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md と skills/auto/SKILL.md 内でLLMがBash tool経由で直接実行するevent発火呼び出し(計5箇所)が、zsh環境でもparse errorにならず正常に実行される" --> `skills/verify/SKILL.md` および `skills/auto/SKILL.md` 内で LLM が Bash tool 経由で直接実行する event 発火呼び出し (計5箇所) が、zsh 環境でも parse error なく実行される (`scripts/emit-event.sh` 自体の修正、呼び出し側での `bash -c` ラップ、いずれのアプローチも可 — 採否は `/spec` 時に判断)
- <!-- verify: rubric "修正後のsource emit-event.sh呼び出しパターンがzsh -c経由で実行してもparse errorにならず成功することが確認されている" --> 修正後、`zsh -c` 経由での該当パターンの実行が成功することが確認・記録されている (再現テストまたは実行ログ)

### Post-merge

なし

## Notes

### Auto-Resolve Log (Non-Interactive Mode)

- **Issue Background 記載の exit code (127) と実機再検証結果 (126) の差異**: Spec 作成時に `zsh -c 'source scripts/emit-event.sh'` を再実行し、exit code 126 を観測した (Issue本文は127と記載)。両者とも「異常終了」を示す値であり、根本原因である parse error の発生自体は完全に一致して再現している。exit code の具体値の差異はシェルのビルドやバージョンなど環境固有の要因による可能性があり、修正アプローチの選択や受入条件の充足可否に影響しないため、モデル判断で自動解決 (実害なしと判断し、修正方針には反映しない)。

### アプローチ選択の根拠

`scripts/emit-event.sh` 自体の修正 (採用) と、SKILL.md 呼び出し側の `bash -c` ラップ (不採用) を比較した:

- **`scripts/emit-event.sh` 修正 (採用)**: 変更箇所が1ファイル1行のみで、5箇所ある SKILL.md 側の呼び出し文言は一切変更不要。将来 SKILL.md に同種の `source emit-event.sh` 呼び出しが追加された場合も自動的に安全になる恒久対策。Issue 本文の Auto-Resolved Ambiguity Points が「AC1 はどちらのアプローチでも成立するよう outcome-based に補正した」としている通り、本アプローチでも AC1/AC2 は問題なく充足する。
- **`bash -c` ラップ (不採用)**: 5箇所すべてで呼び出しパターンの書き換えが必要になり、変更範囲が広い。変数展開 ($NUMBER 等) のクォーティングが複雑化し、将来の追加呼び出しでも都度ラップする規律をレビューで担保し続ける必要がある。

fd 番号を1桁 (`9`) に変更する案について、`scripts/*.sh` および `skills/*/SKILL.md` 全体を grep し、fd 9 の明示的な使用 (衝突リスク) がないことを確認済み。`emit_event()` 呼び出し自体がサブシェル内で完結する短命な処理であるため、衝突リスクは低いと判断した。

### CI 検知範囲に関する既知の限界

`.github/workflows/test.yml` の `macos-shell` ジョブは `scripts/*.sh` 全体に対して `bash -n` (bash構文チェックのみ) を実行しており、zsh でのパース可否は検証していない。そのため本種の不具合は今回のように実際に zsh 環境で LLM が Bash tool 経由で実行した際に初めて顕在化する。本 Issue の修正範囲外だが、将来的に zsh 構文チェックを CI に追加する余地がある旨を記録しておく (別 Issue 起票は本 Spec のスコープ外と判断)。
