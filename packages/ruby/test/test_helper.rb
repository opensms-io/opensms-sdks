# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "opensms"

# In-memory HTTP client injected through Opensms::Client.new(http_client:).
# Records every request and serves queued responses (or raises queued
# exceptions), so the unit tests never touch the network.
class MockHttp
  Request = Struct.new(:method, :url, :headers, :body, :timeout) do
    def path
      url.sub(%r{\Ahttps?://[^/]+}, "").split("?", 2).first
    end

    def query
      url.split("?", 2)[1]
    end

    def json
      JSON.parse(body, symbolize_names: true)
    end
  end

  attr_reader :requests

  def initialize
    @queue = []
    @requests = []
  end

  # Queue a response. Non-String bodies are JSON-encoded.
  def enqueue(status: 200, body: nil, headers: {})
    text = body.nil? || body.is_a?(String) ? body : JSON.generate(body)
    hdrs = body.nil? || body.is_a?(String) ? {} : { "Content-Type" => "application/json" }
    @queue << [status, hdrs.merge(headers), text]
    self
  end

  # Queue a problem+json error body.
  def enqueue_problem(status, detail, headers: {}, **extra)
    body = { type: "about:blank", title: "Error", status: status, detail: detail }.merge(extra)
    @queue << [status, { "Content-Type" => "application/problem+json" }.merge(headers), JSON.generate(body)]
    self
  end

  # Queue an exception raised instead of a response.
  def enqueue_error(error = Errno::ECONNREFUSED.new)
    @queue << error
    self
  end

  def call(method, url, headers, body, timeout)
    @requests << Request.new(method, url, headers.dup, body, timeout)
    item = @queue.shift || [200, { "Content-Type" => "application/json" }, "{}"]
    raise item if item.is_a?(Exception)

    item
  end

  def last
    @requests.last
  end
end

module ClientHelpers
  KEY = "sk_test_#{'A' * 32}".freeze

  def setup
    @http = MockHttp.new
    @sleeps = []
    @client = build_client
  end

  def build_client(**opts)
    Opensms::Client.new(api_key: KEY, base_url: "http://mock.local", http_client: @http,
                        sleeper: ->(s) { @sleeps << s }, random: -> { 0.5 }, **opts)
  end

  def sample_msg(overrides = {})
    { id: "0b8f7f5e-1d7e-4a44-9e53-7f2d2f5a0001", to: "+254700000012", status: "queued",
      price: "0.000000" }.merge(overrides)
  end
end
