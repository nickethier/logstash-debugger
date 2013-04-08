require 'sinatra'
require 'json'
require 'logstash'
require 'logstash/event'
require 'logstash/config/file'
require 'logstash/logging'
require "logstash/util"
require 'logstash-debugger/model/config'
require 'logstash-debugger/worker'
require 'resque'

class LSDebugger::App < Sinatra::Base
  set :views, File.dirname(__FILE__)+'/../../views'
  set :public_folder, File.dirname(__FILE__)+'/../../public'
  enable :method_override

  post '/debugger' do
    @config = LSDebugger::Config.new
    @config.config = request.body.read
    @config.rev = 0
    @config.save
    @config.guid
  end

  get '/debugger/:id' do
    config = LSDebugger::Config.first(:guid => params[:id])
    halt 404, 'Config not found' if config.nil?
    {'config' => config.config, 'rev' => config.rev, 
      'events' => config.events.collect{|e| e.guid} }.to_json
  end

  put '/debugger/:id' do
    @config = LSDebugger::Config.first(:guid => params[:id])
    halt 404, 'Config not found' if config.nil?
    @config.config = request.body.read
    @config.rev = @config.rev+1
    @config.save
    {'config' => @config.config, 'rev' => @config.rev}.to_json
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
LSDebugger.require_children(File.dirname(__FILE__)+'/controllers')
