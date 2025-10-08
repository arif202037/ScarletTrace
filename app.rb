#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple login logging API using Sinatra
# - POST /login: accept JSON payload, enrich with IP + timestamp, redact sensitive fields, append to logs.jsonl
# - Sends a short notification to Discord and Telegram (if env vars configured)
# - Basic request throttling via rack-throttle
#
# Requirements (gems): sinatra, json, dotenv, net/http, uri, rack-throttle

require 'json'
require 'time'
require 'net/http'
require 'uri'
require 'fileutils'

# Auto-load .env if present
begin
  require 'dotenv/load'
rescue LoadError
  warn '[WARN] dotenv gem not found; skipping .env loading'
end

require 'sinatra'
begin
  require 'rack/throttle'
rescue LoadError
  warn '[WARN] rack-throttle gem not found; rate limiting disabled'
end

# Settings
set :environment, (ENV['RACK_ENV'] || 'development')
set :port, (ENV['PORT'] || 4567).to_i
set :bind, (ENV['BIND'] || '0.0.0.0')
set :logging, true

LOG_PATH = File.join(__dir__, 'logs.jsonl')
THROTTLE_MAX_PER_MIN = (ENV['THROTTLE_MAX_PER_MIN'] || '60').to_i

if defined?(Rack::Throttle)
  use Rack::Throttle::Minute, max: THROTTLE_MAX_PER_MIN
end

helpers do
  # Recursively redact sensitive keys
  def redact_sensitive(obj, keys = %w[password token])
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), acc|
        if keys.include?(k.to_s.downcase)
          acc[k] = '[REDACTED]'
        else
          acc[k] = redact_sensitive(v, keys)
        end
      end
    when Array
      obj.map { |v| redact_sensitive(v, keys) }
    else
      obj
    end
  end

  # Safely append one JSON object per line to a JSONL file
  def append_jsonl(path, obj)
    line = JSON.generate(obj)
    FileUtils.mkdir_p(File.dirname(path)) unless Dir.exist?(File.dirname(path))
    File.open(path, File::RDWR | File::CREAT, 0o644) do |f|
      f.flock(File::LOCK_EX)
      f.seek(0, IO::SEEK_END)
      f.write(line)
      f.write("\n")
      f.flush
      f.fsync
    ensure
      begin
        f.flock(File::LOCK_UN)
      rescue StandardError
        # ignore
      end
    end
  end

  # Build a compact human notification string
  def build_notification(payload)
    username = payload['username'] || 'n/a'
    device = payload['device'].is_a?(Hash) ? payload['device'] : {}
    platform = device['platform'] || 'n/a'
    lang = device['language'] || 'n/a'
    screen = device['screen'].is_a?(Hash) ? device['screen'] : {}
    width = screen['width'] || screen[:width]
    height = screen['height'] || screen[:height]
    size = (width && height) ? "#{width}x#{height}" : 'n/a'
    ip = payload['ip'] || 'n/a'
    time = payload['timestamp'] || Time.now.utc.iso8601

    [
      '🔔 Nouvelle connexion :',
      "- user: #{username}",
      "- ip: #{ip}",
      "- os: #{platform}",
      "- lang: #{lang}",
      "- screen: #{size}",
      "- time: #{time}"
    ].join("\n")
  end

  # Send message to Discord webhook (returns [ok, error_message_or_nil])
  def notify_discord(message)
    url = ENV['DISCORD_WEBHOOK_URL']
    return [false, 'DISCORD_WEBHOOK_URL not set'] if url.to_s.strip.empty?
    begin
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = 5
      http.open_timeout = 5

      content = message[0, 1900] # Discord content limit safety
      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/json'
      req.body = { content: content }.to_json
      res = http.request(req)
      ok = res.is_a?(Net::HTTPSuccess)
      [ok, ok ? nil : "Discord HTTP #{res.code}"]
    rescue StandardError => e
      [false, e.message]
    end
  end

  # Send message to Telegram via bot sendMessage (returns [ok, error_message_or_nil])
  def notify_telegram(message)
    token = ENV['TELEGRAM_BOT_TOKEN']
    chat_id = ENV['TELEGRAM_CHAT_ID']
    return [false, 'TELEGRAM_BOT_TOKEN not set'] if token.to_s.strip.empty?
    return [false, 'TELEGRAM_CHAT_ID not set'] if chat_id.to_s.strip.empty?
    begin
      uri = URI.parse("https://api.telegram.org/bot#{token}/sendMessage")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 5
      http.open_timeout = 5

      req = Net::HTTP::Post.new(uri.request_uri)
      req.set_form_data('chat_id' => chat_id, 'text' => message)
      res = http.request(req)
      ok = res.is_a?(Net::HTTPSuccess)
      [ok, ok ? nil : "Telegram HTTP #{res.code}"]
    rescue StandardError => e
      [false, e.message]
    end
  end

  def json_error(status_code, message, details = nil)
    content_type :json
    body = { error: message }
    body[:details] = details if details
    halt status_code, JSON.generate(body)
  end

  # Basic shape validation; returns [ok, errors]
  def validate_payload(payload)
    errors = []
    unless payload.is_a?(Hash)
      errors << 'Payload must be a JSON object'
      return [false, errors]
    end

    username = payload['username']
    if !username.is_a?(String) || username.strip.empty?
      errors << 'username is required (non-empty string)'
    end

    device = payload['device']
    if device && !device.is_a?(Hash)
      errors << 'device must be an object when provided'
    else
      if device
        screen = device['screen']
        if screen && !screen.is_a?(Hash)
          errors << 'device.screen must be an object'
        elsif screen
          w = screen['width'] || screen[:width]
          h = screen['height'] || screen[:height]
          if w && !w.is_a?(Numeric)
            errors << 'device.screen.width must be numeric when provided'
          end
          if h && !h.is_a?(Numeric)
            errors << 'device.screen.height must be numeric when provided'
          end
        end
      end
    end

    [errors.empty?, errors]
  end
