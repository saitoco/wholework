[English](../../reports/claude-fable-5-impact-strategy.md) | 日本語

# Wholework の Claude Fable 5 影響分析と戦略

**作成日**: 2026-06-12
**作成者**: 自動分析セッション
**モデルリリース**: Claude Fable 5 / Claude Mythos 5 — 2026-06-09（[アナウンス](https://www.anthropic.com/news/claude-fable-5-mythos-5)）
**対象範囲**: Mythos クラス model 登場後の Wholework の存在意義、および配布コンポーネント（skills, agents, scripts）と Steering Documents
**ステータス**: 提案 — 実行計画は「Candidate Issues」（§8）を参照

> ⚠️ **停止中のお知らせ（2026-06-13）**: 政府指令により、Anthropic が Fable 5（`claude-fable-5`）の API 提供を一時停止中です。API を呼び出すとエラーになる可能性が高いです。停止期間は未定ですが長期化はしない見込みです。下記の分析および Candidate Issues は、再開後も有効です。再開時は: 本ノートと `scripts/run-spec.sh` の停止警告行を削除してください。

**関連**: `docs/reports/claude-opus-4-7-optimization-strategy.md` を踏まえて作成

## 1. エグゼクティブサマリー

Claude Fable 5 は、一般利用向けに提供される初の **Mythos クラス** model であり、Anthropic が Opus クラスの *上* に位置づけるティアだ。ほぼ全ての能力ベンチマークで state-of-the-art を達成し、タスクが長く複雑になるほどその差は広がる。Wholework にとって重要な特性は次の通り: これまでの如何なる Claude よりも長時間自律的に作業でき、高 effort では自身の作業を自己検証し、並列 sub-agent が *信頼できる*ようになり（かつ非同期駆動が最適）、学びを書き出す**ファイルベースの memory surface** を与えると性能が顕著に向上する。

ここで本能的に湧くのは存在意義への問いだ。*1 回の model 呼び出しで codebase 全体の移行を 1 日で自律的にこなせるなら、issue→spec→code→review→merge→verify という 6 フェーズの scaffold は依然として割に合うのか?*

**我々の結論は、Fable 5 によって Wholework の存在意義は弱まるどころか強まる — ただし、リポジショニングと再調整を行えば、だ。** Wholework はそもそも「model を賢くする」ための scaffold ではない。作業を GitHub の Issue/PR/Label へ外部化し、人間・将来のセッション・チームがそれを可視化・gate・監査できるようにする **governance（統制）・traceability（追跡可能性）・verification（検証）の harness** である。より自律的な model は *blast radius（影響範囲）が大きい* ため、受入条件・review gate・post-merge 検証・監査証跡の価値は下がるどころか上がる。注目すべきは、Anthropic 自身が推奨する Fable 5 の運用方法（境界を明示する、進捗の主張を tool 結果に照らして裏付ける、検証 harness を回す、memory surface を与える）が、Wholework の設計思想をほぼ一行ずつなぞっている点だ。Wholework の「Spec as cross-phase memory」と `/verify` の post-merge 受入ループは、Anthropic が今まさに推奨するパターンそのものである。

とはいえ、Wholework の前提のいくつかは旧 model 向けに調整されており、今や誤作動する:

1. **review における literal な filter-following** — `review-bug` は「確証のあるバグのみを報告し、誤検知を最小化せよ」と指示されている。Fable 5（および既に Opus 4.8）はこの自己フィルタ指示を *literal に* 守るため、バグ発見能力自体は向上しているのに計測上のリコールが下がりうる。Wholework には既に downstream の検証ステージがあるので、finder プロンプトの自己フィルタは自分のアーキテクチャと衝突している（§4.1, C1）。
2. **watchdog と長いターン** — Fable 5 の難タスクでの単発リクエストは数分に及びうる。1800 秒の no-stdout watchdog デフォルトはより頻繁に発火する（§4.2, C2）。
3. **過度に prescriptive なプロンプト** — Anthropic は、旧 model 向けの逐次的 scaffolding が Fable 5 の出力品質を *下げる* と警告する。Wholework の SKILL.md は意図的に prescriptive であり、選択的な de-prescription 監査（reasoning steps のみ、mechanical steps は除く）が必要だ（§4.3, C5）。
4. **自律実行での early-stop / 境界逸脱** — Fable 5 は稀に、tool 呼び出しなしで意図表明だけしてターンを終えたり、要求されていない隣接アクションを取ったりする。自律 `run-*.sh` の GUARD_PREFIX に、Anthropic 推奨の anti-early-stop と境界リマインダを追加すべきだ（§4.4, C3）。

加えて、採用上の厳しい現実がある: Fable 5 は **$10/$50 per MTok**（Opus 4.8 の 2 倍、Sonnet 4.6 の約 3.3 倍）であり、**サブスクリプションプランでは 2026-06-22 以降 usage credits でゲートされ**、**zero-data-retention 組織では利用不可**（30 日保持が必須）だ。したがって採用は **選択的かつ opt-in** でなければならず、デフォルトのモデル差し替えにしてはならない（§3.3, §5.2）。

作業は 4 段階の優先度に整理し、**9 件の candidate issue** を生成する（§8）。

## 2. Wholework に依然として存在意義はあるか?

これは本レポートが答えるべき中心的な問いなので、機構の話の前に答える。

### 2.1 脅威を正直に述べる

Fable 5 のローンチ証跡は、フェーズ分割型のワークフローエンジンにとって本当に破壊的だ:

- Stripe は 2 ヶ月・5000 万行の Ruby 移行を 1 日に圧縮した。
- 顧客は「1 年前なら 100 回プロンプトを要した」アプリが一発で出てくると報告している。
- 最大 effort では model が「自身の作業を内省し検証」し、「高度に自律的な運用」を可能にする。
- 数百万 token に渡って集中を維持し、自身のメモを使って出力を改善する。

ここから 2 つの具体的な圧力が生じる:

- **Scaffold の溶解。** Wholework のフェーズ境界の一部は元々、context-rot 回避と容量を動機としていた — `docs/tech.md` 自身が「1M context GA 以降、その動機は大きく薄れた」と認めている動機だ。数百万 token を保持し自己検証する model は、作業を 6 つの独立した `claude -p` プロセスに切り分ける *技術的* 根拠を侵食する。
- **収束しつつある第一者プロダクト。** Anthropic の **Managed Agents** は今や **Outcomes**（`user.define_outcome` + 採点可能な rubric → iterate → grade → revise ループ）を提供する。これは概念的に Wholework の 受入条件 → code → `/verify` ループと同じ形であり、しかもサーバー管理だ。Wholework がこれまで持った中で最も直接的な競合に近い。

これらを軽く扱うべきではない。

### 2.2 なぜ存在意義は保たれ、さらに増すのか

Wholework の価値はオーケストレーションの巧妙さではなく、model 呼び出しを *取り巻く* すべてにある:

| ニーズ | より高性能な model はこれを消すか? | Fable 5 の効果 |
|---|---|---|
| 要件捕捉（Issue、受入条件） | No — model は意図の *実行* は上達するが、組織が *何を* 望むかの決定はしない | 中立〜正: 「なぜ」を与えれば意図推論が向上 |
| 適切な粒度の人間 review gate | No — blast radius が大きいほど gate は *より* 必要 | **正**: Fable 5 は「要求外の隣接アクション」を取りより頻繁に質問する。適切な gate が両方を吸収する |
| post-merge 検証 | No — 検証なき自律は最も危険な組み合わせ | **正**: Anthropic は検証 harness を明示的に推奨。`/verify` がまさにそれ |
| 監査証跡（Issue/PR/Label/retro） | No — 監査可能性はチーム/コンプラのニーズで、model の IQ とは直交 | **正**: より自律的な作業 → 何が起きたか再構成する必要が増す |
| セッション横断 memory | No | **強い正**: Fable 5 は memory surface があると「顕著に性能向上」。Spec-as-memory がまさにそれ |

この整合性はフレーミングの偶然ではない。Anthropic の Fable 5 運用ガイダンスは、Wholework が既に満たしているチェックリストのように読める:

- *「memory surface を与える … 1 ファイルに 1 つの学び … 訂正も確認済みアプローチも記録する。」* → Wholework の **Retrospective を Spec に蓄積**するパターン。
- *「自己検証を明示する … fresh-context の verifier sub-agent は自己批判を上回る。」* → Wholework の **`/verify`**（post-merge, fork）と **review-bug → 検証 sub-agent** の 2 段フィルタ。
- *「境界を明示する … 所見を報告して止まる … 求められるまで修正を適用しない。」* → Wholework の **`/issue`（What）vs `/spec`（How）** 境界と **非対話 3 段ポリシー**（auto-resolve / skip / hard-error）。
- *「リクエストだけでなく理由を与える。」* → Spec の **Background / Purpose** セクションが意図を実行へ運ぶ。

言い換えれば、model が高性能で自律的になるほど、Wholework が提供する *デプロイ面* こそが、実リポジトリに向けて安全に使えるようにする要素になる。オーケストレーションはコモディティであり、**governance と verification の harness が moat（堀）**だ。

### 2.3 堀をどこで守るべきか

Managed Agents + Outcomes に対して、Wholework の持続的な差別化要因は:

1. **GitHub ネイティブな成果物** — 作業の記録は、チームが既に生活している Issue・PR・Label・review スレッドであり、不透明なサーバーセッションではない。
2. **サブスクリプション / OAuth 認証** — `run-*.sh` は Claude Code サブスクリプション経路で動く。Managed Agents は API key と Anthropic ホストのコンテナを要する。
3. **段階的採用** — チームは `/review` だけ、`/verify` だけを、フルのホスト型 agent スタックにコミットせず採用できる。
4. **人間 review gate がファーストクラス** — Outcomes は rubric に対し自律的に採点する。Wholework は Issue・PR・AC 確認の各点に *人間* の承認を挿入する。

戦略的な一手（§5.1）は、この**ポジショニングを前面に出す**ことだ: Wholework は、高度に自律的なコーディング agent を実 GitHub リポジトリで安全に走らせるための governance-and-verification harness である — オーケストレーションの巧妙さで競う「issue-driven workflow」ではない。

**結論:** 開発を続けよ。Fable 5 の挙動に合わせて再調整し、long-horizon 推論が割に合う箇所でモデルを選択的に採用し、メッセージングをオーケストレーションではなく governance + verification 中心へリポジショニングせよ。

## 3. Claude Fable 5 の主な変更点（Wholework 関連）

### 3.1 挙動の変化

| 挙動 | Wholework への関連 | レバー |
|---|---|---|
| **より長い自律ターン**（高 effort で単発が数分） | `claude-watchdog.sh`（1800 秒 no-stdout kill）を直撃 | デフォルト引き上げ / 増えたナレーションに依拠 / 進捗 echo（§4.2） |
| **高 effort での自己検証** | `/verify` と review 2 段フィルタを補完。re-verify ceremony 依存を低減 | 文書化。Fable 5 時は re-verify を軽量化検討 |
| **並列 sub-agent が信頼可能、非同期推奨** | `/issue` L/XL と `/review` の fan-out。現状 spawn-and-block | single-message spawn は維持、非同期化を探索（§4.5） |
| **memory surface で性能向上** | Spec-as-memory を裏付け。パターン強化の好機 | retrospective 規律を強化（§5.4） |
| **デフォルトでより多くのユーザー向けナレーション** | tool 呼び出し間の stdout が増える → watchdog に *有利*。ただし wrap-up が冗長 | watchdog には正味プラス。冗長なら抑制のみ |
| **より頻繁に質問 / 隣接アクションを取る** | 自律 `run-*.sh` が質問で停滞 or 過剰行動 | GUARD_PREFIX に境界 + 小決定は聞かないリマインダ追加（§4.4） |
| **稀な early-stop**（意図表明・tool 呼び出しなし） | 非対話の完了を阻害。reconcile が捕捉する必要 | anti-early-stop リマインダ追加。reconcile が部分緩和済み（§4.4） |
| **literal な filter-following** | `review-bug` の「HIGH SIGNAL のみ/誤検知最小化」自己フィルタがリコールを下げる | find と filter を分離（§4.1） |
| **旧 model 向けプロンプトはしばしば過度に prescriptive** | Wholework SKILL.md は高度に逐次的 | 選択的 de-prescription 監査（§4.3） |
| **token カウントダウン提示時の context anxiety** | Task Budgets を採用した場合のみ関連（現状 OAuth CLI では N/A） | 対応不要。将来用にメモ |

### 3.2 API サーフェスの変更（CLI 利用者はほぼ影響なし）

Wholework は **Claude Code CLI**（`claude -p --model … --effort …`）を呼ぶのであって API ではないため、大半の breaking change は非該当だ — ただし 2 つの挙動は CLI 経由でも漏れてくる:

| 変更 | Wholework に該当? | 備考 |
|---|---|---|
| thinking 常時 ON、`budget_tokens`/`thinking:disabled` が 400 | No | CLI が thinking を管理。effort は `--effort` で操作 |
| サンプリングパラメータ削除 | No | CLI 呼び出しで設定していない |
| cyber/bio classifier 経由の `refusal` stop reason | **間接的** | security review query が Fable 5 ではなく Opus 4.8 fallback で処理されうる（§4.6） |
| tokenizer | Opus 4.7/4.8 から変化なし | 同一 tokenizer。現行 Opus ベースラインから token カウントはほぼ不変 |
| 30 日データ保持が必須 | **Yes（採用ゲート）** | ZDR 組織は Fable 5 を一切使えない（§3.3） |

### 3.3 採用上の制約（コストの現実）

| 制約 | 詳細 | Wholework への含意 |
|---|---|---|
| **価格** | $10 入力 / $50 出力 per MTok — Opus 4.8 の 2 倍、Sonnet 4.6 の約 3.3 倍 | デフォルト化は不可。高レバレッジフェーズに限定 |
| **サブスクゲート** | Pro/Max/Team で 2026-06-22 まで含まれ、以降は usage credits 必須 | `run-*.sh` のデフォルト（OAuth/サブスク）は数日で無料 Fable 5 アクセスを失う。デフォルトではなく opt-in フラグに |
| **データ保持** | 30 日保持必須、ZDR では不可 | 採用は ZDR ユーザー向けに graceful degrade すべき |
| **safeguards** | session の <5% が Opus 4.8 に fallback（cyber/bio/distillation classifier） | security-review フェーズが最も露出（§4.6） |
| **CLI エイリアス** | モデル文字列は `claude-fable-5`。Claude Code CLI の短縮 `fable` エイリアスは未確認 | `run-spec.sh` に組み込む前に確認 |

## 4. 影響分析（具体）

### 4.1 review-bug: find と filter の分離（最高価値の変更）

`agents/review-bug.md` は **自己フィルタ** 原則で指示されている: 「確証のあるバグのみを flag … 誤検知を最小化 … 真に修正が必要な問題のみ報告」。Wholework の `/review` Step 10–10.3 アーキテクチャは *既に*、誤検知を除くための別個の downstream 検証 sub-agent パス（Opus, 並列, 最大 10 件）を走らせている。

Opus 4.7/4.8 のコードレビューガイダンス — Fable 5 にはなおさら当てはまる — は明示的だ: review プロンプトが「高 severity のみ報告」「保守的に」と言うと、新しい model はそれを *literal に* 守り、同じだけ徹底的に調べた上で閾値未満の所見を *報告しない*。precision は上がるが、バグ発見が向上していても **計測上のリコールが下がる**。よって Wholework の finder プロンプトは自身の 2 段アーキテクチャと戦っている: find 段で自己フィルタし、*その後* downstream で再びフィルタしているのだ。

**修正:** 分離する。`review-bug` には confidence + severity タグ付きで全ての所見を報告させ、フィルタは downstream 段が行うと明示せよ（「ここでの仕事はフィルタではなくカバレッジだ」）。既存の検証 sub-agent をフィルタとして維持する。これは `agents/review-bug.md`（および `review-light.md` の対応注記）への純粋なプロンプト変更であり、Fable 5 採用とは無関係に **今日の Opus 4.8** に当てはまり、本レポート中で単一最高価値の項目だ。

### 4.2 watchdog vs Fable 5 の長いターン

`scripts/watchdog-defaults.sh` は `WATCHDOG_TIMEOUT_DEFAULT=1800`（30 分 stdout なし → kill）を設定する。`docs/reports/watchdog-recovery-strategy.md` は既に、PR 本文作成まわりの Sonnet long-thinking がこれを超えうると文書化しており、採用された修正は 進捗 echo（Approach D）+ reconcile Stage 2（Approach C）だった。

Fable 5 は silent window をさらに延ばす: 難しい単発リクエストは数分走り、1 フェーズは多数のリクエストを連鎖させる。相反する 2 つの事実:

- **悪化:** ステップごとの思考が長い → stdout 間隔が長い → 1800 秒 kill の誤発火が増える。
- **改善:** Fable 5 はデフォルトでより多くナレーションする — *その* 中間テキストが `claude -p` の stdout に届くなら、watchdog をリセットする。

**アクション:** デフォルト変更の前に、Fable 5 下の watchdog 挙動を spike せよ。ナレーションが確実に stdout へ届かないなら、`WATCHDOG_TIMEOUT_DEFAULT` を引き上げ（例: 1800 → 2700）、かつ/または Approach-D の進捗 echo を long-silent な箇所（spec 設計、review 統合）へ拡張する。プロジェクト単位の `watchdog-timeout-seconds` ノブは escape hatch として維持する。

### 4.3 プロンプトの de-prescription（慎重・選択的に）

Anthropic: *「旧 model 向けに書かれたプロンプトと skill は、しばしば Fable 5 に対して過度に prescriptive で、出力品質を下げる … 古い逐次 scaffolding を外して A/B せよ。」* Wholework の SKILL.md は意図的に逐次的 — それがワークフローエンジンだ。

解決は 2 種類のステップを分離することだ:

- **Mechanical steps**（label 遷移、`gh` コマンド、ファイルパス、順序不変条件）— これらは prescriptive のまま *維持必須*。これは reasoning ではなく決定性だ。触れない。
- **Reasoning steps**（spec をどう設計するか、リスクをどう評価するか、バグをどう見つけるか）— ここが Fable 5 の過 prescription ペナルティが効く箇所だ。de-prescription の候補: サブステップを列挙する代わりに、ゴールと制約を述べ、model に推論させる。

これは **spike-and-measure** 項目であり全面書き換えではない。そして Fable 5 が実際にあるフェーズで採用された場合 *のみ* 実施すべきだ（さもなくば、明示的ステップを好む Sonnet/Opus の挙動を劣化させてしまう）。

### 4.4 自律実行の信頼性: 境界 + early stop

`run-*.sh` は `GUARD_PREFIX`（「skill ステップを完了まで follow … 他 skill へハンドオフしない」）を前置する。Fable 5 はこの prefix が未対応な 2 つの failure mode を追加する:

- **Early stop** — 「これから X を実行する」で締めるが tool 呼び出しがない。Anthropic 推奨の自律リマインダ（「…最後の段落を確認せよ。計画や約束なら、今 tool 呼び出しでその作業を行え…」）は `run-*.sh` の非対話実行に直接マッピングされる。
- **隣接過剰行動** — 要求外のアクション（バックアップブランチ、メッセージ下書き）を取る。境界リマインダ（「ユーザーが問題を述べているとき … 所見を報告して止まる … 状態変更前に証拠がその具体的アクションを支持するか確認する」）は既存の 3 段非対話ポリシーを補完する。

**アクション:** `GUARD_PREFIX`（または source されるリマインダブロック）を anti-early-stop と境界リマインダで拡張する。低コストで、`/auto` の完了信頼性を即座に改善し、Sonnet/Opus でも無害だ。

### 4.5 非同期 sub-agent（将来志向）

Wholework の `/issue` L/XL（Step 11a）と `/review` Step 10 は既に single-message の `Task(...)` spawn で fan-out している — Opus 4.7 向けに追加した conservative-spawn 緩和だ。2 つの更新:

- 括弧書きの根拠「(Opus 4.7 may otherwise serialize the spawns)」は世代依存で古い。Opus 4.8 は sub-agent を *より少なく* spawn し、Fable 5 は *信頼可能* にして委譲を報いる。single-message-spawn 指示は残す（依然正しい）が、根拠は一般化すべきだ。
- Fable 5 は特に、context を保持し orchestrator と通信する **非同期** sub-agent を、spawn-and-block より報いる。skill コンテキストの Task tool は本質的に spawn-and-block なので、これは **将来志向** — multi-agent ロードマップ（`[[project_multi_agent_support]]`）と adapter-chain パターンに沿うものであり、即時変更ではない。

### 4.6 security review における cyber-classifier 露出

`review-bug.md` は shell injection、secrets、「LLM-to-Shell pattern migration risks」を明示的にチェックする。Fable 5 の cyber classifier はこうした query を Opus 4.8 fallback へ回しうる（API では refuse）。Claude Code CLI 経由では Opus 4.8 への fallback は自動かつ透過的で、API refusal よりはるかに非破壊的だ — が、これは **Fable 5 review の security 部分が、Fable 5 ではなく Opus 4.8 によって暗黙に回答されうる** ことを意味する。ブロッカーではなく監視項目であり、`review-bug` に特に Fable 5 を採用する理由をわずかに弱める（そもそも security 分析が一部スコープ外のフェーズでもある）。

## 5. 戦略的提言

### 5.1 メッセージングのリポジショニング（P1）

`docs/product.md` の Vision/Differentiation とユーザーガイドを、オーケストレーションではなく **governance + verification** を前面に出すよう更新する。テーゼ: *コーディング agent が自律的になるほど、価値は「誰がループを回すか」から「誰が要件を捕捉し、変更を gate し、結果を検証し、監査証跡を保つか」へ移る。Wholework はその harness であり、GitHub ネイティブで、あなたのサブスク上で動き、1 フェーズずつ採用できる。* 隣接する第一者オプションとして Managed Agents + Outcomes を名指しし、4 つの持続的差別化要因（§2.3）を明確化する。

### 5.2 選択的・opt-in な Fable 5 採用（P1）

どこでも Fable 5 をデフォルトに **しない**。`run-spec.sh` に `--fable` opt-in を追加する（単一最高レバレッジのフェーズ: 設計品質、long-horizon、エラーが伝播する）。明確なコスト/retention 警告でゲートする。全ての mechanical / 高頻度フェーズは Sonnet/Opus デフォルトを維持する。文書化する: $10/$50 コスト、サブスクでの 2026-06-22 以降の credit ゲート、ZDR 非互換と graceful degrade。ユーザー自身のセッションで inline 動作する `/auto` orchestrator には Fable 5 を推奨する（強制はできない）— long-horizon coherence が最も効く場所だ。

### 5.3 review における find-from-filter 分離（P0）

§4.1 を Fable 5 採用とは独立に出荷する — **今日の Opus 4.8** でリコールを改善する。

### 5.4 Spec-as-memory の強化（P2）

Fable 5 はこのパターンを裏付ける。retrospective 規律を skill 本文で明示する（1 エントリ 1 つの学び、訂正 *も* 確認済みアプローチも記録、関連エントリをリンク、リポが記録するものは重複させない）。`/code` と `/spec` で「開始前に Spec retrospective を参照する」ガイダンスを surface する。

### 5.5 model-effort マトリクス SSoT のリフレッシュ（P1）

`docs/tech.md`（`ssot_for: model-effort-matrix`）は sub-agent の `opus` エイリアスが「Opus 4.7 に auto-resolve」と言う — 古い。Opus 4.8 リリース後、`opus` → 4.8 だ。マトリクスと「Opus 4.7 effort calibration」注記を Opus 4.8 + Fable 5 対応に更新し、Fable 5 行/注記を追加し（opt-in されうる箇所、コスト/retention 制約）、`opus` エイリアスは Fable 5 に **解決しない**（明示的なモデル文字列を要する別ティア）ことを明記する。

## 6. 影響サマリー表

| 領域 | リスク/機会 | 優先度 |
|---|---|---|
| review-bug 自己フィルタ vs literal following | リコール退行（今日の Opus 4.8、Fable 5 でより顕著） | P0 |
| watchdog vs 長い Fable 5 ターン | 1800 秒 kill の誤発火 | P1 |
| メッセージング / ポジショニング | Managed Agents に対する戦略的妥当性 | P1 |
| 選択的 Fable 5 opt-in（spec） | 制御されたコストでの品質向上 | P1 |
| model-effort マトリクス SSoT の陳腐化 | ドキュメントドリフト（opus→4.8） | P1 |
| 自律実行の境界/early-stop | `/auto` 完了信頼性 | P2 |
| プロンプト de-prescription | Fable 5 採用時の品質 | P2 |
| Spec-as-memory 強化 | 推奨パターンと整合 | P2 |
| cyber-classifier fallback 監視 | security-review カバレッジ | P3 |
| 非同期 sub-agent | 将来の multi-agent 方向 | P3 |

## 7. 移行チェックリスト（Wholework 固有）

- [ ] `agents/review-bug.md` / `review-light.md`: find-from-filter 分離（confidence+severity 付きで全件報告、フィルタは downstream）
- [ ] Fable 5 下の `claude-watchdog.sh` の stdout cadence を spike。必要なら `WATCHDOG_TIMEOUT_DEFAULT` 引き上げ かつ/または 進捗 echo 追加
- [ ] `run-spec.sh` 連携前に、Fable 5 の Claude Code CLI `--model` 文字列/エイリアスを確認
- [ ] `run-spec.sh`: コスト/retention 警告付きの `--fable` opt-in を追加。ZDR では graceful degrade
- [ ] `GUARD_PREFIX`: 自律実行向けに anti-early-stop + 境界リマインダを追加
- [ ] `docs/tech.md` model-effort マトリクス: `opus`→4.8、Fable 5 行/注記追加、古い「4.7」auto-resolve 注記を修正
- [ ] `docs/product.md` + ガイド: governance + verification 軸へリポジショニング。Managed Agents/Outcomes を名指し
- [ ] `/code` + `/spec`: 「まず Spec retrospective を参照」する memory-surface ガイダンスを強化
- [ ] `/issue` 11a と `/review` 10 の「(Opus 4.7 may serialize spawns)」根拠を一般化
- [ ] `review-bug` security チェックの cyber-classifier fallback 監視メモを追加

## 8. Candidate Issues（実行計画）

すべて Wholework 標準フォーマット（Background / Purpose / Acceptance Criteria、該当する場合 Pre-merge と Post-merge 分割）に従う。CI/テスト触接項目は Size M 以上（`[[feedback_ci_sensitive_size_m]]`）。

| # | タイトル | 優先度 | 推定 Size | フェーズ影響 |
|---|---|---|---|---|
| C1 | review-bug の find/filter 分離（literal filter-following 対策、Opus 4.8 でも有効） | urgent | M | review |
| C2 | Fable 5 long-turn 対応: watchdog タイムアウト/進捗 echo の spike と再調整 | high | M | auto/code/spec |
| C3 | 自律実行の GUARD_PREFIX に early-stop/boundary リマインダ追加 | high | S | auto, all run-*.sh |
| C4 | docs/tech.md model-effort-matrix を Opus 4.8 / Fable 5 対応で更新 | high | S | docs |
| C5 | run-spec.sh に `--fable` opt-in 追加（コスト/retention 警告付き、ZDR graceful degrade） | high | M | spec |
| C6 | docs/product.md・guide を governance+verification 軸へリポジショニング | high | M | docs |
| C7 | プロンプト de-prescription 監査（reasoning steps のみ、Fable 5 採用時に spike） | medium | M | all skills |
| C8 | Spec-as-memory 強化（retrospective 規律の明示、/code・/spec ガイダンス） | medium | S | code, spec |
| C9 | 並列 spawn 説明の世代非依存化 + cyber-classifier fallback 監視メモ | low | S | issue, review |

### 順序の根拠

- **C1** を最初に、Fable 5 とは独立に出荷する — *今日の* Opus 4.8 にあるリコール退行を修正する。
- **C2, C3** は自律実行の信頼性修正。両方 Sonnet/Opus で無害で、Fable 5 採用前に着地できる。
- **C4, C6** はドキュメント/ポジショニング。C4 は正しいガイダンスをアンブロックし、C6 は戦略的再フレーム。
- **C5** が実際の Fable 5 連携。チェックリストの CLI エイリアス確認に依存。
- **C7** は C5 着地後、あるフェーズで Fable 5 が使われている場合 *のみ* 実施。
- **C8, C9** は低リスクの補強。

## 9. Non-goals

- API レイヤの移行は行わない（コードベースは API ではなく Claude Code CLI を呼ぶ。`refusal`/`fallbacks`/`thinking` の処理は CLI の仕事）。
- Fable 5 への全面モデル差し替えは行わない — コスト、サブスクゲート、ZDR 制約により、デフォルト差し替えは誤りだ。
- フェーズ境界の撤廃は行わない — scaffold 溶解圧力（§2.1）は実在するが governance 価値（§2.2）が上回る。将来の model + 第一者プロダクトが GitHub ネイティブ harness を冗長化した場合にのみ再検討する。
- `ANTHROPIC_MODEL` 環境変数の削除は行わない — CLI `-p` モードの workaround（claude-code#22362）が依然必要。

## 10. 参考

- [Claude Fable 5 と Claude Mythos 5 ローンチ](https://www.anthropic.com/news/claude-fable-5-mythos-5)
- `docs/reports/claude-opus-4-7-optimization-strategy.md`（関連; 旧 model の再調整）
- `docs/reports/sonnet-effort-recalibration.md`, `task-budgets-spike.md`, `ultrareview-spike.md`, `watchdog-recovery-strategy.md`
- `docs/tech.md` §Architecture Decisions（model-effort-matrix の SSoT）
- `docs/product.md` §Vision / §Differentiation / §Future Direction

---

*本レポートは §8 の Issue を提案する。各 Issue は適切な `phase/*` ラベルを付与し、Wholework GitHub Project で Priority を設定して Wholework GitHub リポジトリに作成されることを想定する。*
