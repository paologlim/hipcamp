#!/usr/bin/env ruby

require 'curb'
require 'yajl'
require 'yaml'
require 'hipchat'

def load_config(config_file)
  puts "-- Loading config"
  YAML.load_file config_file
end

def fetch_basecamp_events(config)
  puts "-- Fetching Basecamp events"
  url = "https://basecamp.com/%s/api/v1/projects/%s/events.json" % [config['id'], config['project_id']]

  r = Curl::Easy.perform(url) do |curl|
    curl.headers["User-Agent"] = config['app_name']
    curl.http_auth_types = :basic
    curl.username = config['username']
    curl.password = config['password']
  end

  Yajl::Parser.parse(r.body_str, :symbolize_keys => true)
end

def get_new_events(events, config)
  new_events = []

  i = 0

  while events[i][:id] != config["last_event_id"]
    new_events << events[i]
    i = i + 1
  end

  new_events
end

def post_new_events(events, config)
  puts "-- Got %i new events to post" % events.size

  client = HipChat::Client.new(config['token'])

  events.each do |event|
    msg = "%s:%s<br/>%s" % [event[:creator][:name], event[:summary], event[:excerpt]]
    msg = fix_message(msg)
    client[config['channel']].send('Hipcamp', msg, :color => config['color'])
  end

  puts "-- Posting successfull!"
end

def fix_message(msg)
  msg.gsub("&lt;", "<")
    .gsub("&gt;", ">")
    .gsub("&quot;", "\"")
    .gsub("&#39;", "\'")
end

def update_config(latest_event, config, config_file)
  puts "-- Updating config file"

  config['basecamp']['last_event_id'] = latest_event[:id]
  f = File.open(config_file, "w+")
  f.write(YAML::dump(config))
  f.close
end

def main
  config_file = "hipcamp.yml"

  puts "Running Hipcamp...\n"

  config = load_config(config_file)
  events = fetch_basecamp_events(config["basecamp"])
  new_events = get_new_events(events, config["basecamp"])
  post_new_events(new_events, config["hipchat"]) unless new_events.empty?
  update_config(new_events.first, config, config_file) unless new_events.empty?

  puts "\nDone!"
end

main
