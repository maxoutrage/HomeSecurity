#!/usr/bin/python
#
# P.A.Hall	18th March 2016
#
# motionClient
#  setup motion sensor
#  create socket to aliceServer
#  detect the change in state from the motion sensor
#  on change in state
#    send signal to aliceServer
#    on socket timeout
#      close the current socket and open new socket
#
import RPi.GPIO as GPIO
import socket
import time
import sys
import platform
#
hostname = platform.node()
sensor = 4
port   = 6004
host   = "neuromancer"
#
previous_state = False
current_state  = False
#
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
#print "Connecting to %s on port %s..." % (host,port)
try:
  s.connect((host, port))
except socket.error, message:
  print 'Socket Error %s' % (message)
  exit
#
s.settimeout(2.0)
s.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
#
GPIO.setmode(GPIO.BCM)
GPIO.setup(sensor, GPIO.IN, GPIO.PUD_DOWN)
#print "Reading from sensor pin %s" % (sensor)
#
while True:
    time.sleep(0.1)
    previous_state = current_state
    current_state  = GPIO.input(sensor)
    if current_state != previous_state:
        new_state = "HIGH" if current_state else "LOW"
        state = "MOTION/%s/%s\n" % (hostname,new_state)
        #print '%s' % (state)
        try:
          s.sendall(state)
        except socket.error:
          s.close()
          #print 'Socket timeout, destroy and re-create the socket'
          time.sleep( 2.0)
          s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
          s.connect((host, port))
          s.settimeout(2.0)
          s.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
          #print 'Socket re-created to %s %s' % (host,port)
