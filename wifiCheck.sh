#!/bin/bash
#
# Check there is a network connection to the local router
# If the connection appears down then restart the network
#
# 11/5/15	Added check for motion port 8080
#               restart motion if not found
#
# Local Network Router
router_ip=10.0.0.1
log_file=/home/pi/mystery.log

# Make sure we can write to the log.
touch $log_file
if [ $? != 0 ]; then
    echo "Cannot use $log_file."
    exit 1
fi  

# Redirect output.
exec 1> /dev/null
exec 2>> $log_file

# A function for logging.
print2log () {
    echo $(date +"%D %R ")$@ >>$log_file
}
#
# Ping router.
ping -c 1 $router_ip & wait $!
if [ $? != 0 ]; then
  print2log "Ping $router_ip failed! Assumed network is down and attempting to reset..."
  sudo ifdown --force wlan0
  sudo ifup wlan0
else print2log "Ping OK."
fi
# Check sshd.
print2log "sshd PIDs: "$(ps -o pid= -C sshd)
#
# Check motion is listening on 8080
#
motion_listening=`sudo netstat -anp | grep 8081`
if [ $? != 0 ]; then
  print2log "motion is not listening on port 8080! Attempting to restart motion..."
  sudo /etc/init.d/motion restart
fi

