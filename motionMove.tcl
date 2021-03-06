#!/usr/bin/tclsh
#
# Sync local files with Google Drive
#
package require Expect
#
set baseDir     "/home/phall/gdrive/motion"
set timeout     7200
set version     "motionUpload V0.1"
set prompt      "er> "
set drivePrompt { *[:$] }
set logFile     "/home/phall/Hacks/motionMove.log"
#
#
#
log_file -noappend $logFile
match_max 100000
#
spawn bash
log_user 1
expect $prompt               { send "cd $baseDir\r" }
expect $prompt               { send "drive push -ignore-name-clashes=true\r"  }
sleep 1
expect {
  sleep 2
  $prompt                    { send "drive push -ignore-name-clashes=true\r"  }
  -re $drivePrompt           { send "y\r" }
  timeout                    { send "y\r" }
  eof                        { send_user "Eof";       exit 1 }
}
#
#
#
set timeout -1
expect $prompt
exit
