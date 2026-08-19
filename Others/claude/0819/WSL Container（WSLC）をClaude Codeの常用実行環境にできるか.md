結論として、**今回の用途なら WSL2 を推奨します。WSL Container（WSLC）をClaude Codeの常用実行環境にするメリットは、現時点ではあまりありません。**

特に、

* Windows PCでClaude Codeを日常的に使用
* Claude Enterpriseで認証
* 「Admin Settings → Claude Code → Managed settings」からJSONを配布
* 開発者側で設定を勝手に緩めにくくしたい
* Claude Codeの実行範囲も制限したい

という要件なら、**Windows + WSL2 + Claude Code + server-managed settings + Claude Code Sandbox** が一番素直です。Anthropic自身もWindows上でClaude CodeをWSL内にインストールして使う方法を正式に案内しており、Claude Codeの組み込みSandboxもWSL2を正式サポートしています。([Claude][1])

## 比較するとこうなります

| 項目                          | WSL2           | WSL Container（WSLC）  |
| --------------------------- | -------------- | -------------------- |
| Claude Codeの日常利用            | **◎ 推奨**       | △                    |
| Anthropic公式のWindows利用方法     | **○ 明示的に対応**   | WSLC固有の手順は見当たらない     |
| Enterprise Managed settings | **◎**          | ○ 原理上利用可能            |
| 組織OAuthログイン                 | **◎ 簡単**       | ○ コンテナ内で認証が必要        |
| 設定・認証の永続化                   | **◎ 自然**       | △ Volume等の設計が必要      |
| Claude Code Sandbox         | **◎ WSL2正式対応** | Linuxコンテナとして別途考慮     |
| プロジェクト分離                    | ○              | **◎**                |
| 環境の再現性                      | ○              | **◎**                |
| 運用の簡単さ                      | **◎**          | △                    |
| 現時点の成熟度                     | **◎**          | △ WSLC自体がpre-release |
| Enterprise PCへの標準展開         | **◎**          | △                    |
| 今回のおすすめ                     | **★★★★★**      | ★★☆☆☆                |

WSLC自体もLinuxコンテナーを実行できますが、2026年8月19日時点ではWSL 2.9.3以上のpre-releaseが必要です。([Microsoft Learn][2]) Anthropicはコンテナー内でClaude Codeを実行する方法を正式に用意していますが、現在の公式Dev ContainerガイドはDockerベースです。WSLC固有のClaude Code運用手順は、公式資料では確認できませんでした。([Claude][3])

---

# 今回、特に重要なポイント

ご質問にある

> 組織設定 ＞ Claude Code ＞ 管理された設定

は、Anthropicのドキュメント上では **Server-managed settings** です。

つまり、管理者画面に入力したJSONを、社員PCへファイルとしてコピーする仕組みではありません。

イメージはこうです。

```text
Claude Enterprise
┌──────────────────────────────┐
│ Admin Settings               │
│   ↓                          │
│ Claude Code                  │
│   ↓                          │
│ Managed settings             │
│                              │
│ {                            │
│   "permissions": {...},      │
│   "sandbox": {...}           │
│ }                            │
└──────────────┬───────────────┘
               │
               │ Anthropicから配信
               ↓
Windows
└─ WSL2 Ubuntu
     │
     ├─ Claude Code
     │    ↓
     │  Enterprise OAuth Login
     │    ↓
     │  Managed settings取得
     │
     └─ ソースコード
          ~/src/project
```

Claude Codeが組織OAuthで認証すると、AnthropicのサーバーからManaged settingsを自動取得します。設定は起動時に取得され、実行中も定期的に更新されます。([code.claude.com][4])

したがって、**WSL2だから管理設定を手動で`/etc/...`にコピーしなければならない、ということではありません。**

---

# WSL2で問題なくManaged settingsを使えます

例えば管理者がClaude Enterprise側に、

```json
{
  "permissions": {
    "deny": [
      "Bash(curl *)",
      "Read(./.env)",
      "Read(./secrets/**)"
    ],
    "disableBypassPermissionsMode": "disable"
  },
  "allowManagedPermissionRulesOnly": true
}
```

のような設定を登録すると、組織アカウントで認証したClaude Codeに配信できます。Server-managed settingsは通常のユーザー設定やプロジェクト設定より上位に位置し、一般のユーザー設定から上書きできません。([Claude][4])

確認するときはWSL内のClaude Codeで、

```text
/status
```

を実行します。

正常に配信されていれば、

```text
Enterprise managed settings (remote)
```

のように表示されます。([Claude Platform Docs][5])

これはEnterprise展開時にかなり重要な確認方法です。

