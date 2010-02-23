#!/usr/bin/ruby

# To use this, set:
#  HACKPGH_GOOGLE_USER to your HackPGH google apps account
#  HACKPGH_GOOGLE_KEY to your password for said account
#  HACKPGH_GOOGLE_MEMBER_SHEET to the members worksheet key (it's part of the URL)

# TODO: Check for existance of environment variables
# TODO: Check that argv[0] contains a serial port
# TODO: If either fails, print usage info.

# TODO: Check that we can open the serial port, before bothering to go out to the net?

require "rubygems"
# From http://github.com/gimite/google-spreadsheet-ruby
require "google_spreadsheet"
# From http://ruby-serialport.rubyforge.org/
require "serialport"

# Log in.
session = GoogleSpreadsheet.login(ENV['HACKPGH_GOOGLE_USER'], 
                                  ENV['HACKPGH_GOOGLE_KEY'])

# First worksheet of the HackPGH members list spreadsheet
ws = session.spreadsheet_by_key(ENV['HACKPGH_GOOGLE_MEMBER_SHEET']).worksheets[0]

# Gather RFID IDs for active users
# Col 4 is Active/Not, Col -1 (8 doesn't work for some reason) is RFID out
# Col -2 is RFID ID (don't know why 7 doesn't work)
rfid_tags = ws.rows.select{|r| r[4] == 'Y' && r[-1] == 'Y'}.map{|r| r[-2].gsub(/"/,'')}

puts "About to write #{rfid_tags.size} RFID Tags"
puts "Connecting to Arduino on port #{ARGV[0]}"

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
  sp.write 'U' 
  t = 0; while (t != ?\n) do printf("%c", t = sp.getc) end
  sp.putc rfid_tags.size
  t = 0; while (t != ?\n) do printf("%c", t = sp.getc) end
  rfid_tags.each do |tag|
    sp.write tag
    t = 0; while (t != ?\n) do printf("%c", t = sp.getc) end
  end
  puts "Done?"
  t = 0; while (t != ?\n) do printf("%c", t = sp.getc) end
end
