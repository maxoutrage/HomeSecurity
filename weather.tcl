#!/bin/tclsh
#
# required packages
#
package require http
package require tdom
package require mysqltcl
#
# Weather and time constants
#
set delay         "01:30:00"
set delayT        "-60 minutes"
set upStairsON    "20:00:00"
set upStairsOFF   "02:00:00"
set downStairsOFF "02:00:00"
set deckON        "02:00:00"
set deckOFF       "06:00:00"
set noDecisions   "21:00:00"
set yesDecisions  "12:00:00"
set livingRoom    3
set diningRoom    2
set masterBedRoom 4
set deckLight     5
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
# debugging aid to display XML elements and attributes
#
proc explore {parent} {
  set type [$parent nodeType]
  set name [$parent nodeName]
  puts "$parent is a $type node named $name"
  if {$type != "ELEMENT_NODE"} then return
  if {[llength [$parent attributes]]} {
    puts "attributes: [join [$parent attributes] ", "]"
  }
  foreach child [$parent childNodes] {
        explore $child
  }
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
# Retrieve the weather from openweather for Snoqualmie
# and parse out the key values
#
proc getWeather {} {
  set theURL  "http://api.openweathermap.org/data/2.5/weather?zip=98065&mode=xml&units=imperial&APPID=aa5a36d2f31d0d73d32988baf3202c12"
  set token [http::geturl $theURL]
  set doc [dom parse [::http::data $token]] 
  set root [$doc documentElement]
  #explore $root
  set cloudStatus [$root selectNodes /current/clouds]
  set cloudCover  [$cloudStatus getAttribute name]
  set cloudiness  [$cloudStatus getAttribute value]
  set sunStatus   [$root selectNodes /current/city/sun]
  set sunSets     [$sunStatus getAttribute set]
  set tempStatus  [$root selectNodes /current/temperature]
  set currentTemp [$tempStatus getAttribute value] 
  set humStatus   [$root selectNodes /current/humidity]
  set humidity    [$humStatus getAttribute value]
  set preStatus   [$root selectNodes /current/pressure]
  set pressure    [$preStatus getAttribute value]
  set windStatus  [$root selectNodes /current/wind/speed]
  set windSpeed   [$windStatus getAttribute value]
  set windName    [$windStatus getAttribute name]
  set windSource  [$root selectNodes /current/wind/direction]
  set windDirect  [$windSource getAttribute value]
  set rainStatus  [$root selectNodes /current/precipitation]
  set rainMode    [$rainStatus getAttribute mode]

  $doc delete
  http::cleanup $token
  return [ list $cloudStatus $cloudCover $cloudiness $sunStatus $sunSets $currentTemp $humidity $pressure $windSpeed $windName $windDirect $rainMode ]
}
#
# Sleep routine - this may help the br status 
#
proc sleep N {
    after [expr {int($N * 1000)}]
}
#
# Control appliance on/off
# 
proc bottleRocket { house appliance state } {
  if { $house != "A" } {
    puts "error: House not set to A - actual value $house"
    return
  }
  if { $appliance < 0 || $appliance > 16 } {
    puts "error: appliance out of bounds  - actual value $appliance"
  }
  if { $state != "on" && $state != "off" } {
    puts "error: state not set to on or off - actual value $state"
  }
  puts "\tBR $house $state $appliance "
  sleep 1
  exec /usr/local/bin/br --house=$house --$state=$appliance
  sleep 1
  exec /usr/local/bin/br --house=$house --$state=$appliance
}
#
# Adjust the lightsON based on the weather information
# the latest/default lightsON will be (sunSets - delayT)
#
proc upStairsStatus { lightsON upStairsOff weatherStatus cloudCover } {
  set now [ clock seconds ]
  set switchON false
  set normalOff [ clock scan $upStairsOff -format {%H:%M:%S} ]
  set normalOff [ clock add $normalOff 24 hours ]
  set normalON  [ clock scan $lightsON    -format {%H:%M:%S} ]
  #
  if { [expr $now > $normalOff] } {
    set switchON {false}
    return $switchON
  }
  if { [expr $now > $normalON] } {
    set switchON {true}
    return $switchON
  }
  return $switchON
}
proc downStairsStatus { lightsON downStairsOff weatherStatus cloudCover } {
  set now          [ clock seconds ]
  set normalOff    [ clock scan $downStairsOff -format {%H:%M:%S} ]
  set normalOff    [ clock add $normalOff 24 hours ]
  set normalON     $lightsON
  set switchON     {false}
  set earlyTime    "12:00:00"
  set earlyTimeSec [ clock scan $earlyTime -format {%H:%M:%S} ]
  #
  # patterns decide if the lights should be on or off - Default is lights are off
  #
  # late night - lights off
  if { [expr $now > $normalOff] } {
    set switchON {false}
    return $switchON
  }
  # normal switch on time
  set adjustforWeather [ weatherDecision $lightsON $weatherStatus $cloudCover ]
  if { [expr $now > $normalON] } {
    set switchON {true}
    return $switchON
  }
  #
  # weather check
  #
  if { [expr $now > $earlyTimeSec] } {
    set adjustforWeather [ weatherDecision $lightsON $weatherStatus $cloudCover ]
    if { [string is true -strict $adjustforWeather] && [ expr $now > $earlyTimeSec ] } {
      set switchON {true}
      puts -nonewline "weatherDecision is ON. "
      return $switchON
    } else {
      puts -nonewline "weatherDecision is OFF. "
    }
  }
}
proc weatherDecision { lightsON weatherStatus cloudCover } {
  set cloudCoverStates { "clear skys" "few clouds" "scattered clouds" "broken clouds" "overcast clouds" }
  set cloudCoverOffset { 0            0            30                 45              60                }
  set now [ clock seconds ]
  set weatherON {false}
  #
  if { [expr $cloudCover > 90] && [string compare $weatherStatus "overcast clouds"] } {
    set weatherON {true}
    return $weatherON
  }
  if { [expr $cloudCover > 80] && [string compare $weatherStatus "rain"] } {
    set weatherON {true}
    return $weatherON
  }
  return $weatherON
} 
#
# Calculate the sunSET from the returned API information and convert to local time
# Return the original/plain lights on time based on the standard delay
#
proc calculateSunSet { originalSunSetTime delayTime} {
  set SunSetTimeSeconds [clock scan $originalSunSetTime -format {%Y-%m-%dT%T} -timezone :Europe/London]
  set localSunSetTime [clock format $SunSetTimeSeconds -format %H:%M:%S]
  puts "\tLocal sun set time is $localSunSetTime."
  set switchON [ clock scan "$delayTime" -base [clock scan $localSunSetTime ] ]
  return $switchON
}
#
# Main:
# getWeather Status via call to openweather API
# If no decisions are in effect (based on time) then log the weather and exit
# else
#   get the upStairs and downStairs status and switch on / off the lights
# endif
#
# Get the specific weather attributes and sunset time for this lat and long
# 
set weatherAttributes [ getWeather ]
set cloudStatus [ lindex $weatherAttributes 0 ]
set cloudCover  [ lindex $weatherAttributes 1 ]
set cloudiness  [ lindex $weatherAttributes 2 ]
set sunStatus   [ lindex $weatherAttributes 3 ]
set sunSets     [ lindex $weatherAttributes 4 ]
set currentTemp [ lindex $weatherAttributes 5 ]
set currentTemp [ expr { round( $currentTemp ) }  ]
set humidity    [ lindex $weatherAttributes 6 ]
set pressure    [ lindex $weatherAttributes 7 ]
set windSpeed   [ lindex $weatherAttributes 8 ]
set windName    [ lindex $weatherAttributes 9 ]
set windDirect  [ lindex $weatherAttributes 10 ]
set rainMode    [ lindex $weatherAttributes 11 ]
#
# Retrieve current light Status
#
set livingRoomStatus    [ retrieveLightStatus $livingRoom ]
set diningRoomStatus    [ retrieveLightStatus $diningRoom ]
set masterBedRoomStatus [ retrieveLightStatus $masterBedRoom ]
#
# Display the information we have so far
#
set noDecisionsSec  [ clock scan $noDecisions  -format {%H:%M:%S} ]
set yesDecisionsSec [ clock scan $yesDecisions -format {%H:%M:%S} ] 
set now [clock seconds]
set nowT [clock format $now -format %H:%M]
puts "$nowT   Weather, time and lights data is..."
puts "\tCloud Cover is $cloudCover, percentage of cloud cover is $cloudiness%, current temperature is $currentTemp"
puts "\tSun sets $sunSets."
set lightsON [ calculateSunSet $sunSets $delayT ]
puts "\tLights on is [ clock format $lightsON -format %H:%M:%S ]"
puts "\tCurrent light status is $livingRoomStatus $diningRoomStatus $masterBedRoomStatus."
#
# Save the current status to the LightsON table in the home DB
#
set a [ clock format $now      -format "%Y-%m-%d %H:%M:%S" ]
set b [ clock format $lightsON -format "%Y-%m-%d %H:%M:%S" ]
set c [ clock scan $sunSets    -format {%Y-%m-%dT%T} -timezone :Europe/London]
set c [ clock format $c        -format "%Y-%m-%d %H:%M:%S" ]
#
# Decide if decisions on light status should be made ?
# Assuming that if its after a certain time the actual time for bed is indeterminate
# and the lights will be switched off manually. If that decision fails then there is a cron job 
# to switch off everything. The only exception is the outside deck light.
# 
#
# Are decisions made ?
#
if { [expr $now > $noDecisionsSec] || [expr $now < $yesDecisionsSec]} {
  puts "\tNo Decisions is in effect!"
  set sqlcmd "insert into HomeLights (cloudname,cloudcover,temperature,humidity,pressure,windspeed,windname,winddirect,rainmode,sunset,lightson,time_stamp) values ('$cloudCover',$cloudiness,$currentTemp,$humidity,$pressure,$windSpeed,'$windName',$windDirect,'$rainMode','$c','$b','$a')"
  set dbStatus [dbCmd $sqlcmd]
  exit
}
#
# SwitchON upstairs lights ?
#
puts -nonewline "\tLights Status upStairs..."
set lightStatus [ upStairsStatus $upStairsON $upStairsOFF $cloudCover $cloudiness ]
puts -nonewline "Done. "
if { [string is true -strict $lightStatus] } {
  puts " Up Stairs lights ON."
  if { [retrieveLightStatus $masterBedRoom] == 0 } {
    puts "\tChange in Status."
    bottleRocket A $masterBedRoom on
    set sqlcmd "insert into HomeLights (light,lightstatus,time_stamp) values (4,1,'$a')"
    set dbStatus [dbCmd $sqlcmd]
  }
} else {
  puts " Up Stairs lights OFF."
  if { [retrieveLightStatus $masterBedRoom] == 1 } {
    puts "\tChange in Status."
    bottleRocket A $masterBedRoom off
    set sqlcmd "insert into HomeLights (light,lightstatus,time_stamp) values (4,0,'$a')"
    set dbStatus [dbCmd $sqlcmd]
  }
}
#
# SwitchON downStairs lights
#
puts -nonewline "\tLights Status downStairs..."
set lightStatus [ downStairsStatus $lightsON $downStairsOFF $cloudCover $cloudiness ]
puts -nonewline "Done. "
if { [string is true -strict $lightStatus] } {
  puts "Down Stairs lights ON."
  set lightONOFF [ retrieveLightStatus $diningRoom ]
  if { 0 == $lightONOFF } {
    puts "\tChange in status."
    bottleRocket A $diningRoom on
    set sqlcmd "insert into HomeLights (light,lightstatus,time_stamp) values (2,1,'$a')"
    set dbStatus [dbCmd $sqlcmd]
  }
  set lightONOFF [ retrieveLightStatus $livingRoom ]
  if { 0 == $lightONOFF } {
    puts "\tChange in Status."
    bottleRocket A $livingRoom on
    set sqlcmd "insert into HomeLights (light,lightstatus,time_stamp) values (3,1,'$a')"
    set dbStatus [dbCmd $sqlcmd]
  }
} else {
  puts "Down Stairs lights OFF."
  if { [retrieveLightStatus $diningRoom] == 1 } {
    puts "\tChange in Status."
    bottleRocket A $diningRoom off
    set sqlcmd "insert into HomeLights (light,lightstatus,time_stamp) values (2,0,'$a')"
    set dbStatus [dbCmd $sqlcmd]
  }
  if { [retrieveLightStatus $livingRoom] == 1 } {
    puts "\tChange in Status."
    bottleRocket A $livingRoom off
    set sqlcmd "insert into HomeLights (light,lightstatus,time_stamp) values (3,0,'$a')"
    set dbStatus [dbCmd $sqlcmd]
  }
}
#
# Event Ends, save the current weather data
#
set sqlcmd "insert into HomeLights (cloudname,cloudcover,temperature,humidity,pressure,windspeed,windname,winddirect,rainmode,sunset,lightson,time_stamp) values ('$cloudCover',$cloudiness,$currentTemp,$humidity,$pressure,$windSpeed,'$windName',$windDirect,'$rainMode','$c','$b','$a')"
set dbStatus [dbCmd $sqlcmd]
puts "Event Ends."
exit
