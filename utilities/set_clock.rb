#!/usr/bin/ruby

# TODO: Check that argv[0] contains a serial port
# TODO: If above fails, print usage info.

require "rubygems"
# From http://ruby-serialport.rubyforge.org/
require "serialport"

puts "Connecting to Arduino on #{ARGV[0]}"
SerialPort.open(ARGV[0], 9600, 8, 1, SerialPort::NONE) do |sp|
  # Set serial port timeout to infinite (defaults to -1 on Linux)
  sp.read_timeout = 0

  sleep 5
  puts "Waiting for POWER_ON message from Arduino"
  buf = ""; while (! /.* POWER_ON.*\n/.match(buf)) do
    t = sp.getc
    printf("%c", t)
    buf << t
  end
  now = Time.now
  sp.write 'T' 
  sp.putc(now.year - 2000)
  sp.putc(now.month)
  sp.putc(now.day)
  sp.putc(now.wday)
  sp.putc(now.hour)
  sp.putc(now.min)
  sp.putc(now.sec)
  t = 0; while (t != ?\n) do printf("%c", t = sp.getc) end
end
