#!/bin/tclsh
#
# Server side for the android client to control homeLights
#
# 12/27/15	P.A.Hall	With state change to ON for any light update the DB with status = 2 = manual on
#                               this status is used by aliceHome in further checks
# 02/27/16	P.A.Hall	Added receiving movement updates from PI's
#
package require mysqltcl
package require logger
#
# logger
#
proc log_to_file {txt} {
    set logfile "/home/phall/log/aliceHome.log"
    set msg "\[[clock format [clock seconds]]\] $txt"
    set f [open $logfile {WRONLY CREAT APPEND}] 
    fconfigure $f -encoding utf-8
    set msg [string map { "-_logger::service" "" } $msg]
    puts $f $msg
    close $f
}
#
# Retrieve the light status from the DB
#
proc retrieveLightStatus { light } {
  set m [mysqlconnect -user root -db home -password hyperion] 
  #set mysqlQuery "select lightstatus from HomeLights where light = $light and light is not NULL and time_stamp = (select max(time_stamp) from HomeLights)"
  set mysqlQuery  "select lightstatus from HomeLights where light = $light and lightstatus is not NULL order by time_stamp DESC limit 1"
  set status [mysqlsel $m $mysqlQuery -flatlist]
  if { $status == "" } { set status 0 }
  mysqlclose $m
  return $status
}
#
# Connect to the homeDB
# The DB connection can timeout - if the dbHandle exist then ping the DB
# if the db ping fails then the connection was closed so reconnect to the DB.
#
proc loginDB {} {
   global dbHandle
   set log [logger::init ::aliceServer::loginDB]
   if {![info exists dbHandle]} {
      set dbHandle [::mysql::connect -db home -user root -password hyperion]
      ::mysql::autocommit $dbHandle true
      ${log}::info "Connected to DB"
   } else {
       if {![mysqlping $dbHandle]} {
         set dbHandle [::mysql::connect -db home -user root -password hyperion]
         ${log}::error "DB Ping failed - reconnected to DB"
       }
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
# update the DB when motion is detected
#
proc motionDetected { location state } {
  set log [logger::init ::aliceServer::motiondetected]
  ${log}::info "Detected motion $location state is $state"
  set now    [clock seconds]
  set nowT   [clock format $now -format "%Y-%m-%d %H:%M:%S"]
  set sqlcmd "insert into motion (description,motion,time_stamp) values ('$location','$state','$nowT')"
  set dbStatus [dbCmd $sqlcmd]
  ${log}::info "Return status after insert on DB was $dbStatus"
  return
}
#
# Control appliance on/off
# 
proc bottleRocket { appliance state } {
  set log [logger::init ::aliceServer::BR]
  ${log}::info "Appliance $appliance changed to state $state"
  set now  [ clock seconds ]
  set nowT [ clock format $now -format "%Y-%m-%d %H:%M:%S" ]
  set state [string tolower $state]
  #set appliance [string range $appliance 1 1]
  exec /usr/local/bin/br --house=A --$state=$appliance
  exec /usr/local/bin/br --house=A --$state=$appliance
  if {$state == "on"  } { set state 2 }
  if {$state == "off" } { set state 0 }
  set sqlcmd "insert into HomeLights (light,lightstatus,time_stamp) values ($appliance,$state,'$nowT')"
  set dbStatus [dbCmd $sqlcmd]
  return
}
# AliceServer --
#	Open the server listening socket
#	and enter the Tcl event loop
#
# Arguments:
#	port	The server's port number
proc AliceServer {port} {
    set log [logger::init ::aliceServer::AliceServer]
    ${log}::info "Listening on port $port for requests and events"
    set s [socket -server AliceAccept $port]
    vwait forever
}
# AliceAccept --
#	Accept a connection from a new client.
#	This is called after a new socket connection
#	has been created by Tcl.
#
# Arguments:
#	sock	The new socket connection to the client
#	addr	The client's IP address
#	port	The client's port number
proc AliceAccept {sock addr port} {
  global echo
  set log [logger::init ::aliceServer::AliceAccept]
  ${log}::info "New connection from $addr port $port"
  set echo(addr,$sock) [list $addr $port]
  fconfigure $sock -buffering line -blocking 0
  fileevent $sock readable [list AliceEcho $sock]
  puts $sock "1000  X10Commander Server"
}
proc sendDeviceList { sock } {
  set cmdEnd "ENDLIST"
  set lightName   "LivingRoom DinningRoom BackDeck MasterBedroom FrontBedroom KitchenLights DiningRoomFan SoundAlarm"
  set lightNumber "3 2 5 4 6 7 8 16"
  foreach light $lightNumber name $lightName {
    puts $sock "Device~$name~A$light~0"
  }
  puts $sock $cmdEnd
}
proc updateDeviceStatus { sock } {
  set lightName   "LivingRoom DinningRoom BackDeck MasterBedroom FrontBedroom KitchenLights DiningRoomFan SoundAlarm"
  set lightNumber "3 2 5 4 6 7 8 16"
  foreach light $lightNumber name $lightName {
    set status [ retrieveLightStatus $light ]
    puts $sock "Update~$name~A$light~$status"
  }
}
# AliceEcho --
#	This procedure is called when a client sends a request
#
# Arguments:
#	sock	The socket connection to the client
proc AliceEcho { sock } {
  global echo
  set log [logger::init ::aliceServer::AliceEcho]
  set BRAlarm        "16"
  set motionDetected "HIGH"
  set password       "PASSWORD~bz2uhm"
  set version        "VER~2.10 (1.2.1)."
  set cmdList        "LIST"
  set cmdMsg         "MSG~HEYU"
  set cmdDev         "DEVICE~sendplc*"
  set cmdMov         "MOTION*"
  #
  # Check end of file or abnormal connection drop and handle the event
  #   else check the command and respond accordingly
  #
  if {[eof $sock] || [catch {gets $sock line}]} {
    close $sock
    unset echo(addr,$sock)
    ${log}::info "Socket closed"
  } else {
    ${log}::info "Input from object received - $line"
    if  { $line == "$password" } {
      ${log}::info "Matched Password"
      ${log}::info "Sending version"
      puts $sock $version
    }
    if { $line == $cmdList } {
      ${log}::info "Sending device list to handset"
      sendDeviceList $sock
      ${log}::info "Sending device status to handset"
      updateDeviceStatus $sock
    }
    if { [string match $cmdDev $line] } {
      set output [string range $line [expr {[string last "~" $line] + 2}] end-1]
      set appliance [lindex $output 0]
      set state     [lindex $output 1] 
      ${log}::info "Change in state for $appliance to $state"
      set appliance [string range $appliance 1 1]
      set status [bottleRocket $appliance $state]
    }
    if { [string match $cmdMov $line] } {
      set location [lindex [split $line "/"] 1 ]
      set state    [lindex [split $line "/"] 2 ]
      set status [motionDetected $location $state]
    }
  }
}
#
# Enter the server loop
#
set log [logger::init aliceServer]
${log}::logproc info log_to_file
AliceServer 6004
