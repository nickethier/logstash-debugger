require 'sinatra'
require 'json'
require 'logstash'
require 'logstash/event'
require 'logstash/config/file'
require 'logstash/logging'
require "logstash/util"
require 'logstash-debugger/model/config'
require 'logstash-debugger/worker'
require 'stud/task'
require 'diffy'

class LSDebugger::App < Sinatra::Base
  set :views, File.dirname(__FILE__)+'/../../views'
  set :public_folder, File.dirname(__FILE__)+'/../../public'
  enable :method_override


  post '/debugger.json' do
    config = LSDebugger::Config.new
    data = JSON.parse(request.body.read) rescue halt(500)
    config.config = data['config']
    config.rev = 0
    config.save
    {"config_id" => config.guid}.to_json
  end

  get '/debugger/:id.json' do
    config = LSDebugger::Config.first(:guid => params[:id])
    halt 404, 'Config not found' if config.nil?
    {'config' => config.config, 'rev' => config.rev, 
      'event_ids' => config.events.collect{|e| e.guid} }.to_json
  end

  put '/debugger/:id.json' do
    config = LSDebugger::Config.first(:guid => params[:id])
    halt 404, 'Config not found' if config.nil?
    data = JSON.parse(request.body.read) rescue halt(500)
    config.config = data['config']
    config.rev = config.rev+1
    config.save
    {'rev' => config.rev}.to_json
  end

  post '/debugger/:id/events.json' do
		config = LSDebugger::Config.first(:guid => params[:id])
    halt 404, 'Config not found' if config.nil?
    data = JSON.parse(request.body.read) rescue halt(500)
    event = LogStash::Event.new
    puts data.inspect
    case data['format']
    when 'plain'
      event.message = data['event']
    when 'json'
      begin
      # JSON must be valid UTF-8, and many inputs come from ruby IO
      # instances, which almost all default to ASCII-8BIT. Force UTF-8
	      fields = JSON.parse(data['event'].force_encoding("UTF-8"))
  	    fields.each { |k, v| event[k] = v }
    	  event.message = data['event']
    	rescue => e
      	event.message = data['event']
      	event.tags << "_jsonparsefailure"
    	end
		when 'json_event'
			begin
      	event = LogStash::Event.from_json(data['event'].force_encoding("UTF-8"))
    	rescue => e
    	  event.message = data['event']
  	    event.tags << "_jsonparsefailure"
    	end
		else
			halt(500, 'Bad format')
		end
		e = LSDebugger::Event.create(:raw => event.to_json)
		config.events << e
		config.save
		
		Stud::Task.new do
			thread = LSDebugger::Worker.perform(config, e)
			puts thread.wait
			puts 'DONE'
		end
		{'event_id' => e.guid}.to_json
  end

	get '/debugger/:id/events/:eid.json' do
		config = LSDebugger::Config.first(:guid => params[:id])
		event = LSDebugger::Event.first(:guid => params[:eid])
		halt 404, 'Config not found' if config.nil?
		halt 404, 'Event not found' if event.nil?

		json = {'event' => event.raw,
			'config_rev' => config.rev,
			'transitions' => event.transitions.collect{|t| 
					{
						'filter' => t.filter,
						'filtered_event' => t.raw,
            'diff' => Diffy::Diff.new(JSON.pretty_generate(JSON.parse(event.raw)),
              JSON.pretty_generate(JSON.parse(t.raw))).to_s(:html)
					}
			},
			'log' => event.log_data
		}
    if params[:pretty]
      JSON.pretty_generate(json)
    else
      json.to_json
    end
	end

  get '/debugger/:id/events/:eid' do
    @config = LSDebugger::Config.first(:guid => params[:id])
    @event = LSDebugger::Event.first(:guid => params[:eid])
    @state = JSON.pretty_generate(JSON.parse(@event.raw))
    @transitions = @event.transitions.collect{|t| 
          e = {
            'filter' => t.filter,
            'filtered_event' => t.raw,
            'diff' => Diffy::Diff.new(@state,
              JSON.pretty_generate(JSON.parse(t.raw))).to_s(:html)
          }
          @state = JSON.pretty_generate(JSON.parse(t.raw))
          e
      }
    erb :events
  end

  get '/debugger/:id' do
    @config = LSDebugger::Config.first(:guid => params[:id])
    halt 404, 'Config not found' if @config.nil?
    erb :config
  end

  get '/diff.css' do
    content_type 'text/css'
    Diffy::CSS
  end

  get '/' do
    erb :home
  end


end
LSDebugger.require_children(File.dirname(__FILE__)+'/controllers')
