#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
#
#  MODIFIED     (MM/DD/YY)
#    Edwin         12/25/2019 - Change frequency and retention to 15.
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/13/2017 - Change the retention from 7 to 30 days.
#    Edwin         10/11/2017 - Add the STAP API calling.
#
##########################################################################
# History:
# script to verify the OSW agent and restart if not running
# script also move the archives to the staging for archiving
# version 1: Britto S (bsusaima@cisco.com)
##########################################################################


############################## for STAP API call using.
START_TIME=`date "+%F %T"`
C_ID=""
C_STATUS="success"
C_MSG=""


_EMAIL_ID=cwopsdba@cisco.com

_OSW_INSTALL_DIR=/var/oswbb

_OSW_LOCAL_BACKUP_DAYS=15
_OSW_LOCAL_BACKUP_HOURS=$(expr ${_OSW_LOCAL_BACKUP_DAYS} \* 24)

_ret=$(ps -e | grep -cw OSWatcher.sh)
if [ ${_ret} -eq 0 ]; then
  cd ${_OSW_INSTALL_DIR}
  ${_OSW_INSTALL_DIR}/startOSWbb.sh 15 ${_OSW_LOCAL_BACKUP_HOURS} gzip ${_OSW_INSTALL_DIR}/archive >> /tmp/OSWatcherstatus
  tail -100 /tmp/OSWatcherstatus > /tmp/OSWatcherstatus.m
  mailx -s "OSWatcher Not Running,Restarted" ${_EMAIL_ID} < /tmp/OSWatcherstatus.m

  C_STATUS="warning"
  C_MSG="start the OSW agent."
fi


