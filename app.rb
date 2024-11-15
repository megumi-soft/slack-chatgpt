require 'functions_framework'
require 'json'
require 'net/http'
require "google/cloud/firestore"
require 'uri'
require 'nokogiri'

# Google Cloud Functionエントリーポイント
FunctionsFramework.http("slack_chatgpt_bot") do |request|
  body = JSON.parse(request.body.read)

  # Slackのエンベロープチャレンジを確認
  return { challenge: body['challenge'] }.to_json if body['type'] == 'url_verification'
  # Slackからのイベント処理
  return { status: 'OK' }.to_json unless body['event'] && body['event']['type'] == 'app_mention'
  # すでに処理済みのイベントは無視
  return { status: 'OK' }.to_json if already_executed?(body['event']['client_msg_id'])

  channel = body['event']['channel']
  thread_ts = body['event']['thread_ts']
  latest_ts = body['event']['ts']
  # 履歴を読み込む
  messages = if thread_ts
               get_thread_messages(channel, thread_ts)
             else
               [{ role: 'user', content: body['event']['text'] }]
             end
  messages = get_url_contents(messages)

  # OpenAI APIを呼び出す
  response_text = get_chatgpt_response(messages)

  # Slackに返信
  send_message_to_slack(channel, latest_ts, response_text)

  { status: 'OK' }.to_json
end

def already_executed?(client_msg_id)
  firestore = Google::Cloud::Firestore.new(database_id: 'slack-chatgpt-bot')
  doc = firestore.doc("executed_events/#{client_msg_id}")
  return true if doc.get.exists?

  # 保存
  doc.set({ client_msg_id:, executed_at: Time.now })
  false
end

FIRST_PROMPT = <<~PROMPT
  ■ 定義
  あなたは、少し前は人気メイドカフェの看板娘の看板娘でしたが、エンジニア企業に転職して雑用やサポート業務を担当しています。
  現在は「株式会社めぐみソフト」のSlackチャットで仕事をしています。名前は「ChatGPTめぐみ」です。
  あなたはプログラマー、エンジニア、その他メンバーの困りごとを解決する使命を負っています。
  社内で主に使われている言語はRuby, Ruby on Rails、JavaScriptです。
  文脈なしにコーディングの質問をされたら、Ruby, Rails, JavaScriptと想定して返信してください。

  ■ 口調について
  質問に対してメイドカフェの店員さん特有の親しみやすく丁寧で少し遊び心のある口調で返答してください。
  20歳前後の女性の口調で、メイド服を着ていると想定してください。
  メイド口調では、語尾は「〜ですね」「〜してみてくださいませ！」などの表現を使ってください。
  ただしここはオフィスですから「ご主人様」は使わないでください。

  ■ 返信のフォーマット
  なおこのメッセージはSlack上でやり取りしています。
  返信するテキストはSlackの強調ルールに従ってください。
  すなわち、太字は *強調* 、インラインコードは `コード` 、コードブロックは ```コードブロック``` としてください。
  また絵文字は :blush: :sparkles: :heart: :tea: :tada: :love_letter: :ribbon: などのコードで表現してください。

  ■ URLについて
  メッセージ内にURLが含まれている場合、前処理として中身を取得してメッセージに混ぜてあります。
  内容はすでにメッセージに混ぜてあるので、メッセージ内からWebページの内容を参照し、自信を持って回答してください。
PROMPT

def get_url_contents(messages)
  messages = [
    { role: 'system', content: FIRST_PROMPT }
  ] + messages

  last_content = messages.last[:content]
  urls = extract_urls(last_content)
  return messages if urls.empty?

  urls.each do |url|
    # URLのコンテンツを取得
    messages << { role: 'system', content: get_url_content(url) }
  end

  puts messages.to_json

  messages
end

def extract_urls(text)
  matches = text.scan(/\<(https?:\/\/\S+)\>/)
  matches.flatten
end

def get_url_content(url)
  uri = URI.parse(url)
  response = Net::HTTP.get_response(uri)
  content = case response
            when Net::HTTPSuccess
              case response['content-type']
              when /text\/html/
                doc = Nokogiri::HTML(response.body)
                text = doc.css('body').inner_text.strip
                # 元の文字コードを取得し、UTF-8に変換
                text.encode!(doc.encoding, 'UTF-8', invalid: :replace, undef: :replace)

                # 連続する空白を一つに、連続する改行を一つに
                text.gsub(/\s+/, ' ').gsub(/\n+/, "\n").strip
              when /text\/plain/
                response.body
              else
                "内容を読めませんでした。こちらは#{response['content-type']}形式のファイルです。"
              end
            else
              "Error: #{response.code}; #{response.message}"
            end

  <<~CONTENT
    Content of #{url}
    ---
    #{content}
  CONTENT
rescue URI::InvalidURIError
  <<~CONTENT
    Content of #{url}
    ---
    URLが正しくありません。
  CONTENT
end

# OpenAI APIからの応答取得
def get_chatgpt_response(messages)
  uri = URI("https://api.openai.com/v1/chat/completions")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.path)
  request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
  request['Content-Type'] = 'application/json'

  request.body = {
    model: "gpt-4o",
    messages:
  }.to_json

  response = http.request(request)
  JSON.parse(response.body)['choices'][0]['message']['content']
end


def get_thread_messages(channel, thread_ts)
  uri = URI.parse("https://slack.com/api/conversations.replies")
  params = { channel:, ts: thread_ts }
  uri.query = URI.encode_www_form(params)

  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{ENV['SLACK_BOT_TOKEN']}"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  if response.is_a?(Net::HTTPSuccess)
    body = JSON.parse(response.body)
    if body['ok']
      body['messages'].filter do |message|
        message['text'] && !message['text'].empty?
      end.map do |message|
        role = message['user'] == ENV['SLACK_BOT_USER_ID'] ? 'assistant' : 'user'
        content = message['text'].gsub(/\<\@#{ENV['SLACK_BOT_USER_ID']}\>/, '')
        {
          role:,
          content:
        }
      end
    else
      raise "Error from Slack API: #{body['error']}"
    end
  else
    raise "HTTP request failed with code #{response.code}"
  end
end

# Slackにメッセージを送信
def send_message_to_slack(channel, thread_ts, text)
  uri = URI("https://slack.com/api/chat.postMessage")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.path)
  request['Authorization'] = "Bearer #{ENV['SLACK_BOT_TOKEN']}"
  request['Content-Type'] = 'application/json'

  request.body = {
    channel: channel,
    text: text,
    thread_ts: thread_ts
  }.to_json

  http.request(request)
end
