require 'logstash'
require 'logstash/event'
require 'logstash/config/file'
require 'logstash/logging'
require "logstash/util"
require 'logstash-debugger/model/config'
require 'logstash-debugger'

class LSDebugger::Worker
  @queue = :filterworker

  def self.perform(id, event)
    @filters = []
    data = LSDebugger::Config.first(:guid => id)

    logger = LogStash::Logger.new(STDERR)
    logger.level = :debug
    config = LogStash::Config::File.new(nil, data.config)
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
    @output_queue = LogStash::SizedQueue.new(10)
    @output_queue.logger = logger

    filterworker = LogStash::FilterWorker.new(@filters, @filter_queue,
                                                    @output_queue)
    filterworker.logger = logger
    thread = Thread.new(filterworker, 0, @output_queue) do |*args|
      run_filter(*args)
    end

    @filter_queue << LogStash::Event.from_json(event)

    data.events << LSDebugger::Event.from_event(@output_queue.pop)
    data.save
  rescue Resque::TermException => e
    puts e.inspect
  end

  def self.run_filter(filterworker, index, output_queue)
    LogStash::Util::set_thread_name("|worker.#{index}")
    filterworker.run
    @logger.warn("Filter worker shutting down", :index => index)

    # If we get here, the plugin finished, check if we need to shutdown.
    #shutdown_if_none_running(LogStash::FilterWorker, output_queue)
  end # def run_filter

end