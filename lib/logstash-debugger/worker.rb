require 'logstash'
require 'logstash/event'
require 'logstash/config/file'
require 'logstash/logging'
require 'logstash/util'
require 'logstash-debugger/model/config'
require 'logstash-debugger'

class LSDebugger::Worker

  attr_reader :event

  def initialize(event)
    puts event
    @event = event
  end

  def <<(event)
    @event.log_data = @event.log_data + "\n" + event.inspect rescue event.inspect
    @event.save
  end

  def self.perform(data, event)
    @filters = []

    logger = LogStash::Logger.new(LSDebugger::Worker.new(event))
    logger.level = :debug
    config = LogStash::Config::File.new(nil, data.config)
    config.logger = logger
    config.parse do |plugin|
      type = plugin[:type].config_name  # "input" or "filter" etc...
      if type == 'filter'
        klass = plugin[:plugin]
        instance = klass.new(plugin[:parameters])
        instance.logger = logger
        instance.register
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
    filterworker.after_filter do |e, f|
      t = LSDebugger::Transition.new(:filter => f.to_s, :raw => e.to_json)
      event.transitions << t
      event.save
    end

    thread = Thread.new(filterworker, 0, @output_queue, logger) do |*args|
      run_filter(*args)
    end

    @filter_queue << LogStash::Event.from_json(event.raw)
    sleep(10) #TODO handle flushed/yielded events?
    @filter_queue << LogStash::SHUTDOWN
  end

  def self.run_filter(filterworker, index, output_queue, logger)
    LogStash::Util::set_thread_name("|worker.#{index}")
    filterworker.run
    logger.warn("Filter worker shutting down", :index => index)

    # If we get here, the plugin finished, check if we need to shutdown.
    #shutdown_if_none_running(LogStash::FilterWorker, output_queue)
  end # def run_filter

end
