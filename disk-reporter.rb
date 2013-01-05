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
require 'fileutils'


###
# Parse command line options
###

$options = {
  'pidfile' => false,
  'logfile' => false,
  'fifo'    => '/var/run/disk-monitor.fifo',
  'daemon'  => false,
  'monitor' => false,
  'ports'   => false,
  'sleep'   => 1,
  'touch'   => '.disk-monitor'
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-h", "--help", :NONE, "Shows this message") do
    puts opts
    exit 0
  end

  opts.on("-p", "--pidfile", :REQUIRED, String, "Set the pidfile.") do |pidfile|
    $options['pidfile'] = pidfile
  end

  opts.on("-l", "--logfile", :REQUIRED, String, "Set the logfile.") do |logfile|
    $options['logfile'] = logfile
  end

  opts.on("-f", "--fifo", :REQUIRED, String, "Set the Linux FIFO file through which this reporter will report to the monitor. (Default: #{$options['fifo']})") do |fifo|
    $options['fifo'] = fifo
  end

  opts.on("-d", "--[no-]daemonize", :NONE, "Daemonize this program on startup. (Default: #{$options['daemon']})") do |daemon|
    $options['daemon'] = daemon
  end

  opts.on("-m", "--monitor", :REQUIRED, String, "Directory to monitor.") do |dir|
    $options['monitor'] = File.expand_path(dir)
  end

  opts.on("-P", "--ports", :REQUIRED, String, "Ports to close if directory is not responsive.") do |ports|
    $options['ports'] = ports.split(",")
  end

  opts.on("-s", "--sleep", :REQUIRED, Integer, "Set the number of seconds to sleep between each touch/report cycle. (Default: #{$options['sleep']} seconds)") do |sleep|
    $options['sleep'] = sleep
  end

  opts.on("-t", "--touchfile", :REQUIRED, String, "Set the touchfile name inside of the monitored directory. (Default: #{$options['touch']})") do |touch|
    $options['touch'] = touch
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

def work_loop()
  touchfile = "#{$options['monitor']}/#{$options['touch']}"
  message = "#{$options['monitor']},#{$options['ports'].join(",")}"

  loop do
    begin
      FileUtils.touch(touchfile)
      File.open($options['fifo'], 'a') {|f| f.write("#{message}\n") }
      log("Sent: #{message}")
    rescue Errno::ENOENT => error
      log("[ERROR] #{error}")
    end
    
    sleep($options['sleep'])
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

%w{ pidfile logfile fifo monitor ports touch }.each do |key|
  if !$options[key]
    puts "Missing #{key}!"
    exit 1
  end
end

if !File.directory?($options['monitor'])
  log("Monitor directory #{$options['monitor']} does not exist")
  exit 1
end

if $options['daemon']
  daemonize()
  write_pid()
  at_exit { clean_pid() }
end

create_fifo()
work_loop()


