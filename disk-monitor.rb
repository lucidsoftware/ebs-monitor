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


$0 = 'disk-monitor ' + ARGV.join(' ')

require 'getoptlong'

def help()
  puts "#{__FILE__} [OPTIONS]

Options:
	-h, --help 		Show this help

	-p, --pidfile		Set the pidfile
				Default /var/run/disk-monitor.pid

	-l, --logfile		Log to this file
				Default: /var/log/disk-monitor.log

	-f, --fifo		Set the fifo to listen to
				Default: /var/run/disk-monitor.fifo

	-d, --daemonize		Daemonize
				Default: false

	-b, --heartbeat		Elapsed time between heartbeats before a directory will be marked as 'down'
				Default: 5

	-w, --wait		Seconds from start of script to wait before updating iptables
				Default: 60

"
end

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
  File.open($logfile, 'a') {|f| f.write("#{full_message}\n") }
end

def write_pid()
  File.open($pidfile, 'w') {|f| f.write("#{$$}") }
  log("wrote pid to #{$pidfile}")
end

def clean_pid()
  File.delete($pidfile)
  log("removed pidfile #{$pidfile}")
end

def update_iptables()
  if Time.now < $start_update_iptables
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
    `#{command}`
#    log(command)
  end

  rules.each do |rule,found|
    if !found
      command = "iptables -I #{rule}"
      `#{command}`
#      log(command)
    end
  end
end

def work_loop()
  fifo = File.open($fifo, "r+")
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

    cutoff = Time.now - $heartbeat
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
  if !File.exists?(File::dirname($fifo))
    system("/bin/mkdir", "-p", File::dirname($fifo))
  end

  if !File.exists?($fifo)
    log("making fifo #{$fifo}")
    system("/usr/bin/mkfifo", $fifo)
  else
    log("fifo #{$fifo} already exists")
  end
end




#
# MAIN
#

opts = GetoptLong.new(
  ['--help', '-h', GetoptLong::NO_ARGUMENT],
  ['--pidfile', '-p', GetoptLong::OPTIONAL_ARGUMENT],
  ['--logfile', '-l', GetoptLong::OPTIONAL_ARGUMENT],
  ['--fifo', '-f', GetoptLong::OPTIONAL_ARGUMENT],
  ['--daemonize', '-d', GetoptLong::OPTIONAL_ARGUMENT],
  ['--heartbeat', '-b', GetoptLong::OPTIONAL_ARGUMENT],
  ['--wait', '-w', GetoptLong::OPTIONAL_ARGUMENT]
)

$pidfile = "/var/run/disk-monitor.pid"
$logfile = "/var/log/disk-monitor.log"
$fifo = "/var/run/disk-monitor.fifo"
$monitors = {}
$heartbeat = 5
$select_timeout = 2
$start_update_iptables = Time.now + 60
daemonize = false
run = true

opts.each do |opt, arg|
  case opt
    when '--help'
      help()
      run = false
    when '--pidfile'
      $pidfile = arg
    when '--logfile'
      $logfile = arg
    when '--fifo'
      $fifo = arg
    when '--daemonize'
      daemonize = true
    when '--heartbeat'
      $heartbeat = arg.to_i
    when '--wait'
      $start_update_iptables = Time.now + arg.to_i
  end
end

if run
  if daemonize
    daemonize()
    write_pid()
    at_exit { clean_pid() }
  end

  create_fifo()
  work_loop()
end


