# Codex 管理ポリシー設計メモ

## 方針

- 管理画面には `requirements.toml` 互換の payload だけを登録する。
- ユーザー側の `config.toml`、プロジェクト設定、ユーザー hooks、ユーザー MCP は信頼しない。
- 既定プロファイルは `company_workspace` とし、Workspace 内の編集だけを許可する。
- `approval_policy = never` 相当の運用は禁止し、承認が必要な操作ではユーザー確認を求める `on-request` だけを許可する。
- Web search は `cached` のみ許可する。`disabled` は Codex 側で常に許可されるため、ユーザーが検索を無効化することは許容される。
- MCP は空の allowlist から開始し、必要なものだけ管理者が正確な identity 付きで追加する。
- Hooks は managed hooks のみ許可し、ユーザー、プロジェクト、セッション、plugin hooks は無効化する。
- 共有フォルダは個別サーバー名ではなく、UNC 汎用パターン `\\*\*` と `\\*\*\**` で防御的に拒否する。
- mapped drive は TOML だけではネットワーク共有かローカルディスクかを判定できないため、共有ドライブに使われやすい `H:\` から `Z:\` をまとめて拒否する。

## 重要な制限

- `requirements.toml` は Codex の sandbox と command 実行を制御するもので、Windows の共有フォルダそのものを物理的に read-only にするものではない。
- 共有フォルダへの「物理的な書き込み禁止」は、共有フォルダ側の ACL、GPO、Intune、ファイルサーバー権限で実施する必要がある。
- `on-request` は sandbox 内の全操作を毎回承認させる設定ではない。今回の設定では、shell entrypoint は command rules で prompt させる。
- 共有フォルダを Workspace として選択する UI 操作を、`requirements.toml` の標準キーだけで完全に禁止する専用設定は見当たらない。
- `permissions.filesystem.deny_read` は読み取り拒否であり、書き込みの物理禁止ではない。
- UNC 形式の共有フォルダはワイルドカード deny と `deny_read` で Codex 側のアクセスを防御的に制限する。mapped drive は拒否対象のドライブ文字に含まれる場合に制限できる。
- 共有フォルダ Workspace を選択時点で確実に拒否するには、Windows 側で該当パスを権限上使えなくするか、MDM 配布の managed SessionStart hook で UNC path / mapped drive を検出して停止する運用が必要。
- 現在の TOML は `allow_managed_hooks_only = true` で非管理 hooks を止めるが、Workspace path 検査用の managed hook 定義やスクリプトは含めていない。
- `allowed_sandbox_modes = ["read-only"]` は旧クライアント向けの fail-closed 設定。編集を許可する運用は Codex 0.138.0 以降にそろえてから行う。

## 導入手順

1. `requirements.company-codex-policy.toml` の mapped drive 拒否範囲 `H:\` から `Z:\` が社内のドライブ運用と合っているか確認する。
2. TOML を管理画面 `https://chatgpt.com/codex/cloud/settings/policies` に登録する。
3. 管理対象 PC の Codex を再起動し、起動時の managed requirements summary を確認する。
4. テスト用ユーザーで以下を確認する。
   - `approval_policy = never` を選べない。
   - `:danger-full-access` を選べない。
   - Live web search を選べない。
   - ユーザー定義 MCP が起動しない。
   - ユーザー、プロジェクト、plugin hooks が実行されない。
   - Workspace 外への書き込みが失敗する。
   - 共有フォルダの direct path 書き込みが失敗する。
   - 旧クライアントでは read-only に落ちる。
