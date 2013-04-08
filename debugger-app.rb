require 'sinatra'
require 'json'
require 'logstash'
require 'logstash/event'
require 'logstash/config/file'
require 'logstash/logging'
require "logstash/util"
require 'securerandom'
require 'redis'
require 'resque'


class LogstashFilterApp < Sinatra::Base
  before do
    @redis = Redis.new
  end
  post '/debugger' do
    @guid = SecureRandom.uuid
    data = JSON.parse request.body.read
    hash = {'config' => data["config"]}
    hash['rev'] = 0
    @redis.set(@guid, hash.to_json)
    {"id" => @guid}.to_json
  end

  get '/debugger/:id' do
    @redis.get(params[:id])
  end

  put '/debugger/:id' do
    data = JSON.parse request.body.read
    hash = {'config' => data["config"]}
    hash['rev'] = 0
    @redis.set(params[:id], hash.to_json)
    hash.to_json
  end

  post '/debugger/:id/plain' do
    data = request.body.read
    event = LogStash::Event.new
    event.message = data
    Resque.enqueue(Worker, @redis.get(params[:id]), event.to_json)
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
    Resque.enqueue(Worker, @redis.get(params[:id]), event.to_json)
  end

  post '/debugger/:id/json_event' do
    raw = request.body.read
    begin
      event = LogStash::Event.from_json(raw.force_encoding("UTF-8"))
    rescue => e
      event.message = raw
      event.tags << "_jsonparsefailure"
    end
    Resque.enqueue(Worker, @redis.get(params[:id]), event.to_json)
  end


end

class Worker
  @queue = :filterworker

  def self.perform(config, event)
    @filters = []
    logger = LogStash::Logger.new(STDERR)
    logger.level = :debug
    config = LogStash::Config::File.new(nil, JSON.parse(config)["config"])
    config.logger = logger
    config.parse do |plugin|
      type = plugin[:type].config_name  # "input" or "filter" etc...
      if type == 'filter'
        klass = plugin[:plugin]
        instance = klass.new(plugin[:parameters])
        instance.logger = logger
        @filters << instance
      end
    end

    @filters.each do |filter|
      filter.type = "stdin" if filter.type.nil?
    end

    @filter_queue = LogStash::SizedQueue.new(10)
    @filter_queue.logger = logger
    @output_queue = LogStash::MultiQueue.new
    @output_queue.logger = logger

    filterworker = LogStash::FilterWorker.new(@filters, @filter_queue,
                                                    @output_queue)
    filterworker.logger = logger
    thread = Thread.new(filterworker, 0, @output_queue) do |*args|
      run_filter(*args)
    end

    @filter_queue << LogStash::Event.from_json(event)
    logger.info(:event => @output_queue.pop)
  end

  def self.run_filter(filterworker, index, output_queue)
    LogStash::Util::set_thread_name("|worker.#{index}")
    filterworker.run
    @logger.warn("Filter worker shutting down", :index => index)

    # If we get here, the plugin finished, check if we need to shutdown.
    #shutdown_if_none_running(LogStash::FilterWorker, output_queue)
  end # def run_filter

end
