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


$0 = 'disk-reporter ' + ARGV.join(' ')

require 'getoptlong'
require 'fileutils'

def help()
  puts "#{__FILE__} [OPTIONS]

Options:
	-h, --help 		Show this help

	-p, --pidfile		Set the pidfile
				Required

	-l, --logfile		Log to this file
				Required

	-f, --fifo		Set the fifo to listen to
				Default: /var/run/disk-monitor.fifo

	-d, --daemonize		Daemonize
				Default: false

	-m, --monitor		Directory to monitor
				Example: -m /var/www
				Required

	-P, --ports		Ports to close if directory is not responsive
				Example: -P 80,443
				Required

	-s, --sleep		Seconds to sleep between each report
				Default: 1

	-t, --touchfile		File to touch in directory
				Default: .diskmonitor

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

def work_loop()
  touchfile = "#{$monitor_directory}/#{$touchfile}"
  message = "#{$monitor_directory},#{$ports.join(",")}"

  loop do
    begin
      FileUtils.touch(touchfile)
      File.open($fifo, 'a') {|f| f.write("#{message}\n") }
    rescue Errno::ENOENT => error
      log("[ERROR] #{error}")
    end
    
    sleep($sleep)
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
  ['--pidfile', '-p', GetoptLong::REQUIRED_ARGUMENT],
  ['--logfile', '-l', GetoptLong::REQUIRED_ARGUMENT],
  ['--fifo', '-f', GetoptLong::OPTIONAL_ARGUMENT],
  ['--daemonize', '-d', GetoptLong::OPTIONAL_ARGUMENT],
  ['--monitor', '-m', GetoptLong::REQUIRED_ARGUMENT],
  ['--ports', '-P', GetoptLong::REQUIRED_ARGUMENT],
  ['--sleep', '-s', GetoptLong::OPTIONAL_ARGUMENT],
  ['--touchfile', '-t', GetoptLong::OPTIONAL_ARGUMENT]
)

$pidfile = nil
$logfile = nil
$fifo = "/var/run/disk-monitor.fifo"
$monitor_directory = nil
$ports = nil
$sleep = 1
$touchfile = ".diskmonitor"
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
    when '--monitor'
      $monitor_directory = arg
      if !File.directory?($monitor_directory)
        log("Monitor directory #{$monitor_directory} does not exist")
      end
    when '--ports'
      $ports = arg.split(",")
    when '--sleep'
      $sleep = arg.to_i
    when '--touchfile'
      $touchfile = arg
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


