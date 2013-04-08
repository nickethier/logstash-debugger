require 'dm-core'
require 'dm-redis-adapter'

module LSDebugger
  module Controller end
  def self.app
    initialize_model

    require 'logstash-debugger/app'

    LSDebugger::App
  end

  def self.initialize_model
    DataMapper::Logger.new($stdout, :debug)
    DataMapper.setup(:default, {:adapter  => "redis"})
    LSDebugger.require_children(File.dirname(__FILE__)+'/logstash-debugger/model')
    DataMapper.finalize
  end

  def self.require_children(path)
    Dir.foreach(path) do |filename|
      to_require = File.basename(filename, '.rb')
      unless to_require.match(/^\./)
        if File.directory? "#{path}/#{filename}"
          require_children("#{path}/#{filename}")
        else
          require "#{path}/#{to_require}"
        end
      end
    end
  end
end