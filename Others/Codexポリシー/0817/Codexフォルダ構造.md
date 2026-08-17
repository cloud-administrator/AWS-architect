```text
【1. Codex CLI】

%USERPROFILE%\.codex\
└─ packages\
   └─ standalone\
      ├─ releases\
      │  └─ <Codex CLIバージョン>-<Windowsターゲット>\
      │     │
      │     ├─ bin\
      │     │  ├─ codex.exe
      │     │  │   └─ ★ Codex CLI本体
      │     │  │
      │     │  └─ codex-code-mode-host.exe
      │     │      └─ Code Mode用補助実行ファイル
      │     │
      │     ├─ codex-resources\
      │     │  ├─ codex-windows-sandbox-setup.exe
      │     │  │   └─ ★ Codex CLI用Windowsサンドボックス設定
      │     │  │
      │     │  └─ codex-command-runner.exe
      │     │      └─ サンドボックス内コマンド実行用
      │     │
      │     ├─ codex-path\
      │     │  └─ rg.exe
      │     │      └─ ファイル検索用
      │     │
      │     └─ codex-package.json
      │
      ├─ current
      │  └─ 現在使用するreleasesフォルダーへのリンク
      │
      └─ install.lock


【Codex CLIの現在使用中の実行ファイル】

%USERPROFILE%\.codex\
└─ packages\
   └─ standalone\
      └─ current\
         ├─ bin\
         │  ├─ codex.exe
         │  │   └─ ★ Codex CLI本体
         │  │
         │  └─ codex-code-mode-host.exe
         │
         ├─ codex-resources\
         │  ├─ codex-windows-sandbox-setup.exe
         │  │   └─ ★ Codex CLI用Windowsサンドボックス設定
         │  │
         │  └─ codex-command-runner.exe
         │
         └─ codex-path\
            └─ rg.exe


【Codex CLIのコマンド入口】

%LOCALAPPDATA%\
└─ Programs\
   └─ OpenAI\
      └─ Codex\
         └─ bin\
            ├─ codex.exe
            │   └─ ★ codexコマンドから起動される入口
            │
            └─ codex-code-mode-host.exe

            ※ このbinフォルダーは通常、
               %USERPROFILE%\.codex\packages\standalone\current\bin
               を参照するリンク／ジャンクション
```

```text
【2. VS Code拡張機能】

%USERPROFILE%\.vscode\
└─ extensions\
   └─ openai.chatgpt-<拡張機能バージョン>-win32-<CPU>\
      │
      ├─ package.json
      ├─ extension関連ファイル
      │
      └─ bin\
         └─ windows-<CPU>\
            ├─ codex.exe
            │   └─ ★ VS Code拡張機能が使用するCodex本体
            │
            ├─ codex-windows-sandbox-setup.exe
            │   └─ ★ VS Code拡張機能用Windowsサンドボックス設定
            │
            ├─ codex-command-runner.exe
            │   └─ サンドボックス内コマンド実行用
            │
            └─ rg.exe
                └─ ファイル検索用


【Windows x64の場合のパス形式】

%USERPROFILE%\.vscode\
└─ extensions\
   └─ openai.chatgpt-<拡張機能バージョン>-win32-x64\
      └─ bin\
         └─ windows-x86_64\
            ├─ codex.exe
            │   └─ ★ VS Code拡張機能のCodex本体
            │
            ├─ codex-windows-sandbox-setup.exe
            │   └─ ★ VS Code拡張機能用
            │
            ├─ codex-command-runner.exe
            └─ rg.exe
```

