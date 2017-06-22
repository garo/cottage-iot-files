#!/usr/bin/ruby

# Reads power usage from E2 CLASSIC wireless energy monitor, available from Clas Ohlson
# requires https://github.com/merbanan/rtl_433
# Sends data to mosquitto (apt-get install mosquitto-clients)

require 'json'

IO.popen("rtl_433 -d 0 -f 433500000 -R 36 -q -F json") do |io|
  while (line = io.gets) do
    if line[0] == '{'
      begin
        data = JSON.parse(line)
        result = {
          "value" => data["current"],
          "battery" => data["battery"] == "OK" ? 1 : 0,
          "interval" => data["interval"]
	      }
	      `mosquitto_pub -h 172.16.153.2 -t nest/power/current -m '#{result.to_json}'`
      rescue JSON::ParseError
      end
    end
  end 
end
