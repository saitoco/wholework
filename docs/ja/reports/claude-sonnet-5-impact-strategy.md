[English](../../reports/claude-sonnet-5-impact-strategy.md) | 日本語

# Wholework の Claude Sonnet 5 影響分析と戦略

**作成日**: 2026-07-02
**作成者**: 自動分析セッション
**モデルリリース**: Claude Sonnet 5 (`claude-sonnet-5`) — 2026-06-30 ([アナウンス](https://www.anthropic.com/news/claude-sonnet-5))
**対象範囲**: フェーズ別 model/effort マトリクス (`docs/tech.md`, `ssot_for: model-effort-matrix`) と、default-parent 変更で影響を受ける skill/script インベントリ
**ステータス**: 提案 — 実行計画は「Candidate Issues」 (§8) を参照

**関連**: `docs/reports/claude-fable-5-impact-strategy.md` および `docs/reports/claude-opus-4-7-optimization-strategy.md` を踏まえて作成

## 1. エグゼクティブサマリー

Claude Sonnet 5 は Sonnet 4.6 からの agentic 性能の大きな飛躍だ — 早期のパートナー証言によれば、バグを調査し、再現テストを書き、修正を実装し、変更を stash してリグレッションを自力で確認する、これらすべてを 1 パスでこなし、これまで未解決だった実在の pull request を、テスト済み・検証済みの結果まで無人で運びきったという。`effort: xhigh` では、意味のある割合のタスクで Opus 4.8 に迫り、一方で導入価格 ($2 input / $10 output per MTok、2026-08-31 まで。以降は $3/$15 が標準) は Opus 4.8 のコスト ($5/$25) のおよそ 40〜60% に位置する。`medium` effort ティアはコスト/性能カーブを大きく広げると報告されており、Claude Code / Cowork / Chat のレート制限もリリースに合わせて引き上げられた。サイバー関連のセーフガードは Opus 4.7/4.8 の水準に据え置かれており — Fable 5 の Mythos ティア分類器よりも明確に緩い。

Wholework は現在、フェーズ別マトリクス全体で Sonnet 4.6 を **default parent model** として固定している (`docs/tech.md` §Phase-specific model and effort matrix, `ssot_for: model-effort-matrix`)。Sonnet 5 は、Opus をなお大きく下回るコストのまま agentic 精度を高めるという組み合わせを備えており、マトリクスを前回再校正して以降、Wholework の default-model 経済性にとって最も影響の大きい model ティアの動きだ — Fable 5 よりも影響が大きい。Fable 5 は $10/$50 の価格と保持制約により opt-in 限定の採用ストーリーにとどまるからだ (`[[project_sonnet_5_migration]]`)。

本レポートの結論はこうだ: **default-parent の問いは実在するが、本 Issue の中ではまだ着手可能ではない。** Wholework の `/code` skill とフェーズ orchestration は既に、effort と model を独立に調整可能な軸として扱っている (`docs/tech.md` §Effort optimization strategy)。したがって Sonnet 4.6 → Sonnet 5 の差し替えは、2 つの計測が着地した *後* であれば、狭く機械的な変更にすぎない — `/verify` の interactive 摩擦の再計測 (#877) と、tokenizer 由来の watchdog/context-budget 影響 (#878) だ。本 Issue は Migration path Phase 1 のみにスコープする: 影響インベントリを公開し、`docs/tech.md` のマトリクスにノートのみの段落を追加し (表本体の編集はしない)、Phase 2〜4 が必要とする follow-up Issue (§8) を列挙する。実際の default-parent 差し替え、フェーズごとの effort 再校正、`--effort=` フラグ露出は、いずれもそれらの follow-up Issue に意図的に先送りする。これはマトリクスに触れる変更に対する CI-sensitive Size M 最小ポリシーと整合する (`[[feedback_ci_sensitive_size_m]]`)。

*Fable 5 レポートとの関係におけるスコープの注記*: Fable 5 レポートの §2 (「Wholework に依然として存在意義はあるか?」) は、ここでは繰り返さない。Sonnet 5 は Fable 5/Mythos の 1 ティア下に位置するため、そこで既に検討した scaffold 溶解圧力と Managed-Agents 競合圧力は、推移的に、かつより低い強度で適用される — より高性能な *default* model は、同じ governance/verification の論拠を弱めるのではなく強める。完全な論証は `docs/reports/claude-fable-5-impact-strategy.md` §2 を参照。

## 3. Claude Sonnet 5 の主な変更点 (Wholework に関連するもの)

### 3.1 価格

| Model | 価格 (input/output per MTok) | Opus 4.8 ($5/$25) 比 |
|---|---|---|
| Sonnet 5 — 導入価格 (2026-08-31 まで) | $2 / $10 | 約 40% |
| Sonnet 5 — 標準価格 (2026-09-01 から) | $3 / $15 | 約 60% |
| Opus 4.8 (参照) | $5 / $25 | 100% |
| Fable 5 (参照、opt-in 限定) | $10 / $50 | 200% |

Sonnet 5 の標準価格 ($3/$15) は、Wholework のコストモデル上で Sonnet 4.6 が既に占めているのと同じ帯域にある (Fable 5 レポートの「Sonnet 4.6 の約 3.3 倍」という Fable 5 の $10/$50 との比較を逆算すると、Sonnet 4.6 はおよそ $3/$15 になる)。言い換えれば、Sonnet 5 は default-parent スロットに新しいコストティアを **導入しない** — それは、Wholework が default model に *既に支払っている価格で* 明確に高い agentic 精度を提供し、さらに導入期間中はそれよりも安い。

### 3.2 tokenizer の更新

Sonnet 5 は Opus 4.7 の変更と同じファミリーの tokenizer 更新を搭載する: 同じ入力テキストが、旧 tokenizer よりも 1.0×〜1.35× 多いトークンにマップされる。これは `claude-watchdog.sh` の no-stdout タイムアウト校正と、Wholework 内の文字数ベースの context-budget ヒューリスティックへの **直接的な入力** だ。完全な計測は `#878` (§4.4) に委譲する — 本レポートは、変更が存在し当該 Issue のスコープに含まれることを記録するのみである。

### 3.3 effort カーブの広がり

Anthropic のガイダンスによれば、Sonnet 5 での effort レベル調整は Sonnet 4.6 よりもコスト/性能カーブをさらに広げる: `medium` effort は深い推論を必要としないタスクに対して有意に高いコスト効率をもたらし、`xhigh` effort は一部のタスクで Opus 4.8 クラスの性能に迫る。これは `docs/tech.md` マトリクスのフェーズ別 effort 列 (現状 `run-code.sh`, `run-review.sh` は `high`。`run-spec.sh` は `max`/`xhigh`) に直接影響する — 再校正候補は §4.2 に列挙するが、実際のフェーズごとの effort 変更は Phase 3 の作業 (§8, C シリーズ) であって本 Issue ではない。

### 3.4 レート制限とサイバーセーフガード

Claude Code / Cowork / Chat のレート制限は Sonnet 5 リリースに合わせて引き上げられた。これは Wholework の `run-*.sh` orchestration にとって純粋な運用上のプラスだ (対応不要)。サイバーセーフガードは Fable 5 のより厳格な Mythos ティア分類器ではなく Opus 4.7/4.8 の水準に据え置かれている — つまり Sonnet 5 は、Fable 5 レポート §4.6 に記録したサイバー分類器フォールバックを Fable 5 より誘発しにくい。これは、仮に Sonnet 5 をそこで採用する場合の `review-bug` 系のセキュリティ感度の高いクエリにとって、関連する (好ましい) データポイントである。

### 3.5 Fable 5 の再展開 (2026-07-01) — ティア分離

Fable 5 は 2026-06-13 に政府指令のもとで停止され、Sonnet 5 のローンチ翌日である 2026-07-01 に再展開されたと報じられている。本レポートは両者を別トラックとして扱う: **Sonnet 5 は default-parent 候補** (本レポート) であり、一方 **Fable 5 は opt-in 限定のまま** だ — これは `docs/tech.md` の既存の Fable 5 段落と Fable 5 レポート §5.2 に沿う。再展開は Fable 5 のコスト ($10/$50)、保持 (30 日)、サブスクリプションゲーティングの制約を変えない。本レポートと Fable 5 レポートの candidate Issue を互いに優先度付けする際、この 2 つの model ティアを混同すべきではない。

## 4. 影響分析 (具体)

### 4.1 default parent 差し替え: 決定マトリクス

| 要因 | Sonnet 4.6 (現行 default) | Sonnet 5 | 判定 |
|---|---|---|---|
| 標準価格でのコスト | 約 $3/$15 (ベースライン) | $3/$15 (2026-09-01 から) | 中立 — 同一帯域 |
| 2026-08-31 までのコスト | 約 $3/$15 | $2/$10 (導入価格) | Sonnet 5 に有利 |
| agentic 精度 (brownfield、multi-step) | ベースライン | 大幅な向上が報告。`xhigh` で Opus 4.8 に迫る | Sonnet 5 に有利 |
| watchdog/context budget への tokenizer 影響 | N/A (現行ベースライン) | 1.0〜1.35× — Wholework の実際のプロンプト構成に対しては未計測 | **不明 — 差し替えをブロック** (#878) |
| `/verify` interactive モード摩擦 (#485) | 既知の痛点、high priority で確認済み (`[[project_verify_interactive_pain]]`) | Sonnet 5 の agentic 向上が re-verify ceremony を減らすかは未計測 | **不明 — 差し替えをブロック** (#877) |
| 変更自体の CI 感度 | — | マトリクス表の編集は CI-sensitive、Size M 最小 (`[[feedback_ci_sensitive_size_m]]`) | 計測結果にかかわらず独自の PR-route Issue が必要 |

**読み解き**: コストと報告されている精度は既に Sonnet 5 に有利だが、2 つの不明点 (tokenizer 由来の watchdog 校正、`/verify` 摩擦の差分) は、まさに新しい tokenizer と model に対して実ワークロードを走らせるまで表面化しない類のリグレッションだ。したがってマトリクス差し替えは、#877 と #878 が着地する *後* に順序付けるのが正しく、前ではない — これが本 Issue を分析のみにとどめる根拠である (`[[project_sonnet_5_migration]]`)。

### 4.2 フェーズ別 effort 再校正候補

§3.3 のとおり、`medium` effort は今やより広い範囲をカバーし、`xhigh` は Opus 4.8 に迫る。Sonnet 5 が default として採用された後に再検討する候補 (Phase 3, §8):

- `run-code.sh` (現状 `high`): 現在の `high` effort が既に過剰供給かもしれない XS/S patch-route Issue で `medium` の候補。SSoT を変える前に A/B の証拠を要する。
- `run-review.sh` (現状 `high`): review orchestration は機械的 (深い分析は `docs/tech.md` のマトリクス根拠のとおり sub-agent が担う) であり、もっともらしい `medium` 候補となる。
- `run-spec.sh` (現状 Sonnet では `max`): 設計品質にクリティカルなフェーズ。§3.3 の「`xhigh` が Opus に迫る」というフレーミングは、L サイズの spec で Opus に落とさずとも `xhigh` で十分かもしれないことを示唆するが、これは品質感度の高い変更であり、default の切替ではなく慎重な評価を要する。
- `run-issue.sh` (現状 `high`): issue フェーズの作業は実装ではなくスコープ分析なので、再検討のリスクは低い。4 つのうち最も優先度は低い。

これらのいずれも本 Issue では実装しない — Sonnet 5 の default parent 採用 (Phase 2) をゲートとする Phase 3 の candidate Issue (§8, C シリーズ) である。

### 4.3 sub-agent (Opus alias) 継続の判断

`docs/tech.md` のマトリクスは現在、`review-bug`, `review-spec`, `issue-scope`, `issue-risk`, `issue-precedent`, `frontend-visual-review` を `opus` alias (Opus 4.8 に自動解決) にルーティングしている。Sonnet 5 の「`xhigh` が Opus 4.8 に迫る」というフレーミングは、これらの sub-agent の一部を Sonnet 5 に移せるかという問いを提起する。

**推奨: これらの sub-agent は当面 Opus 4.8 を維持する。** `docs/tech.md` におけるこれらの各ルートの根拠は *精度クリティカル性* だ — バグ検出、spec 逸脱検出、scope/risk/precedent 調査は、まさに「意味のある割合のタスクで Opus 4.8 に迫る」 (つまり *全* タスクではない) が容認できないヘッジとなるタスクである。`review-bug` での false negative はバグを出荷し、`issue-precedent` での precedent の見落としは下流で受入条件の品質を劣化させる。sub-agent の effort は親から継承され、これらの agent は通常フェーズ総コストのわずかな割合なので、差し替えのコスト論拠は精度リスクに対して弱い。この判断は、バグ検出/precedent 取得タスクを特に対象とした Sonnet 5 `xhigh` のベンチマークが利用可能になった場合にのみ再検討すべきだ (本 Issue ではなく、将来の Icebox 再評価トリガーの候補)。

### 4.4 tokenizer 影響 — #878 に委譲

Sonnet 5 の tokenizer は、同じ入力を 1.0×〜1.35× 多いトークンにマップし、Opus 4.7 の tokenizer 変更と同じファミリーにある。Wholework の実際のプロンプト構成 (Spec 本文、Issue 本文、git diff、`auto-events.jsonl` の抜粋) が、実ワークロードがその範囲のどこに落ちるかを決め、それが `claude-watchdog.sh` の no-stdout タイムアウトのデフォルトと context-budget ヒューリスティックの再校正が必要かどうかを決める。本レポートはその計測を試みない — それは `#878` (「context-budget: Sonnet 5 tokenizer 変更 (1.0-1.35×) の watchdog/context budget 影響測定」) の完全なスコープであり、§4.1 のとおり default-parent 差し替えをブロックする。

### 4.5 `/verify` の挙動改善 — #877 に委譲

`/verify` interactive モードは、繰り返される re-verify ceremony による、確認済みで high-priority のユーザー向け摩擦を抱えている (`[[project_verify_interactive_pain]]`, Issue #485)。Sonnet 5 の高い agentic 精度と報告されている自己検証挙動は、その摩擦を減らすもっともらしいレバー (re-verify を要する false FAIL の減少、より信頼できる構造化受入テスト) だが、これはドキュメントのみの判断ではなく、実際の `/verify` 実行に対する再計測を要する。その再計測と、それに伴う設計簡素化は `#877` (「verify: Sonnet 5 での /verify interactive 摩擦 (#485) 再測定と設計簡素化判定」) の完全なスコープである。

### 4.6 判断基準 (ドラフト、Issue #876 §B と整合)

Issue 本文のドラフト決定マトリクスを引き継ぐ:

- **常に Sonnet 5** (default として採用後): read-heavy、低リスク、高並列性のフェーズ — `/audit stats`, `/audit auto-session`, `/auto --batch` の親 orchestration。これらは model 差し替えの blast radius が最も小さく、ボリュームが最も大きいので、コスト削減が複利で効く。
- **Sonnet 5 `xhigh` を評価中**: 実装が重いフェーズ (`run-code.sh`)、spec フェーズ (`run-spec.sh`) — 品質面の潜在的アップサイドが最も大きいが、リグレッションのコストが最も高いフェーズでもある (spec エラーは既存のマトリクス根拠のとおり全下流フェーズに伝播する)。
- **Opus 4.8 を継続**: バグ検出 (`review-bug`)、spec 逸脱 (`review-spec`)、scope/risk/precedent 調査 (`issue-scope`/`issue-risk`/`issue-precedent`) — §4.3 のとおり、agentic な精度がクリティカルであり、「Opus 4.8 に迫る」は「Opus 4.8 に一致する」ではない。
- **当面保留**: `/verify`, `/merge` — 現状 Sonnet で十分、機械的。Sonnet 5 がこの計算を変えるという証拠はまだない (#877 は `/verify` を特に対象とするので、#877 の着地後に再検討)。

## 5. 戦略的推奨

### 5.1 マトリクス表に触れずに影響インベントリを公開する (P1)

本 Issue 自身のスコープ: 本レポートと `docs/tech.md` のノートのみの段落を出荷する (§ Migration path Phase 1)。マトリクス表そのものは編集しない — default-parent 差し替えは、独自の PR-route Issue に属する、別個の CI-sensitive な変更 (`[[feedback_ci_sensitive_size_m]]`) であり、#877/#878 の後に順序付ける。

### 5.2 default-parent 差し替えを #877 と #878 の後に順序付ける (P1)

Phase 2 の default-parent 差し替え Issue (§8, C1) を起票・優先度付けし、両方のブロッキング計測が着地したらすぐ実行できるようにしておく。ただしそれらの計測を先回りしない。これは Fable 5 採用で既に用いたパターン (measure-then-decide、default-then-measure ではない) を保つ。

### 5.3 Phase 3 の effort 再校正を複数の小さな Issue にスコープする (P2)

§4.2 のとおり、`run-code.sh`, `run-review.sh`, `run-spec.sh`, `run-issue.sh` の effort レベルを、1 つの束ねた変更ではなく、独立した低リスクの patch/S サイズ Issue として再校正する — これは、狭く個別にリバート可能な SSoT 編集を好む Wholework の既存の選好に一致し、各フェーズの証拠をそれぞれの是非で評価できるようにする。

### 5.4 sub-agent の model 差し替えを延期し、精度クリティカルな役割では Opus 4.8 を維持する (P2)

§4.3 のとおり、本 Issue とその直近の follow-up では sub-agent の frontmatter を変更しない。バグ検出/precedent 取得の精度を特に対象とした (一般的な agentic コーディングベンチマークではない) Sonnet 5 `xhigh` のベンチマークが利用可能になった場合にのみ再検討する。

### 5.5 `--effort=` フラグ露出を、緊急ではなく Icebox 適格として扱う (P3)

Size × model × effort の 3 軸フラグ露出 (Phase 4) は、本レポートで特定された緊急のドライバーがない — 正しさやコストをブロックする機能ではなく、利便性/制御の機能だ。需要シグナルを待ちつつ、近い将来の Issue ではなく直接 Icebox 候補 (`[[project_icebox_index]]`) として起票することを推奨する。

## 6. 影響サマリー表

| 領域 | リスク/機会 | 優先度 |
|---|---|---|
| default parent 差し替え (Sonnet 4.6 → Sonnet 5) | コスト中立〜有利、精度向上。#877/#878 にブロックされる | P1 |
| `/verify` 再計測 (#877) | 確認済みで high-priority の interactive 摩擦を減らす可能性 | P1 (#877 で追跡) |
| tokenizer/watchdog 影響 (#878) | 計測まで default-parent 差し替えをブロック | P1 (#878 で追跡) |
| フェーズ別 effort 再校正 | default 差し替え着地後のコスト効率 | P2 |
| sub-agent (Opus alias) 継続 | 変更なし。早計な差し替えは精度リスク | P2 (保留) |
| Fable 5 ティア分離のメッセージング | opt-in の Fable 5 と default 候補の Sonnet 5 を混同しない | P2 |
| `--effort=` フラグ露出 | 緊急のドライバーなし。Icebox 候補 | P3 |

## 7. Migration チェックリスト

- [x] `docs/reports/claude-sonnet-5-impact-strategy.md` (本レポート) を公開
- [x] `docs/tech.md` の Phase-specific model/effort matrix セクションに Sonnet 5 のノートのみの段落を追加し、本レポートへリンク
- [x] `docs/ja/reports/claude-sonnet-5-impact-strategy.md` ja 翻訳を作成 (2026-07-03、§9 のとおり別個の明示的決定)
- [ ] candidate Issue (§8) が起票済み、または既存 Issue にマップ済みであることを確認 (`#877`/`#878` は既存。C シリーズは Phase ごとに起票予定)
- [ ] (任意) Phase 2 の default-parent 差し替え Issue のドラフトを準備。#877/#878 完了まで保留
- [ ] (任意) Phase 3 の effort 再校正 Issue ドラフトを準備 (`run-*.sh` スクリプトごとに 1 件)。Phase 2 まで保留
- [ ] (任意) §5.5 のとおり `--effort=` フラグ露出を Icebox 候補として起票

## 8. Candidate Issues (実行計画)

すべて Wholework 標準フォーマット (Background / Purpose / Acceptance Criteria、該当する場合 Pre-merge と Post-merge の分割) に従う。マトリクス表に触れる項目は CI-sensitive で Size M 最小 (`[[feedback_ci_sensitive_size_m]]`)。

| # | タイトル (日本語) | 優先度 | 想定 Size | 影響フェーズ |
|---|---|---|---|---|
| #877 | verify: Sonnet 5 での /verify interactive 摩擦 (#485) 再測定と設計簡素化判定 | high | M | verify |
| #878 | context-budget: Sonnet 5 tokenizer 変更 (1.0-1.35×) の watchdog/context budget 影響測定 | high | M | auto, code, spec, watchdog |
| C1 | default parent を Sonnet 4.6 → Sonnet 5 に切替 (#877/#878 完了後、matrix 表本体を更新) | high | M | issue, spec, code, review, merge |
| C2 | run-code.sh / run-review.sh の effort 再校正 (medium 候補の A/B 評価) | medium | S | code, review |
| C3 | run-spec.sh の effort 再校正 (xhigh 候補、Opus fallback との比較評価) | medium | S | spec |
| C4 | run-issue.sh の effort 再校正 (medium 候補、低リスクから着手) | low | S | issue |
| C5 | `--effort=` フラグ露出 (Size × model × effort 3 軸、opt-in) | low | M | all skills |
| C6 | Sonnet 5 xhigh の bug-detection/precedent-retrieval ベンチマーク再評価トリガー登録 (Icebox) | low | XS | review, issue |

### 順序付けの根拠

- **#877, #878** は既に起票済みで、この表の他のすべてをブロックする — **C1** を実行できるより前に両方が着地しなければならない。
- **C1** は実際の default-parent 差し替えであり、この表で単独で最もレバレッジの高い変更だ。他のすべての候補 (C2〜C4) は、その effort レベルを再校正する価値が出る前に Sonnet 5 が default であることに依存するからだ。
- **C2, C3, C4** は独立したフェーズごとの effort 再校正で、リスク順に並べる: `run-code.sh`/`run-review.sh` を先に (機械的または sub-agent 委譲)、`run-spec.sh` を次に (品質クリティカル、より多くの証拠を要する)、`run-issue.sh` を最後に (最も優先度が低く、緊急性が最も低い)。
- **C5** は緊急のドライバーがなく (§5.5)、C1〜C4 とは独立に、需要シグナルが現れたときに実行できる。
- **C6** は実装変更ではなくモニタリング/再評価トリガーだ — 最もコストが低く、最も優先度が低い。

## 9. 非目標

- Fable 5 の default 差し替えはしない — Fable 5 は自身のコスト/保持制約により opt-in 限定のまま (§3.5)。本レポートはその結論を再検討しない。
- agent ごとの frontmatter model 差し替えの実装はしない (`review-bug`, `review-spec`, `issue-scope`, `issue-risk`, `issue-precedent`, `frontend-visual-review`) — §4.3 はこれらの役割で Opus 4.8 を維持することを推奨。将来の差し替えは、個別に判断する別 Issue とする。
- 本 Issue での実際の default-parent 差し替えはしない — それは Phase 2 (C1, §8) であり、`#877`/`#878` の後に順序付ける。
- `docs/tech.md` のマトリクス表の編集はしない — §5.1 と Implementation Steps に記載したノートのみの段落だけ。
- ja ミラーに翻訳同期の義務はない — `docs/reports/` は翻訳同期から除外されている (`docs/translation-workflow.md` § Exclusions)。2026-07-03 に作成した `docs/ja/reports/claude-sonnet-5-impact-strategy.md` ミラーは、別個の明示的な決定として手動で維持し、自動同期しない。

## 10. 参照

- [Introducing Claude Sonnet 5 (Anthropic, 2026-06-30)](https://www.anthropic.com/news/claude-sonnet-5)
- [Claude Sonnet 5 System Card](https://www.anthropic.com/claude-sonnet-5-system-card)
- `docs/reports/claude-fable-5-impact-strategy.md` (関連。Mythos ティア分析と、本レポートが §1 で参照により継承する governance/verification-harness の論拠)
- `docs/reports/claude-opus-4-7-optimization-strategy.md` (関連。旧 model 再校正の先例)
- `docs/tech.md` §Phase-specific model and effort matrix (`ssot_for: model-effort-matrix`、本レポートのノートのみの段落の更新対象)
- Issue #876 (本 Issue), #877 (`/verify` 再計測), #878 (tokenizer/context-budget 計測)

---

*本レポートは §8 の Issue を提案する。`#877` と `#878` は既に存在し、Issue #876 の blocked-by 子 Issue である。残りの C シリーズ Issue は、適切な `phase/*` ラベルを付し Wholework GitHub Project 上で Priority を設定したうえで、Wholework GitHub リポジトリに作成されることを想定しており、上記「順序付けの根拠」に沿って順序付ける。*