---

# WSL2を推す最大の理由：Claude Code Sandbox

企業でClaude Codeを使うなら、ここがWSL2の大きな利点です。

Claude Codeには現在、BashコマンドをOSレベルで制限するSandboxがあります。

**SandboxはLinux、macOS、WSL2をサポートしていますが、ネイティブWindowsではサポートされていません。** AnthropicもWindowsでSandboxを使う場合はWSL2内でClaude Codeを実行するよう案内しています。([code.claude.com][6])

つまり、

```text
Windows
    ↓
WSL2
    ↓
Claude Code
    ↓
Claude Code Sandbox
    ↓
bash / npm / python / git ...
```

とできます。

さらに、これをEnterprise Managed settingsから強制できます。

例えばAnthropic公式が示している構成は次の形です。([code.claude.com][6])

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false
  }
}
```

意味はかなり重要です。

| 設定                                | 意味                               |
| --------------------------------- | -------------------------------- |
| `enabled: true`                   | Sandboxを有効化                      |
| `failIfUnavailable: true`         | Sandboxが動かなければClaude Codeの起動を止める |
| `allowUnsandboxedCommands: false` | ClaudeがSandbox外でコマンドを再実行することを禁止  |

つまり、

```text
Sandboxが使える
     ↓
Claude Code起動 OK

Sandboxが壊れている
     ↓
Claude Code起動 NG
```

という運用にできます。Enterprise用途ではかなり相性が良い構成です。([code.claude.com][6])

---

# 私ならこういう構成にします

今回の要件なら、まずこの構成をベースにします。

```text
┌──────────────────────────────┐
│ Windows 11 Enterprise        │
│                              │
│ Intune / Defender / EDR      │
│                              │
│ ┌──────────────────────────┐ │
│ │ WSL2 Ubuntu             │ │
│ │                         │ │
│ │ Claude Code             │ │
│ │    │                    │ │
│ │    ├─ Managed settings  │ │
│ │    │     ↑              │ │
│ │    │ Claude Enterprise  │ │
│ │    │                    │ │
│ │    ├─ Claude Sandbox    │ │
│ │    │                    │ │
│ │    └─ ~/src/project     │ │
│ │                         │ │
│ │ git / node / python etc │ │
│ └──────────────────────────┘ │
│                              │
└──────────────────────────────┘
```

**WSLCはこの構成の外側で、必要に応じてアプリのコンテナー実行に使う**方がきれいです。

例えば、

```text
WSL2
│
├─ Claude Code ← ここでClaudeを動かす
│
├─ git
├─ node
├─ python
│
└─ wslc
     ├─ PostgreSQL container
     ├─ Redis container
     └─ App container
```

という役割分担です。

要するに、

> **Claude CodeそのものをWSLCに閉じ込めるのではなく、Claude CodeはWSL2で動かし、Claudeが開発・テストするアプリをコンテナー化する**

という構成を第一候補にします。

---

# WSLCにClaude Codeを入れると何が面倒になるか

もちろんコンテナー内にClaude Codeを入れること自体は可能な方向性です。AnthropicもDev Container内でClaude Codeを使う構成を正式にサポートしています。([Claude][3])

ただし、コンテナーにすると認証情報の永続化を考えなければなりません。

Claude Codeは、

```text
~/.claude
~/.claude.json
```

などに認証・設定・セッション情報を保持します。

コンテナーを再構築するとホームディレクトリが消えるので、そのままだと再ログインが必要になります。Anthropic公式も、Dev Containerでは`~/.claude`をVolume化し、`CLAUDE_CONFIG_DIR`を設定する方式を案内しています。([Claude][3])

つまりWSLCにClaude Codeを入れるなら、

```text
WSLC container
│
├─ Claude Code
├─ OAuth認証
├─ ~/.claude
├─ ~/.claude.json
│
└─ Volumeによる永続化
```

などを設計する必要があります。

WSL2ならこの手間がほぼありません。

---

# ただし「Managed settingsだけで絶対に改ざん不能」ではありません

Enterprise管理では、ここは知っておいた方がよいです。

AnthropicはServer-managed settingsについて、**クライアント側の制御であり、それ自体が完全なsecurity boundaryではない**と明記しています。例えばユーザーが改造版Claude Codeを実行したり、古いバージョンを実行したり、別組織で認証したりすると、Server-managed settingsを回避できるケースがあります。([code.claude.com][4])

そのため、

```text
「普通の社員が設定を書き換えられないようにする」
```

程度ならServer-managed settingsだけでも非常に有用ですが、

```text
「セキュリティポリシーとして必ず強制する」
```

のであれば、

**Server-managed settings + Endpoint-managed settings**

を組み合わせて考える方がよいです。AnthropicもMDM管理下の端末ではEndpoint-managed settingsの方が強いセキュリティ保証を提供すると説明しています。([code.claude.com][4])

---

# Windows + WSL2ならさらに強くできます

Claude Codeには現在、

```text
wslInheritsWindowsSettings
```

というEnterprise向け設定もあります。

これを使うと、WSL内のClaude CodeがWindows側の、

```text
HKLM\SOFTWARE\Policies\ClaudeCode
```

や

```text
C:\Program Files\ClaudeCode\managed-settings.json
```

の管理ポリシーを参照できます。([Claude][7])

つまり将来的には、

```text
Intune
  ↓