```text
【3. ChatGPTデスクトップアプリ】

<ChatGPTデスクトップアプリのInstallLocation>\
└─ app\
   └─ resources\
      ├─ codex.exe
      │   └─ ★ ChatGPTデスクトップアプリが使用するCodex本体
      │
      ├─ codex-windows-sandbox-setup.exe
      │   └─ ★ ChatGPTデスクトップアプリ用Windowsサンドボックス設定
      │
      ├─ codex-command-runner.exe
      │   └─ 存在する場合：サンドボックス内コマンド実行用
      │
      └─ その他のChatGPT／Codexリソース


【通常のMSIXインストール場所の形式】

C:\Program Files\
└─ WindowsApps\
   └─ OpenAI.Codex_<アプリバージョン>_<CPU>__<発行元ID>\
      └─ app\
         └─ resources\
            ├─ codex.exe
            │   └─ ★ ChatGPTデスクトップアプリのCodex本体
            │
            ├─ codex-windows-sandbox-setup.exe
            │   └─ ★ ChatGPTデスクトップアプリ用
            │
            └─ codex-command-runner.exe
                └─ 存在する場合


【ChatGPTデスクトップアプリの追加ランタイム／キャッシュ】

%LOCALAPPDATA%\
└─ OpenAI\
   └─ Codex\
      └─ bin\
         ├─ <ハッシュ値1>\
         │  ├─ codex.exe
         │  │   └─ ★ ChatGPTアプリが展開したCodex実行ファイル
         │  │
         │  ├─ codex-windows-sandbox-setup.exe
         │  │   └─ ★ 追加ランタイム用
         │  │
         │  └─ codex-command-runner.exe
         │
         └─ <ハッシュ値2>\
            ├─ codex.exe
            ├─ codex-windows-sandbox-setup.exe
            └─ codex-command-runner.exe

            ※ ハッシュ値はアプリ更新などで変化する可能性あり
```

```text
【4. 3種類が主に使用するCodex共通状態フォルダー】

%USERPROFILE%\
└─ .codex\
   ├─ config.toml
   │   └─ ★ Codex共通設定・MCP設定
   │
   ├─ auth.json
   │   └─ 認証情報をファイル保存する設定の場合
   │
   ├─ history.jsonl
   │   └─ ローカル履歴が有効な場合
   │
   ├─ sessions\
   │   └─ ローカルセッション・会話データ
   │
   ├─ logs\
   │   └─ Codexログ
   │
   ├─ skills\
   │   └─ Codexスキル
   │
   ├─ state_5.sqlite
   │   └─ Codexの主要状態
   │
   ├─ logs_2.sqlite
   │   └─ ログデータベース
   │
   ├─ goals_1.sqlite
   │   └─ ゴール情報
   │
   ├─ memories_1.sqlite
   │   └─ メモリー情報
   │
   ├─ queue_1.sqlite
   │   └─ メッセージキュー
   │
   ├─ thread_history_1.sqlite
   │   └─ スレッド履歴
   │
   └─ packages\
      └─ standalone\
         └─ ★ このサブフォルダーだけはCodex CLI本体用
```

```text
【5. VS Code専用設定フォルダー】

%APPDATA%\
└─ Code\
   └─ User\
      ├─ settings.json
      │   └─ ★ VS Code／Codex拡張機能固有設定
      │
      ├─ globalStorage\
      │   └─ VS Code拡張機能の状態保存領域
      │
      └─ profiles\
         └─ <VS CodeプロファイルID>\
            └─ settings.json


【プロジェクト単位のVS Code設定】

<プロジェクトフォルダー>\
└─ .vscode\
   └─ settings.json
       └─ ★ プロジェクト単位のVS Code設定
```

```text
【6. ChatGPTデスクトップアプリ専用データフォルダー】

%LOCALAPPDATA%\
└─ Packages\
   └─ <ChatGPTのPackageFamilyName>\
      ├─ LocalState\
      │   └─ ChatGPTアプリ固有の永続データ
      │
      ├─ LocalCache\
      │   └─ ChatGPTアプリ固有のキャッシュ
      │
      ├─ RoamingState\
      │   └─ ローミング対象データ
      │
      ├─ TempState\
      │   └─ 一時データ
      │
      └─ Settings\
          └─ MSIXアプリ設定
```

