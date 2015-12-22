#!/bin/tclsh
#
# required packages
#
package require mysqltcl
#
set lights "2 3 4"
set version "resetLights V0.1"
#
# Connect to the homeDB
#
proc loginDB {} {
   global dbHandle
   if {![info exists dbHandle]} {
      set dbHandle [::mysql::connect -db home -user root -password hyperion]
      ::mysql::autocommit $dbHandle true
   }
   return $dbHandle
}
#
# Issue DB command 
#
proc dbCmd {sql} {
   return [::mysql::exec [loginDB] $sql]
}
#
# Main
#
puts "$version"
set now [ clock seconds ]
set nowT [ clock format $now -format "%Y-%m-%d %H:%M:%S" ]
#
# Reset the light status
#
foreach light $lights {
  puts "Resetting light $light"
  set sqlcmd "insert into HomeLights (light,lightstatus,time_stamp) values ($light,0,'$nowT')"
  set dbStatus [dbCmd $sqlcmd]  
}
#
# Events Ends
#
puts "Event Ends."
