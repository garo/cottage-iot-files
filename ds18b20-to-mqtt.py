#!/usr/bin/python

import os
import glob
import time
import httplib
import urllib
import string

base_dir = '/sys/bus/w1/devices/'
devices = glob.glob(base_dir + '28*')
#device_file = device_folder + '/w1_slave'

meters = {
  '28-0000073c4f25':'jarvi',
  '28-0000073bb17c':'saunakamari',
  '28-0000073bbf90':'sauna'
}

def read_temp_raw(device_file):
    f = open(device_file, 'r')
    lines = f.readlines()
    f.close()
    return lines

def read_temp(device_file):
    lines = read_temp_raw(device_file)
    while lines[0].strip()[-3:] != 'YES':
        time.sleep(0.2)
        lines = read_temp_raw()
    equals_pos = lines[1].find('t=')
    if equals_pos != -1:
        temp_string = lines[1][equals_pos+2:]
        temp_c = float(temp_string) / 1000.0
        temp_f = temp_c * 9.0 / 5.0 + 32.0
        return temp_c

for d in devices:
    try:
        id = string.split(d, "/")[5]
        temp = read_temp(d + "/w1_slave")
        os.system("mosquitto_pub -h 172.16.153.2 -t nest/sauna/%s -m %.2f" % (meters[id], temp))
    except Exception, e:
        print e.__doc__
        print e.message

