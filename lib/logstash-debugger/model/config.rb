require 'logstash-debugger/model/event'
require 'securerandom'
require 'dm-core'


class LSDebugger::Config
  include DataMapper::Resource

  property :id, Serial
  property :guid, String, :index => true, :default => lambda {|r,p| SecureRandom.uuid}
  property :config, Text
  property :rev, Integer

  has n, :events
end