```text
【7. 3種類のCodex本体の比較】

Codex CLI
│
└─ %USERPROFILE%\.codex\packages\standalone\current\
   └─ bin\
      └─ codex.exe
          └─ ★ Codex CLI本体


VS Code拡張機能
│
└─ %USERPROFILE%\.vscode\extensions\
   └─ openai.chatgpt-<バージョン>-win32-<CPU>\
      └─ bin\
         └─ windows-<CPU>\
            └─ codex.exe
                └─ ★ VS Code拡張機能のCodex本体


ChatGPTデスクトップアプリ
│
└─ <ChatGPTアプリのInstallLocation>\
   └─ app\
      └─ resources\
         └─ codex.exe
             └─ ★ ChatGPTデスクトップアプリのCodex本体
```

```text
【8. 3種類のcodex-windows-sandbox-setup.exeの比較】

Codex CLI
│
└─ %USERPROFILE%\.codex\packages\standalone\current\
   └─ codex-resources\
      └─ codex-windows-sandbox-setup.exe
          └─ ★ Codex CLI用


VS Code拡張機能
│
└─ %USERPROFILE%\.vscode\extensions\
   └─ openai.chatgpt-<バージョン>-win32-<CPU>\
      └─ bin\
         └─ windows-<CPU>\
            └─ codex-windows-sandbox-setup.exe
                └─ ★ VS Code拡張機能用


ChatGPTデスクトップアプリ
│
└─ <ChatGPTアプリのInstallLocation>\
   └─ app\
      └─ resources\
         └─ codex-windows-sandbox-setup.exe
             └─ ★ ChatGPTデスクトップアプリ用


ChatGPTデスクトップアプリの追加ランタイムがある場合
│
└─ %LOCALAPPDATA%\OpenAI\Codex\
   └─ bin\
      └─ <ハッシュ値>\
         └─ codex-windows-sandbox-setup.exe
             └─ ★ ChatGPTアプリの追加ランタイム用
```

```text
【9. 全体構成】

Windows PC
│
├─ Codex CLI専用
│  │
│  ├─ %USERPROFILE%\.codex\packages\standalone\
│  │  ├─ releases\
│  │  ├─ current\
│  │  │  ├─ bin\
│  │  │  │  └─ codex.exe
│  │  │  └─ codex-resources\
│  │  │     └─ codex-windows-sandbox-setup.exe
│  │  └─ install.lock
│  │
│  └─ %LOCALAPPDATA%\Programs\OpenAI\Codex\bin\
│     └─ codex.exe
│
├─ VS Code拡張機能専用
│  │
│  └─ %USERPROFILE%\.vscode\extensions\
│     └─ openai.chatgpt-<バージョン>-win32-<CPU>\
│        └─ bin\
│           └─ windows-<CPU>\
│              ├─ codex.exe
│              └─ codex-windows-sandbox-setup.exe
│
├─ ChatGPTデスクトップアプリ専用
│  │
│  ├─ <InstallLocation>\
│  │  └─ app\
│  │     └─ resources\
│  │        ├─ codex.exe
│  │        └─ codex-windows-sandbox-setup.exe
│  │
│  ├─ %LOCALAPPDATA%\OpenAI\Codex\bin\
│  │  └─ <ハッシュ値>\
│  │     ├─ codex.exe
│  │     └─ codex-windows-sandbox-setup.exe
│  │
│  └─ %LOCALAPPDATA%\Packages\<PackageFamilyName>\
│     ├─ LocalState\
│     └─ LocalCache\
│
└─ Codex共通状態
   │
   └─ %USERPROFILE%\.codex\
      ├─ config.toml
      ├─ sessions\
      ├─ logs\
      ├─ skills\
      ├─ state_5.sqlite
      ├─ logs_2.sqlite
      ├─ goals_1.sqlite
      ├─ memories_1.sqlite
      ├─ queue_1.sqlite
      └─ thread_history_1.sqlite
```
