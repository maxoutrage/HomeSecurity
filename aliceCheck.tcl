#!/usr/bin/tclsh
#
# Verify Camera's are online and working
#
# Select each camera from the available camera's
# For each camera verify that the camera is working and online
# If the camera is not available then reset the camera and report all events
#
package require mysqltcl
package require logger
package require Expect
#
set version                "0.1"
set piUsername             "pi"
set piPassWord             "raspberry"
set cameraIP               "10.0.0.16 10.0.0.17 10.0.0.18 10.0.0.19"
set cameraName             "DriveWay  GarageDoor FrontDoorIN  FrontDoorOut"
set br                     "/usr/local/bin/br --house=A --on=16"
set promptMatch            "raspberrypi.* "
set processCheck           "pgrep -c motion"
log_user 0
#
set timeout 10
match_max 10000
#
# log to file
#
proc log_to_file { txt } {
    set prefix "::aliceCheck "
    set logfile "/home/phall/log/aliceHome.log"
    set msg "\[[clock format [clock seconds]]\] $prefix $txt"
    set f [open $logfile {WRONLY CREAT APPEND}] 
    fconfigure $f -encoding utf-8
    set msg [string map { "-_logger::service" "" } $msg]
    puts $f $msg
    close $f
}
#
# For each camera 
#   check that each camera is accessable and that the software is running  
#   generate an alarm if a camera is not accessable
#   if the camera software is not running then do not issue an alarm but attempt to restart it 
#
set log [logger::init aliceHome::aliceCheck]
${log}::logproc info log_to_file
${log}::info "Events Begins"
${log}::info "$version"
for {set i 0} {$i < [llength $cameraIP]} {incr i} {
    set camera [lindex $cameraIP $i]
    set cameraDescription [lindex $cameraName $i]
    ${log}::info "Checking $cameraDescription ($camera)"
    spawn ssh -l $piUsername $camera
    expect {
	timeout { 
	    ${log}::alert "Timed out while attempting to connect. Triggering alarm"
	    exec {*}{br --house=A --on=16}
	    exit
	}
	"No route to host" {
            ${log}::alert "Appears down. Triggering Alarm"
	    exec {*}{br --house=A --on=16}
            exit
	}
	"password:" {send "$piPassWord\r"}
    }
    ${log}::info "Connected to $cameraDescription"
    ${log}::info "Checking motion package is running on $cameraDescription"
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
    ${log}::info "$cameraDescription $testResult"
    if { $testResult == "NOT running." } {
      ${log}::info "Attempting to restart motion package for $cameraDescription"
      set timeout 300
      send "sudo /etc/init.d/motion restart\r"
      expect {
          timeout { ${log}::critical "Timed out restarting the motion package" }
          -re $promptMatch { ${log}::info "motion package for $cameraDescription has been restarted" }
      }
    } 
}
${log}::info "Event Ends."
exit
