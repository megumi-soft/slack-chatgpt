# Slack ChatGPT Bot

このリポジトリは、Slack上でChatGPTと会話できるBotをGoogle Cloud Functionsを使用して構築したものです。@ChatGPTでスレッド上で会話を開始し、ChatGPTの応答を受け取ることができます。

## 特徴

- Google Cloud Functions上で動作
- Slack上でのスレッド形式の会話をサポート
- 環境変数でAPIキーなどの情報を管理
- DBは不要

## 環境設定

### 必要なツール

- Google Cloud SDK
- Ruby on rbenv
- SlackワークスペースとSlack APIへのアクセス

## 環境変数の設定

- `.env.development` ファイルを作成する

## セットアップ手順

1. 依存関係のインストール

```bash
bundle install
```

2. Google Cloud Functionsにデプロイ

```bash
gcloud functions deploy slack_chatgpt_bot \
  --runtime ruby32 \
  --trigger-http \
  --allow-unauthenticated \
  --project hidesys
```

## Slack Botの設定方法

  1. Slackアプリの作成
    - Slack APIのAppページに移動し、新しいアプリを作成します。
  2. OAuth & Permissionsの設定
    - アプリのOAuth & Permissionsページで、以下のスコープを追加します：
      - chat:write
      - chat:write.public
      - channels:history
      - groups:history
      - im:history
      - mpim:history
  3. イベントサブスクリプションの設定
    - App HomeのEvent SubscriptionsでEnable Eventsをオンにします。
    - Request URLに、Google Cloud FunctionsのエンドポイントURLを入力します。
    - Subscribe to bot eventsセクションにてapp_mentionイベントを追加します。
  4. Botトークンの取得
    - OAuth & Permissionsページで、OAuthトークンが生成されているはずです。これを環境変数のSLACK_BOT_TOKENに設定します。
  5. Slackチャンネルで@ChatGPTと会話を開始
    - Botがワークスペースに追加されていることを確認し、チャンネル上で@ChatGPTとメンションして会話を開始できます。メンションしたスレッドでChatGPTが応答を返します。
