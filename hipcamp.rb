#!/usr/bin/env ruby

require 'curb'
require 'yajl'
require 'yaml'
require 'hipchat'
require 'date'

def load_config(config_file)
  puts "-- Loading config"
  YAML.load_file config_file
end

def fetch_basecamp_events(config)
  puts "-- Fetching Basecamp events"

  r = Curl::Easy.perform(config['resource_url']) do |curl|
    curl.headers["User-Agent"] = config['app_name']
    curl.http_auth_types = :basic
    curl.username = config['username']
    curl.password = config['password']
  end

  Yajl::Parser.parse(r.body_str)
end

def get_new_events(events, config)
  case config['resource_type']
  when 'project'
    get_new_project_events(events, config)
  when 'calendar'
    get_new_calendar_events(events)
  else
    raise "Unknown resource type"
  end
end

def get_new_project_events(events, config)
  new_events = []

  i = 0

  while events[i]['id'] != config["last_event_id"]
    new_events << events[i]
    i = i + 1
  end

  new_events
end

def get_new_calendar_events(events)
  events.select do |e|
    event_date = Date.parse e['starts_at']
    event_date <= Date.today
  end
end

def post_new_events(events, config)
  puts "-- Got %i new events to post" % events.size

  client = HipChat::Client.new(config['token'])

  events.each do |event|
    msg = build_message(event, config)
    post_message(client, msg, config)
  end

  puts "-- Posting successfull!"
end

def post_message(client, msg, config)
  opts = {
    :color  => config['color'],
    :notify => true,
    :message_format => 'text' }

  client[config['channel']].send('Hipcamp',
                                 msg,
                                 opts)
end

def build_message(event, config)
  msg_fields = config['message_fields'].collect{ |f| event[f] }
  msg = config['message_format'] % ([event['creator']['name']] + msg_fields)
  fix_message(msg)
end

def fix_message(msg)
  msg.gsub("&lt;", "<")
    .gsub("&gt;", ">")
    .gsub("&quot;", "\"")
    .gsub("&#39;", "\'")
end

def update_config(latest_event, config, config_file)
  if config['basecamp']['resource_type'] == "project"
    puts "-- Updating config file"

    config['basecamp']['last_event_id'] = latest_event['id']
    f = File.open(config_file, "w+")
    f.write(YAML::dump(config))
    f.close
  end
end

def main
  config_file = ARGV[0]

  puts "Running Hipcamp...\n"

  config = load_config(config_file)
  events = fetch_basecamp_events(config["basecamp"])
  new_events = get_new_events(events, config["basecamp"])
  post_new_events(new_events, config["hipchat"]) unless new_events.empty?
  update_config(new_events.first, config, config_file) unless new_events.empty?

  puts "\nDone!"
end

main
