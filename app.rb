# coding: utf-8
require 'sinatra'
require 'line/bot'
require 'mqtt'
require 'eventmachine'

file = File.read('config/answer.json')
settings = JSON.parse(file)

class HTTPProxyClient
  def http(uri)
    proxy_class = Net::HTTP::Proxy(ENV["FIXIE_URL_HOST"], ENV["FIXIE_URL_POST"], ENV["FIXIE_URL_USER"], ENV["FIXIE_URL_PASSWORD"])
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
    config.channel_id = ENV["LINE_CHANNEL_ID"]
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_mid = ENV["LINE_CHANNEL_MID"]
  }
end

def sendMessage(payload)
  host = ENV["MQTT_HOST"]
  port = ENV["MQTT_PORT"]
  topic = ENV["MQTT_TOPIC"]
  qos = ENV["MQTT_QOS"].to_i || 0
  username = ENV["MQTT_USERNAME"]
  password = ENV["MQTT_PASSWORD"]
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
  host = ENV["MQTT_HOST"]
  port = ENV["MQTT_PORT"]
  topic = ENV["MQTT_TOPIC"]
  username = ENV["MQTT_USERNAME"]
  password = ENV["MQTT_PASSWORD"]
  MQTT::Client.connect(
    :host => host,
    :port => port,
    :username => username,
    :password => password) do |c|
      c.get(topic) do |topic, message|
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
  signature = request.env['HTTP_X_LINE_CHANNELSIGNATURE']
  unless client.validate_signature(request.body.read, signature)
    error 400 do 'Bad Request' end
  end

  receive_request = Line::Bot::Receive::Request.new(request.env)

  receive_request.data.each { |message|
    case message.content
    # Line::Bot::Receive::Message
    when Line::Bot::Message::Text
      msg = message.content[:text]
      puts msg
      puts msg.encoding
      puts settings['pub_success']
      puts settings['sub_success']
      # publish
      settings['pub_success'].each { |successes|
        if (msg.chomp == successes['message'])
          sendMessage(successes['payload'])
          client.send_text(
            to_mid: message.from_mid,
            text: successes['responses'].sample,
          )
          return "OK"
        end
      }
      # subscribe
      settings['sub_success'].each { |successes|
        if (msg.chomp == successes['message'])
          value = getLatest()
          client.send_text(
            to_mid: message.from_mid,
            text: successes['responses'].sample.gsub("{value}", value),
          )
          return "OK"
        end
      }
      # fail
      client.send_text(
        to_mid: message.from_mid,
        text: settings['fail'].sample,
      )
    # Line::Bot::Receive::Operation
    when Line::Bot::Operation::AddedAsFriend
      puts 'Welcome message of send_sticker'
      client.send_sticker(
        to_mid: message.from_mid,
        stkpkgid: 2,
        stkid: 144,
        stkver: 100
      )
    end
  }
  "OK"
end
