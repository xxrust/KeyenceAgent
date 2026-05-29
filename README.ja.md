# KeyenceAgent

<p align="center">
  <img src="docs/images/keyenceagent-harness-overview.png" alt="KeyenceAgent アーキテクチャ概要">
</p>

<p align="center">
  <a href="https://github.com/xxrust/KeyenceAgent/commits/master"><img alt="Latest commit" src="https://img.shields.io/github/last-commit/xxrust/KeyenceAgent?style=flat-square&logo=git"></a>
  <a href="https://github.com/xxrust/KeyenceAgent"><img alt="Repository size" src="https://img.shields.io/github/repo-size/xxrust/KeyenceAgent?style=flat-square"></a>
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell&logoColor=white">
  <img alt="KV STUDIO" src="https://img.shields.io/badge/KV%20STUDIO-script--owned-008C95?style=flat-square">
  <img alt="MVP" src="https://img.shields.io/badge/MVP-3x%20repeat%20passed-22A06B?style=flat-square">
  <img alt="UI guard" src="https://img.shields.io/badge/UI%20guard-shared%20library-0B5FFF?style=flat-square">
</p>

<p align="center">
  <a href="README.md"><img alt="English" src="https://img.shields.io/badge/English-0B5FFF?style=for-the-badge"></a>
  <a href="README.zh-CN.md"><img alt="中文" src="https://img.shields.io/badge/%E4%B8%AD%E6%96%87-008C95?style=for-the-badge"></a>
  <a href="README.ja.md"><img alt="日本語" src="https://img.shields.io/badge/%E6%97%A5%E6%9C%AC%E8%AA%9E-22A06B?style=for-the-badge"></a>
</p>

KeyenceAgent は、KEYENCE KV STUDIO の PLC プロジェクトをエージェント支援で作成、更新、検証するためのスクリプト所有ハーネスです。

エージェントは意図の準備と証拠の確認を担当します。KV STUDIO が開いている間の操作は、プロジェクト作成から変換結果の取得まで runner スクリプトが担当します。

## アーキテクチャ

KeyenceAgent は、推論、実行、検証を明確な境界に分けます。

```text
タスク要求
  -> scaffold model
  -> scaffold renderer
  -> static gates
  -> guarded KV runner
  -> same-run artifacts
  -> agent verification
```

| レイヤー | 責務 | 主な成果物 |
| --- | --- | --- |
| Scaffold model | モジュール、MNM、変数、FB 引数、プロジェクト情報、受け入れ条件を記述します。 | `scaffold.model.json`, `TASK.md`, `VERSION.md` |
| Renderer | 構造化モデルを KV STUDIO 用のインポートファイルへ変換します。 | `mnm/*.mnm`, `variables/<module>/*.tsv`, `scaffold.json` |
| Static gates | KV STUDIO を開く前に、不完全または危険な入力を拒否します。 | checklist, variable validation, import plan, scaffold validation |
| Guarded runner | プロジェクト作成またはオープン、MNM インポート、変数入力、FB 引数入力、コンパイル、結果取得を実行します。 | `mvp_result.json`, `repair_result.json`, `artifacts/` |
| Route governance | キーボード、UIA、マウス、スクリプト戦略の無根拠な切り替えを防ぎます。 | `route-state.json` |

## コアメカニズム

KeyenceAgent は強い実行契約を使います。

| フェーズ | 所有者 | 契約 |
| --- | --- | --- |
| KV STUDIO を開く前 | エージェント | scaffold を編集し、検証ゲートを通してから runner を 1 回起動します。 |
| KV STUDIO が開いている間 | スクリプト | 共有 UI guard でフォーカス、キー入力、マウス入力、貼り付け、モーダル検出、失敗境界を制御します。 |
| runner 終了後 | エージェント | 同一実行の artifacts だけを読み、結果 JSON と KV STUDIO テキストから次の変更を判断します。 |

この契約は、デスクトップ IDE 自動化の主要な失敗を制御します。つまり、エージェントがライブ UI を見ながら即興で操作し、古いエラーを新しい操作へ誤って帰因する状態を避けます。

## 現在の機能

| 機能 | 状態 |
| --- | --- |
| 新規プロジェクト作成 | repeat runner で検証済み。 |
| 複数 MNM インポート | 複数モジュールとモジュール別変数ファイルに対応。 |
| グローバル変数とローカル変数の再構築 | 貼り付け前に検証し、runner 証拠で確認。 |
| 既存プロジェクト更新 | `.kpr` を変更する前に snapshot gate と import-plan gate を使用。 |
| コンパイル結果取得 | 結果ツリーのテキストを `compile_result_copied.txt` に保存し、クリップボードは補助証拠として扱います。 |
| ファンクションブロック作成 | `MODULE_TYPE:2` の MNM をユーザー FB としてインポート。 |
| FB 引数テーブル | 必須列の入力を guarded runner で検証済み。 |
| FB インスタンスと呼び出し | コンパイル可能な平滑フィルタ FB プロジェクトで検証済み。 |
| 再現性ゲート | 連続成功を要求し、最新 FB MVP は 3 回連続で成功。 |

