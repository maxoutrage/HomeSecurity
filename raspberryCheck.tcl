#!/usr/bin/expect
#
# Verify Camera's are online and working
#
# Select each camera from the available camera's
# For each camera verify that the camera is working and online
# If the camera is not available then reset the camera and report all events
#
package require mysqltcl
#
set version                "0.0.01"
set piUsername             "pi"
set piPassWord             "raspberry"
set cameraIP               "10.0.0.16 10.0.0.17 10.0.0.18 10.0.0.19"
set cameraName             "DriveWay  GarageDoor FrontDoorIN  FrontDoorOut"
set br                     "/usr/local/bin/br --house=A --on=16"
set promptMatch            "raspberrypi.* "
set processCheck           "pgrep -c motion"
set logFile                "/mnt/prachett/logs/raspberryCheck.log"
#
log_user 0
set timeout 10
match_max 10000
#
# For each camera 
#   check that each camera is accessable and that the software is running  
#   generate an alarm if a camera is not accessable
#   if the camera software is not running then do not issue an alarm but attempt to restart it 
#
puts "motionCheck $version"
#
#
#
#set fp [open $logFile w]
#puts $fp "MotionCheck $version"
#puts $fp "Camera's are/t$cameraIP"
#puts $fp "Camera are/t$cameraName"
# 
for {set i 0} {$i < [llength $cameraIP]} {incr i} {
    set camera [lindex $cameraIP $i]
    set cameraDescription [lindex $cameraName $i]
    puts "Checking $cameraDescription\t($camera)..."
#
    spawn ssh -l $piUsername $camera
    expect {
	timeout { 
	    puts "\tTimed out while attempting to connect. Triggering alarm..."
	    exec {*}{br --house=A --on=16}
	    exit
	}
	"No route to host" {
            puts "\tAppears down. Triggering Alarm..."
	    exec {*}{br --house=A --on=16}
            exit
	}
	"password:" {send "$piPassWord\r"}
    }
    puts "\tConnected"
    puts -nonewline "\tChecking motion..."
    expect {
	-re $promptMatch { 
	    send "$processCheck\r" 
	}
    }
    expect {
	-re $promptMatch {
            send "echo code=$?\r"
        }
    }
    set testResult "NOT running."
    expect {
	"code=0" { set testResult "IS running" }
    }
    puts "\t$testResult"
    if { $testResult == "NOT running." } {
      puts -nonewline "\tAttempting to restart motion..."
      set timeout 300
      send "sudo /etc/init.d/motion restart\r"
      expect {
          timeout { send_user "\n\terror: timed out restarting motion!" }
          -re $promptMatch { puts "Restarted!" }
      }
    } 
}
exit
