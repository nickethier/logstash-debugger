require 'securerandom'
require 'logstash-debugger/model/transition'
require 'dm-core'

class LSDebugger::Event
  include DataMapper::Resource

  property :id, Serial
  property :guid, String, :index => true, :default => lambda {|r,p| SecureRandom.uuid}
  property :raw, Text

  has n, :transitions

  def self.from_event(event)
    new(:raw => event.to_json)
  end
end
