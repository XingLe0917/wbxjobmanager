#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
# 
#  MODIFIED     (MM/DD/YY)
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/11/2017 - Add the STAP API calling.
# 
##########################################################################
# History:
# script to move the osw output file to staging
# version 2: Britto S (bsusaima@cisco.com) - 27-Apr-2017
##########################################################################


############################## for STAP API call using.
START_TIME=`date "+%F %T"`
C_ID=""
C_STATUS="success"
C_MSG=""

call_stap() {
  END_TIME=`date "+%F %T"`
  
  C_DATA="{\"host\": \"${HOSTNAME}\", \"name\": \"$0\", \"start_time\": \"${START_TIME}\", \"end_time\": \"${END_TIME}\", \"status\": \"${C_STATUS}\", \"msg\": \"${C_MSG}\", \"id\": \"${C_ID}\"}"
  C_OUT=`/u00/app/admin/dbarea/bin/call_stap_api.py "${C_DATA}"`
  
  if [ ${C_OUT} = '{"result":"OKOKOK"}' ]
  then
    echo "==== call STAP API success."
  else
    echo "==== call STAP API fail."
  fi
}
############################## END.

_EMAIL_ID=cwopsdba@cisco.com
_OSW_INSTALL_DIR=/var/oswbb
_OSW_ARCHIVAL_BACKUP_DAYS=30
_OSW_ARCHIVAL_DIR=/staging/oswbba/$(hostname -s)/archive

# move to backup archive
cd ${_OSW_INSTALL_DIR}/archive
find . -depth -name "*.dat.gz" -type f | cpio -pmd ${_OSW_ARCHIVAL_DIR} 2> /dev/null

# remove file on staging
cd ${_OSW_ARCHIVAL_DIR}
find . -name "*" -type f -mtime +${_OSW_ARCHIVAL_BACKUP_DAYS} -exec rm -rf {} \;

##########################################################################
# call STAP API.
##########################################################################
call_stap


