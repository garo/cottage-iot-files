#!/usr/bin/ruby
require 'logger'

require 'mqtt'

log = Logger.new('/tmp/esp.log')


class RingBuffer < Array
  attr_reader :max_size

  def initialize(max_size, enum = nil)
    @max_size = max_size
    enum.each { |e| self << e } if enum
  end

  def <<(el)
    if self.size < @max_size || @max_size.nil?
      super
    else
      self.shift
      self.push(el)
    end
  end

  alias :push :<<
end


sauna_temps = RingBuffer.new(5)
sauna_state = :sauna_off 
sauna_alerted = 0
previous_alert = Time.now - 60*3

def delta_t(sauna_temps)
  dTemp = (sauna_temps.last[0] - sauna_temps.first[0])
  dTime = sauna_temps.last[1].to_i - sauna_temps.first[1].to_i
  return {
    :temp => dTemp,
    :time => dTime,
    :samples => sauna_temps.length
  }
end

MQTT::Client.connect('127.0.0.1') do |c|
  c.subscribe('nest/sauna/sauna')
  c.subscribe('nest/sauna/jarvi')
  log.debug "Connected and subscribed to mqtt queues"
  #c.publish('nest/displays/60:01:94:0B:52:47/r0', "jee \1\2")
  
  c.get do |topic,message|
    log.debug "topic: #{topic} with message: #{message}"
    if topic == 'nest/sauna/sauna'
      temp = message.to_f
      sauna_temps << [temp, Time.new]
      delta = delta_t(sauna_temps)
      if delta[:temp] > 0
        arrow = " \1#{delta[:temp].round}"
      elsif delta[:temp] < 0
        arrow = " \2#{delta[:temp].round}"
      else
        arrow = ""
      end
      c.publish('nest/displays/60:01:94:0B:52:47/r0', "Sauna: #{temp.round}#{arrow}'C")
      if sauna_state == :sauna_off && temp > 40.0 && sauna_temps.first[0] < temp
	sauna_state = :sauna_warming 
        previous_alert = Time.now
        sauna_alerted = 0
        log.debug "Sauna is starting to warm up"
      elsif sauna_state == :sauna_warming 
        if temp > 80
          sauna_state = :sauna_warm
          c.publish('nest/displays/60:01:94:0B:52:47/beep', "1")
        else 
          if delta[:temp] < 2 && sauna_alerted < 3 && previous_alert + 60*3 < Time.now
            log.info "Alerting for more wood into sauna. delta: #{delta.round}, sauna_alerted: #{sauna_alerted}"
            c.publish('nest/displays/60:01:94:0B:52:47/beep', "1")
            c.publish('nest/displays/60:01:94:0B:52:47/r1', "Lis#{225.chr}#{225.chr} puita!")
            sauna_alerted += 1
            previous_alert = Time.now
          end
        end
      elsif sauna_state == :sauna_warm 
        if temp < 50
          log.info "Sauna temp is #{temp}, marking sauna state to :sauna_off"
          sauna_state = :sauna_off 
        end
      end 
     
      log.debug "delta: #{delta_t(sauna_temps)}, sauna state: #{sauna_state}" 
    end
    if topic == 'nest/sauna/jarvi'
      temp = message.to_f.round
      c.publish('nest/displays/60:01:94:0B:52:47/r1', "J#{225.chr}rvi: #{temp}'C")
    end
  end
end
