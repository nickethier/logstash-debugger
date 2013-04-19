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

#Monkey patch
module URI
 
  major, minor, patch = RUBY_VERSION.split('.').map { |v| v.to_i }
 
  if major == 1 && minor <= 9
    def self.decode_www_form_component(str, enc=nil)
      if TBLDECWWWCOMP_.empty?
        tbl = {}
        256.times do |i|
          h, l = i>>4, i&15
          tbl['%%%X%X' % [h, l]] = i.chr
          tbl['%%%x%X' % [h, l]] = i.chr
          tbl['%%%X%x' % [h, l]] = i.chr
          tbl['%%%x%x' % [h, l]] = i.chr
        end
        tbl['+'] = ' '
        begin
          TBLDECWWWCOMP_.replace(tbl)
          TBLDECWWWCOMP_.freeze
        rescue
        end
      end
      str = str.gsub(/%(?![0-9a-fA-F]{2})/, "%25")
      str.gsub(/\+|%[0-9a-fA-F]{2}/) {|m| TBLDECWWWCOMP_[m]}
    end
  end
 
end