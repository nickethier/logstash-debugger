require 'sinatra'
require 'json'
require 'logstash'
require 'logstash/event'
require 'logstash/config/file'
require 'logstash/logging'
require "logstash/util"
require 'logstash-debugger/model/config'
require 'logstash-debugger/worker'


class LSDebugger::Api < Sinatra::Base

  post '/debugger' do
    @config = LSDebugger::Config.new
    @config.config = request.body.read
    @config.rev = 0
    @config.save
    @config.id
  end

  get '/debugger/:id' do
    LSDebugger::Config.get(params[:id])
  end

  put '/debugger/:id' do
    @config = LSDebugger::Config.get(params[:id])
    @config.config = request.body.read
    @config.rev = @config.rev+1
    @config.save
    @config.to_json
  end

  post '/debugger/:id/plain' do
    data = request.body.read
    event = LogStash::Event.new
    event.message = data
    Resque.enqueue(LSDebugger::Worker, params[:id], event.to_json)
  end

  post '/debugger/:id/json' do
    raw = request.body.read
    begin
      # JSON must be valid UTF-8, and many inputs come from ruby IO
      # instances, which almost all default to ASCII-8BIT. Force UTF-8
      fields = JSON.parse(raw.force_encoding("UTF-8"))
      fields.each { |k, v| event[k] = v }
      event.message = raw
    rescue => e
      event.message = raw
      event.tags << "_jsonparsefailure"
    end
    Resque.enqueue(LSDebugger::Worker, params[:id], event.to_json)
  end

  post '/debugger/:id/json_event' do
    raw = request.body.read
    begin
      event = LogStash::Event.from_json(raw.force_encoding("UTF-8"))
    rescue => e
      event.message = raw
      event.tags << "_jsonparsefailure"
    end
    Resque.enqueue(LSDebugger::Worker, params[:id], event.to_json)
  end


end


