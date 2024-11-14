require 'sinatra'
require 'json'
require 'net/http'

# Google Cloud Functionエントリーポイント
def slack_bot(request)
  body = JSON.parse(request.body.read)

  # Slackのエンベロープチャレンジを確認
  return { challenge: body['challenge'] }.to_json if body['type'] == 'url_verification'

  # Slackからのイベント処理
  if body['event'] && body['event']['type'] == 'app_mention'
    user_message = body['event']['text']

    # OpenAI APIを呼び出す
    response_text = get_chatgpt_response(user_message)

    # Slackに返信
    send_message_to_slack(body['event']['thread_ts'], response_text)
  end

  { status: 'OK' }.to_json
end

# OpenAI APIからの応答取得
def get_chatgpt_response(message)
  uri = URI("https://api.openai.com/v1/chat/completions")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.path)
  request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
  request['Content-Type'] = 'application/json'

  request.body = {
    model: "gpt-3.5-turbo",
    messages: [{ role: "user", content: message }]
  }.to_json

  response = http.request(request)
  JSON.parse(response.body)['choices'][0]['message']['content']
end

# Slackにメッセージを送信
def send_message_to_slack(thread_ts, text)
  uri = URI("https://slack.com/api/chat.postMessage")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.path)
  request['Authorization'] = "Bearer #{ENV['SLACK_BOT_TOKEN']}"
  request['Content-Type'] = 'application/json'

  request.body = {
    channel: ENV['SLACK_CHANNEL_ID'],
    text: text,
    thread_ts: thread_ts
  }.to_json

  http.request(request)
end