end

before do
  content_type :json
end

get '/' do
  JSON.generate({ ok: true, service: 'login-logger', time: Time.now.utc.iso8601 })
end

post '/login' do
  request.body.rewind
  raw = request.body.read
  json_error 400, 'Empty body' if raw.nil? || raw.strip.empty?

  begin
    payload = JSON.parse(raw)
  rescue JSON::ParserError => e
    json_error 400, 'Invalid JSON', e.message
  end

  ok, errors = validate_payload(payload)
  json_error 422, 'Validation failed', errors unless ok

  # Redact sensitive fields before persisting
  redacted = redact_sensitive(payload)

  # Enrich with server fields
  enriched = redacted.merge(
    'ip' => request.ip,
    'timestamp' => Time.now.utc.iso8601
  )

  # Persist to JSONL
  begin
    append_jsonl(LOG_PATH, enriched)
  rescue StandardError => e
    logger.error("Failed to write log: #{e.message}")
    json_error 500, 'Failed to persist log'
  end

  # Fire-and-forget notifications (errors do not block main flow)
  message = build_notification(enriched)
  disc_ok, disc_err = notify_discord(message)
  tele_ok, tele_err = notify_telegram(message)

  logger.info("/login from #{request.ip} user=#{enriched['username']} discord=#{disc_ok} telegram=#{tele_ok}")
  logger.warn("Discord notify error: #{disc_err}") if disc_err
  logger.warn("Telegram notify error: #{tele_err}") if tele_err

  status 201
  JSON.generate({ ok: true })
end

not_found do
  JSON.generate({ error: 'Not found' })
end

error 500 do
  JSON.generate({ error: 'Internal server error' })
end

# Run the app if executed directly
run! if __FILE__ == $PROGRAM_NAME
