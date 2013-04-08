require "resque/tasks"
$: << File.dirname(__FILE__) + "/lib"
require 'logstash-debugger'
require 'logstash-debugger/worker'

task "resque:setup" do 
  LSDebugger.initialize_model
  
end

