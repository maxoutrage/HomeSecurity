#!/bin/tclsh
#
# P.A.Hall	8th January 2016	removeFiles - Catch if the file does not exist but is in the DB and report
#
package require mysqltcl 
package require logger
package require Expect
#
# logger
#
proc log_to_file {txt} {
    set logfile "/home/phall/log/motionFiles.log"
    set msg "\[[clock format [clock seconds]]\] $txt"
    set f [open $logfile {WRONLY CREAT APPEND}]
    fconfigure $f -encoding utf-8
    set msg [string map { "-_logger::service" "" } $msg]
    puts $f $msg
    close $f
}
#
set cameras "2 1 4 3" 
set baseDir "/home/phall/gdrive/motion" 
set dirList "/home/phall/gdrive/motion/DriveWay /home/phall/gdrive/motion/FrontDoorIN /home/phall/gdrive/motion/FrontDoorOUT /home/phall/gdrive/motion/Garage" 
set now [clock seconds] 
set version "motionFiles V0.1" 
set pixelLimit 5000
set noiseLimit 15
#
# Retrieve a list of files from the DB based on pixels and noise limits
#
proc GetFilesFromDB { camera pixelLimit noiseLimit } {
   set log [logger::init ::motionFiles::GetFilesFromDB]
   set m [mysqlconnect -user root -db security -password hyperion]
   set mysqlQuery "select filename from motionSecurity where camera = $camera and changed_pixels > $pixelLimit and noise < $noiseLimit"
   set fileList [mysqlsel $m $mysqlQuery -flatlist]
   ${log}::info "Number of files for camera $camera [llength $fileList]."
   mysqlclose $m
   return $fileList
}
#
# Return a list of files from a directory - only avi files are supported
#
proc GetFiles { dir } {
  set log [logger::init ::motionFIles::GetFiles]
  ${log}::info "Retrieving files from $dir"
  if { [catch { cd $dir } ] } {
    ${log}::critical "Can't cd to $dir"
    set fileList ""
    return $fileList
  }
  set fileList [ glob -directory $dir *.avi ]
  return $fileList
}
#
# Delete files from a directory
# 
proc removeFiles { dir olderThan} {
  set log [logger::init ::motionFiles::removeFiles]
  set olderThanT [ clock format $olderThan -format {%Y/%m/%d %H:%M}]
  set count 0
  if { [catch {cd $dir } ] } {
    ${log}::critical "Failed to changed to $dir"
    return
  }
  ${log}::info "Removing files from $dir"
  set fileList [ GetFiles $dir ]
  foreach file $fileList {
    if { [file isfile $file] } {
      if { [file mtime $file] > $olderThan} {
        exec rm -f $file
        incr count
      }
    } else { ${log}::error "File $file exists in the DB but not in the directory" }
  }
  ${log}::info "Removed $count files"
  return
}
#
# Main Loop
#
set log [logger::init motionFiles] 
${log}::info "Event Begins" 
set targetTime [ clock add $now -7 days ] 
${log}::info "Cutoff time is [clock format $targetTime -format {%Y/%m/%d %H:%M}]" 
set now [clock seconds] 
set nowT [clock format $now -format {%Y/%m/%d %H:%M}]
#
# Remove all the current files older than specific date
# 
${log}::info "Removing from motion directories files older than [clock format $targetTime -format {%Y/%m/%d %H:%M}]"
foreach dir $dirList {
  removeFiles $dir $targetTime
}
#
# Move into the base directory for gdrive
#
${log}::info "Moving to $baseDir" 
if { [catch {cd $baseDir}] } {
  ${log}::critical "Failed to change to base directory $baseDir"
  exit
}
set count 0
foreach dir $dirList camera $cameras {
  cd $dir
  set files [ GetFilesFromDB $camera $pixelLimit $noiseLimit ]
  ${log}::info "Camera $camera - number of files is [llength $files]"
  foreach file $files {
    if { [file isfile $file] } {
      set ftime [file mtime $file]
      if { [expr {$ftime > $targetTime}] } {
        set fn [file tail $file]
        if { [catch { exec ln -s $file $fn } msg] } {
          incr countError
        }
        incr count
      }
    }
  }
  ${log}::info "For camera $camera - number of files matching time constraints is $count"
  set count 0
}
${log}::info "Local files ready for push to Google Drive"
${log}::info "Event Ends"
exit
