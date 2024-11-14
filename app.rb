require 'functions_framework'
require 'json'
require 'net/http'

# Google Cloud Functionエントリーポイント
FunctionsFramework.http("slack_chatgpt_bot") do |request|
  body = JSON.parse(request.body.read)

  # Slackのエンベロープチャレンジを確認
  return { challenge: body['challenge'] }.to_json if body['type'] == 'url_verification'
  # Slackからのイベント処理
  return { status: 'OK' }.to_json unless body['event'] && body['event']['type'] == 'app_mention'

  channel = body['event']['channel']
  thread_id = body['event']['ts']
  latest_message = body['event']['text']
  # thread_idが存在するのなら履歴を読み込む
  messages = if thread_id
               get_thread_messages(channel, thread_id)
             else
               [{ role: "user", content: latest_message }]
             end

  # OpenAI APIを呼び出す
  response_text = get_chatgpt_response(messages)

  # Slackに返信
  send_message_to_slack(channel, thread_id, response_text)

  { status: 'OK' }.to_json
end

FIRST_PROMPT = <<~PROMPT
  あなたは「株式会社めぐみソフト」のSlackチャットにいるbotの「ChatGPTめぐみ」です。
  プログラマー、エンジニア、その他メンバーの困りごとを解決する使命を負っています。
  社内で主に使われている言語はRuby, Ruby on Rails、JavaScriptです。
  文脈なしにコーディングの質問をされたら、Ruby, Rails, JavaScriptと想定して返信してください。
PROMPT

# OpenAI APIからの応答取得
def get_chatgpt_response(messages)
  uri = URI("https://api.openai.com/v1/chat/completions")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.path)
  request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
  request['Content-Type'] = 'application/json'

  messages = [
    { role: 'system', content: FIRST_PROMPT }
  ] + messages

  request.body = {
    model: "gpt-4o",
    messages:
  }.to_json

  response = http.request(request)
  JSON.parse(response.body)['choices'][0]['message']['content']
end


def get_thread_messages(channel, thread_id)
  uri = URI.parse("https://slack.com/api/conversations.replies")
  params = { channel:, ts: thread_id }
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
        {
          role: message['user'] == ENV['SLACK_BOT_USER_ID'] ? 'assistant' : 'user',
          content: message['text']
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
