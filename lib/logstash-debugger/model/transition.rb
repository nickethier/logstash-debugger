require 'securerandom'
require 'dm-core'

class LSDebugger::Transition
  include DataMapper::Resource

  property :id, Serial
  property :filter, String
  property :raw, Text

end