Windows HKLM Policy
  ↓
WSL2
  ↓
Claude Code
```

という企業管理も可能です。

ただし重要なのは、**`wslInheritsWindowsSettings`自体はclaude.aiのServer-managed settingsから設定できません。** OSレベルのHKLMまたは管理ファイルから設定する必要があります。([Claude][8])

---

# Enterpriseなら `forceRemoteSettingsRefresh` も検討

もう一つおすすめしたいのが、

```json
{
  "forceRemoteSettingsRefresh": true
}
```

です。

通常、初回起動時にAnthropicからManaged settingsを取得できなかった場合、Claude CodeがManaged settingsなしで起動する短いウィンドウが存在し得ます。`forceRemoteSettingsRefresh: true`を有効にすると、新しいManaged settingsを取得できなければClaude Codeを起動させない「fail-closed」にできます。([code.claude.com][4])

したがって企業管理なら、

```json
{
  "forceRemoteSettingsRefresh": true,

  "permissions": {
    "disableBypassPermissionsMode": "disable"
  },

  "allowManagedPermissionRulesOnly": true,

  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false
  }
}
```

のような思想で設計するのはかなり合理的です。各キーはAnthropicのServer-managed settingsおよびSandboxの公式仕様に基づくものです。([Claude][4])

---

## 最終的なおすすめ

今回の要件なら、優先順位はこうします。

**第1候補**

```text
Windows 11
  ↓
WSL2 Ubuntu
  ↓
Claude Code
  ↓
Claude Enterprise OAuth
  ↓
Server-managed settings
  ↓
Claude Code Sandbox
```

**さらにセキュリティを強くするなら**

```text
Windows 11
  │
  ├─ Intune / HKLM Policy
  │
  └─ WSL2 Ubuntu
        ↓
      Claude Code
        ├─ Server-managed settings
        ├─ Endpoint-managed settings
        └─ Sandbox
```

**WSLCは**

```text
Claude Codeの実行環境
```

として最初から採用するのではなく、

```text
Claude Codeが操作する
開発・テスト用コンテナー
```

として利用する方を推奨します。

一点だけ注意すると、Claude CodeのWSL2 Sandboxを厳格に有効にすると、`powershell.exe`、`cmd.exe`、`/mnt/c/...`上のWindowsバイナリなどをSandbox内から直接起動できません。Windows固有のVisual Studio/MSBuild等をClaudeに操作させたい場合は、別の設計が必要です。([code.claude.com][6])

必要であれば次に、**「Windows 11 + WSL2 + Claude Enterpriseを全社展開する場合の推奨構成」**として、①WSL2構築、②Claude Codeインストール、③Enterpriseログイン、④Managed `settings.json`、⑤Sandbox、⑥MCP制限、⑦ネットワーク制限、⑧Intuneまで含めた具体的な構成図と設定例を作れます。

[1]: https://code.claude.com/docs/ja/setup "高度なセットアップ - Claude Code Docs"
[2]: https://learn.microsoft.com/en-us/windows/wsl/wsl-container "WSL container | Microsoft Learn"
[3]: https://code.claude.com/docs/en/devcontainer "Development containers - Claude Code Docs"
[4]: https://code.claude.com/docs/en/server-managed-settings "Configure server-managed settings - Claude Code Docs"
[5]: https://docs.anthropic.com/en/docs/claude-code/settings "Claude Code settings - Claude Code Docs"
[6]: https://code.claude.com/docs/ja/sandboxing "サンドボックス化された Bash ツールを設定する - Claude Code Docs"
[7]: https://code.claude.com/docs/en/settings?utm_source=chatgpt.com "Claude Code settings - Claude Code Docs"
[8]: https://code.claude.com/docs/en/server-managed-settings?utm_source=chatgpt.com "Configure server-managed settings - Claude Code Docs"
