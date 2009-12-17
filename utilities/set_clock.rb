#!/usr/bin/ruby

require "rubygems"
# From http://ruby-serialport.rubyforge.org/
require "serialport"

puts "Connecting to Arduino on #{ARGV[0]}"
SerialPort.open(ARGV[0], 9600, 8, 1, SerialPort::NONE) do |sp|
  sleep 5
  puts "Connected?"
  buf = ""; while (! /.* Ready\r\n/.match(buf)) do 
    printf("%c", t = sp.getc)
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