## Runner フロー

<p align="center">
  <img src="docs/images/kv-repair-loop.png" alt="決定的な KV STUDIO runner ループ">
</p>

1. scaffold model を作成または更新します。
2. MNM と変数アダプターファイルを生成します。
3. KV STUDIO を開く前に静的ゲートを実行します。
4. 新規プロジェクトは `run_kv_mvp_scaffold.ps1`、既存プロジェクトは `run_kv_mvp_repair_existing_project.ps1` を使います。
5. 最初の子ステップ失敗で停止し、同一実行の artifact ディレクトリを確認します。
6. 成功判定は結果 JSON と変換結果テキストで行います。
7. `run_kv_mvp_repeat.ps1` で安定性を証明します。

## リポジトリ構成

```text
.
|-- README.md
|-- README.zh-CN.md
|-- README.ja.md
|-- docs/
|   `-- images/
|-- kv-studio-operator/
|   |-- SKILL.md
|   |-- references/
|   `-- scripts/
|       |-- run_kv_mvp_scaffold.ps1
|       |-- run_kv_mvp_repair_existing_project.ps1
|       |-- run_kv_mvp_repeat.ps1
|       `-- mvp/
|-- keyence-plc-programmer/
`-- route-governance/
```

## 主要スクリプト

| スクリプト | 用途 |
| --- | --- |
| `kv-studio-operator/scripts/render_kv_mvp_scaffold_model.ps1` | 構造化プロジェクトモデルを MNM と変数ファイルへ変換します。 |
| `kv-studio-operator/scripts/validate_kv_mvp_scaffold.ps1` | checklist、schema、module type、変数、FB 宣言、scaffold 整合性を検証します。 |
| `kv-studio-operator/scripts/assert_kv_mnm_import_plan.ps1` | 同名 MNM をインポートする前に、明示的な事前削除計画を要求します。 |
| `kv-studio-operator/scripts/run_kv_mvp_scaffold.ps1` | 新規 KV STUDIO プロジェクトを作成し、MVP 全体を実行します。 |
| `kv-studio-operator/scripts/run_kv_mvp_repair_existing_project.ps1` | snapshot gate を通したうえで scaffold 更新を既存プロジェクトへ適用します。 |
| `kv-studio-operator/scripts/run_kv_mvp_repeat.ps1` | 連続成功ゲートを実行します。 |
| `kv-studio-operator/scripts/mvp/kv_ui_guard.ps1` | すべての KV UI 子スクリプトが共有するフォーカス、モーダル、キーボード、マウス、クリップボード保護ライブラリです。 |

## 検証証拠

最新の FB MVP は次の経路を完了しました。

```text
FB MNM import
-> scan module MNM import
-> FB argument table paste
-> global/local variable paste
-> compile
-> result-tree text capture
-> baseline snapshot write
```

最新 repeat gate:

```text
required_consecutive_passes: 3
attempts_completed: 3
consecutive_passes: 3
status: pass
```

コンパイル oracle は同一実行の KV STUDIO 結果テキストです。

```text
Conversion result OK
error count: 0
warning count: 0
```

## 設計原則

| 原則 | 意味 |
| --- | --- |
| Harness first | 手作業で成功したルートは、skill の約束になる前にスクリプト所有ハーネスになります。 |
| Checklist before UI | checklist がない場合、KV STUDIO スクリプトは即座に失敗します。 |
| Same-run evidence | 古いスクリーンショット、ログ、プロジェクト状態は成功証明になりません。 |
| Shared UI guard | フォーカスとモーダル処理は各スクリプトの局所修正ではなく共有ライブラリに置きます。 |
| Fileized oracles | コンパイル結果と貼り付け結果は、エージェントが判断する前に artifact として保存されます。 |
| Route governance | ルート変更には失敗メカニズムと新しい制御手段の証拠が必要です。 |

## ロードマップ

| 領域 | 計画 |
| --- | --- |
| Function blocks | フォーマット probe で安定性を確認した後、FB 引数コメントと任意列へ対応します。 |
| Existing projects | harness で作成されていないプロジェクト向けに、より強い export/import snapshot ループを完成させます。 |
| Module categories | standby module と interrupt program の検証済み対応を追加します。 |
| FB composition | ネストした FB インスタンス、複数呼び出し点、インスタンススコープ監査を扱います。 |
| Speed | bounded failure の性質を維持しながら不要な待機を削減します。 |
| Sub-agent validation | 独立したサブエージェントが skill だけで同じ MVP を連続成功させる検証を追加します。 |
| Documentation | アーキテクチャ図、失敗分類、runner contract の例を追加します。 |

