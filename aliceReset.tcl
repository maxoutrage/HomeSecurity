#!/bin/tclsh
#
# required packages
#
package require mysqltcl
package require logger
#
set lights "2 3 4"
set version "0.1"
#
# Logger to file
#
proc log_to_file {txt} {
    set prefix "::aliceResetStatus"
    set logfile "/home/phall/log/aliceHome.log"
    set msg "\[[clock format [clock seconds]]\] $prefix $txt"
    set f [open $logfile {WRONLY CREAT APPEND}] 
    fconfigure $f -encoding utf-8
    set msg [string map { "-_logger::service" "" } $msg]
    puts $f $msg
    close $f
}
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
set log [logger::init aliceResetStatus]
${log}::logproc info log_to_file
${log}::info "Events Begins"
${log}::info "$version"
set now [ clock seconds ]
set nowT [ clock format $now -format "%Y-%m-%d %H:%M:%S" ]
#
# Reset the light status
#
foreach light $lights {
  ${log}::info "Resetting light $light"
  set sqlcmd "insert into HomeLights (light,lightstatus,time_stamp) values ($light,0,'$nowT')"
  set dbStatus [dbCmd $sqlcmd]  
}
#
# Events Ends
#
${log}::info "Event Ends."
exit
