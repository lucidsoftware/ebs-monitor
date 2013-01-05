#!/usr/bin/ruby
# 
# Copyright 2013 Lucid Software Inc
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 

require 'optparse'

$script_start = Time.now
$monitors = {}
$select_timeout = 2


###
# Parse command line options
###

$options = {
  'pidfile'   => '/var/run/disk-monitor.pid',
  'logfile'   => '/var/log/disk-monitor.log',
  'fifo'      => '/var/run/disk-monitor.fifo',
  'daemon'    => false,
  'heartbeat' => 5,
  'wait'      => 60
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-h", "--help", :NONE, "Shows this message") do
    puts opts
    exit 0
  end

  opts.on("-p", "--pidfile", :REQUIRED, String, "Set the pidfile. (Default: #{$options['pidfile']})") do |pidfile|
    $options['pidfile'] = pidfile
  end

  opts.on("-l", "--logfile", :REQUIRED, String, "Set the logfile. (Default: #{$options['logfile']})") do |logfile|
    $options['logfile'] = logfile
  end

  opts.on("-f", "--fifo", :REQUIRED, String, "Set the Linux FIFO file through which the reporters will report to the monitor. (Default: #{$options['fifo']})") do |fifo|
    $options['fifo'] = fifo
  end

  opts.on("-d", "--[no-]daemonize", :NONE, "Daemonize this program on startup. (Default: #{$options['daemon']})") do |daemon|
    $options['daemon'] = daemon
  end

  opts.on("-b", "--heartbeat", :REQUIRED, Integer, "Set the max number of seconds to allow between heartbeats before a reporter will be marked as 'down'. (Default: #{$options['heartbeat']} seconds)") do |heartbeat|
    $options['heartbeat'] = heartbeat
  end

  opts.on("-w", "--wait", :REQUIRED, Integer, "Set the number of seconds to delay before updating iptables. (Default: #{$options['wait']} seconds)") do |wait|
    $options['wait'] = wait
  end
end.parse!


###
# Helper functions
###

def daemonize
  if RUBY_VERSION < "1.9"
    exit if fork
    Process.setsid
    exit if fork
    Dir.chdir "/" 
    STDIN.reopen "/dev/null"
    STDOUT.reopen "/dev/null", "a" 
    STDERR.reopen "/dev/null", "a" 
  else
    Process.daemon
  end

  log("daemonized")
end

def log(message)
  full_message = "[#{Time.now}] #{message}"
  puts full_message
  File.open($options['logfile'], 'a') {|f| f.write("#{full_message}\n") }
end

def write_pid()
  File.open($options['pidfile'], 'w') {|f| f.write("#{$$}") }
  log("wrote pid to #{$options['pidfile']}")
end

def clean_pid()
  File.delete($options['pidfile'])
  log("removed pidfile #{$options['pidfile']}")
end

def update_iptables()
  if Time.now < ($script_start + $options['wait'])
    return
  end

  rules = {}

  $monitors.each do |dir, data|
    if !data['up']
      data['ports'].each do |port|
        rule = "INPUT ! -i lo -p tcp -m tcp --dport #{port} -m comment --comment \"disk-monitor #{dir}\" -j REJECT --reject-with icmp-port-unreachable"
        rules[rule] = false
      end
    end
  end

  remove = []
  `iptables -S`.split("\n").each do |line|
    line.strip!
    if line.include?("--comment \"disk-monitor")
      rule = line[3..-1]
      if rules.key?(rule)
        rules[rule] = true
      else
        remove.push(rule)
      end
    end
  end

  remove.each do |rule|
    command = "iptables -D #{rule}"
    log(command)
    `#{command}`
  end

  rules.each do |rule,found|
    if !found
      command = "iptables -I #{rule}"
      log(command)
      `#{command}`
    end
  end
end

def work_loop()
  fifo = File.open($options['fifo'], "r+")
  at_exit { fifo.close() }

  last_iptables_update = Time.now - 86400

  loop do
    ready = select([fifo], nil, nil, $select_timeout)
    update = false

    if !ready.nil?
      begin
        message = ready[0][0].gets()
        split = message.strip.split(',')
        dir = split[0]
        ports = split[1..-1].map {|port| port.to_i}
        if !$monitors.key?(dir)
          update = true
          $monitors[dir] = {
            'heartbeat' => 0,
            'up' => true,
            'ports' => ports
          }
          log("Register #{dir} with ports #{ports.join(',')}")
        elsif $monitors[dir]['ports'] != ports
          update = true
          $monitors[dir]['ports'] = ports
          log("New ports for #{dir}: #{ports.join(',')}")
        end

        $monitors[dir]['heartbeat'] = Time.now
      rescue
        log("failed to read from fifo when it reported ready")
      end
    end

    cutoff = Time.now - $options['heartbeat']
    $monitors.each do |dir,data|
      up = data['heartbeat'] > cutoff
      if up != data['up']
        log("#{dir} - #{up ? 'UP' : 'DOWN'}")
        data['up'] = up
        update = true
      end
    end

    if update || last_iptables_update < Time.now - 60
      update_iptables()
      last_iptables_update = Time.now
    end
  end
end

def create_fifo()
  if !File.exists?(File::dirname($options['fifo']))
    system("/bin/mkdir", "-p", File::dirname($options['fifo']))
  end

  if !File.exists?($options['fifo'])
    log("making fifo #{$options['fifo']}")
    system("/usr/bin/mkfifo", $options['fifo'])
  else
    log("fifo #{$options['fifo']} already exists")
  end
end


###
# MAIN
###

if $options['daemon']
  daemonize()
  write_pid()
  at_exit { clean_pid() }
end

create_fifo()
work_loop()


