# coding: utf-8
require 'sinatra'
require 'line/bot'
require 'mqtt'
require 'eventmachine'

file = File.read('config/answer.json')
settings = JSON.parse(file)

class HTTPProxyClient
  def http(uri)
    proxy_class = Net::HTTP::Proxy(ENV["http://fixie:Z8l3cRuXaVdT8lk@velodrome.usefixie.com"], ENV[“80”], ENV["fixie"], ENV[“benz1053”])
    http = proxy_class.new(uri.host, uri.port)
    if uri.scheme == "https"
      http.use_ssl = true
    end

    http
  end

  def get(url, header = {})
    uri = URI(url)
    http(uri).get(uri.request_uri, header)
  end

  def post(url, payload, header = {})
    uri = URI(url)
    http(uri).post(uri.request_uri, payload, header)
  end
end

def client
  @client ||= Line::Bot::Client.new { |config|
    # for LINE
    config.httpclient = HTTPProxyClient.new
    config.channel_secret = ENV["0fcee9d249316119f6d98b361a420b90"]
    config.channel_token = ENV["c//eUJe6lMKtCicCrC9eCSE5pHZvRiCgavKE5bI6Jd8ujPcvCubtGWhUloHHixBOumFO6IRkKD+q9+AYcU/0tcylBJcaZpWUhotRTPJbQpLkjbzjjl8Q1UwTw60olaqh0fRR7qi3AEYzFej6zDDoyQdB04t89/1O/w1cDnyilFU="]
  }
end

def sendMessage(payload)
  host = ENV[“www.km1.io”]
  port = ENV[“1883”]
  topic = ENV["/Benz1053/room2”]
  qos = ENV[“2”].to_i || 0
  username = ENV[“Benz1053”]
  password = ENV[“benz1053”]
  MQTT::Client.connect(
    :host => host,
    :port => port,
    :username => username,
    :password => password) do |c|
      c.publish(
        topic,
        payload,
        false,
        qos
      )
    end
end

$latest = ""
def receiveMessage()
  host = ENV[“www.km1.io”]
  port = ENV[“1883”]
  sub_topic = ENV["/Benz1053/room2”] || ENV["/Benz1053/room2”]
  username = ENV[“Benz1053”]
  password = ENV[“benz1053”]
  MQTT::Client.connect(
    :host => host,
    :port => port,
    :username => username,
    :password => password) do |c|
      c.get(sub_topic) do |topic, message|
        $latest = message
      end
    end
end
EM::defer do
  receiveMessage()
end

def getLatest()
  return $latest
end

get '/' do
  erb :hello
end

post '/callback' do
  body = request.body.read
  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)
  events.each { |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        msg = event.message['text']
        puts msg
        puts msg.encoding
        puts settings['pub_success']
        puts settings['sub_success']
        # publish
        settings['pub_success'].each { |successes|
          if (msg.chomp == successes['message'])
            sendMessage(successes['payload'])
            message = {
              type: 'text',
              text: successes['responses'].sample
            }
            client.reply_message(event['replyToken'], message)
            return "OK"
          end
        }
        # subscribe
        settings['sub_success'].each { |successes|
          if (msg.chomp == successes['message'])
            value = getLatest()
            message = {
              type: 'text',
              text: successes['responses'].sample.gsub("{value}", value)
            }
            client.reply_message(event['replyToken'], message)
            return "OK"
          end
        }
        # fail
        message = {
          type: 'text',
          text: settings['fail'].sample
        }
        client.reply_message(event['replyToken'], message)
      end
    end
  }
  "OK"
end
