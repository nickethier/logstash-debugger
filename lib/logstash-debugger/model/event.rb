require 'securerandom'
require 'logstash-debugger/model/transition'
require 'dm-core'
require 'logstash/namespace'
require 'logstash/event'

class LSDebugger::Event
  include DataMapper::Resource

  property :id, Serial
  property :guid, String, :index => true, :default => lambda {|r,p| SecureRandom.uuid}
  property :raw, Text
  property :log_data, Text

  has n, :transitions

  def self.from_event(event)
    new(:raw => event.to_json)
  end

  def to_event
    LogStash::Event.from_json(raw) 
  end

end
