#!/bin/tclsh
#
package require mysqltcl

set baseDir "/home/phall/gdrive/motion" 
set m [mysqlconnect -user root -db security -password hyperion] 
mysqluse $m mysql

if { [catch {cd $baseDir}] } {
  puts "Failed to set base directory $baseDir"
  exit
}

puts -nonewline "Retriving current list of files..." 
if { [catch { set originalFileList [ exec ls {*}[glob *.avi] ] } ] } {
  puts "No files matched in drive directory!"
  set originalFileList ""
}
set count 0 
foreach res $originalFileList {
  incr count
}
puts "Done. Number of files currently in the gdrive directory is $count."

puts -nonewline "Date ? " 
flush stdout 
set targetDate [gets stdin]
set newFileList "" 
set count 0
set mysqlQuery "select filename from security.motionSecurity where time_stamp > '$targetDate'"

puts -nonewline "Comparing DB entries to files in gdrive directory..." 
foreach res [mysqlsel $m $mysqlQuery -flatlist] {
    set fn [file tail $res]
    if { [lsearch originalFileList $fn] < 0 } {
      lappend newFileList $res
      incr count
    }
}
mysqlclose $m 
puts -nonewline "Done." 
puts " Difference in files is $count." 
puts -nonewline "Linking files in gdrive to pi directories..."
set countLinked 0 
set countError 0 
foreach newFile $newFileList {
    incr countLinked
    set fn [file tail $newFile]
    if { [catch { exec ln -s $newFile $fn } msg] } {
      incr countError
    }
}
puts "Done. Linked $countLinked files. Number of files failed to link because of an error $countError"

