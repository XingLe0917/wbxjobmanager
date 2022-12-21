#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
# 
#  MODIFIED     (MM/DD/YY)
#    Edwin         03/05/2018 - Add to use HOSTNAME_S to avoid conflict.
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         12/14/2017 - Add the STAP API calling.
# 
#  Change:
#    1. Remove the input parameter for SID.
#    2. Change to get all the SID current running.
# 
# 
# 
##########################################################################
# Functionality: To trim alert-log and listener-log
#
##########################################################################
# roll_logs_11g.sh
#
# Purpose:      This is shell program will be used to roll the
#                alert/listener/crs logs
#
# input:        1) SID list, seperated by comma
#
#
#
# By:          cwopsdba
# date:        14-Mar-2011
#
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


export DEBUG=0
export MAIL_TO=cwopsdba@cisco.com

myEcho() {
  if [ $DEBUG -ge 1 ]; then
    echo $*
  fi
}

############################################################
# No need for the SID as input parameter.
# We can see some servers which running more SID has more line to call this script in crontab,
# but each time, it will run for ASM.
# so, we check out the all the SID running at the server, include the ASM.
############################################################

# usage() {
#   echo ""
#   echo "Scripts needs atleast one parameter."
#   echo ""
#   echo "Usage: `basename $0` <sid_list>"
#   echo "    "
#   echo "    <sid_list>: list of NON ASM sid's seperated by COMMA. Please dont pass ASM sid, it is taken care in the script."
#   echo "    "
#   echo "e.g. "
#   echo "`basename $0` btsystoo1"
#   exit
# }
# 
# if [ $# -eq 0 ]; then
#   usage
#   exit
# fi

echo "start time `date`" > /tmp/trim_logs.lst

HOSTNAME_S="`hostname -s`"
export HOSTNAME_S

# get the GRID_HOME and ASM SID for this server.
GRID_HOME="`cat /etc/oratab | grep -v "^#" | grep -v ^$ | grep -i asm | cut -d':' -f2 | sort -u`"
ASM_SID="`ps -ef | grep asm_smon | grep -v grep | grep ASM | awk '{print $8}' | cut -d'_' -f3`"
RDBMS_HOME="`cat /etc/oratab | grep -v "^#" | grep -v ^$ | grep -iv asm | grep -v agent | cut -d':' -f2 | sort -u`"

if [ -z "${GRID_HOME}" -o -z "${RDBMS_HOME}" ]; then
  # no ASM home found. could not proceed.
  _sub="Error occured in roll over log script @$HOSTNAME_S"
  _msg="\n\nNO ASM home or RDBMS home found in /etc/oratab.\n\nPlease check.\n"
  echo -e ${_msg}
  echo -e ${_msg} | mailx -s "${_sub}" "${MAIL_TO}"

  C_STATUS="fail"
  C_MSG="NO ASM home or RDBMS home found"
  call_stap

  exit
fi

if [ -z "${ASM_SID}" ]; then
  # no ASM SID found. could not proceed.
  _sub="Error occured in roll over log script @$HOSTNAME_S"
  _msg="\n\nNO ASM found to be running on $HOSTNAME_S.\n\nPlease check.\n"
  echo -e ${_msg}
  echo -e ${_msg} | mailx -s "${_sub}" "${MAIL_TO}"

  C_STATUS="fail"
  C_MSG="NO ASM found to be running"
  call_stap

  exit
fi

myEcho "GRID_HOME=$GRID_HOME"
myEcho "ASM_SID=$ASM_SID"
myEcho "RDBMS_HOME=$RDBMS_HOME"
myEcho "HOSTNAME_S=$HOSTNAME_S"

# _sid_list="`echo $1 | tr ',' ' '`"
_sid_list="`ps -ef | grep ora_smon | grep -v grep | awk '{print $8}' | cut -d'_' -f3`"
_sid_list="${_sid_list} ${ASM_SID}"
_cnt=0
for _sid in ${_sid_list}
do
  # # check if the passed SID is a valid SID
  # if [ "${_sid}" != "${ASM_SID}" -a `ps -ef  | grep smon | grep -v grep | grep -v ASM | grep -c ${_sid}` -ne 1 ]; then
  #   _msg="The Passed SID (${_sid}) is not a valid SID on $HOSTNAME_S."
  #   _sub="Error occured in roll over log script @$HOSTNAME_S"
  #   echo -e ${_msg}
  #   echo -e ${_msg} | mailx -s "${_sub}" "${MAIL_TO}"
  #   exit
  # else

    # set the RDBMS_HOME for this sid
    RDBMS_SID=${_sid}

    if [ "${_sid}" = "${ASM_SID}" ]; then
      export ORACLE_SID=${ASM_SID}
      export ORACLE_HOME=${GRID_HOME}
    else
      export ORACLE_SID=${RDBMS_SID}
      export ORACLE_HOME=${RDBMS_HOME}
    fi

    # get the DIAGONISTIC_DEST parameter values
    $ORACLE_HOME/bin/sqlplus -s /nolog << EOSQL 1>/tmp/sql.err 2>&1
conn as sysdba
/
set pages 0 feedback off echo off termout on serveroutput on
select ltrim(rtrim(value)) from v\$parameter where name = 'diagnostic_dest';
EOSQL

    # check for any errors in the sql connection
    if [ -s /tmp/sql.err ]; then
      if [ `cat /tmp/sql.err | egrep -c "ORA-|SP2-"` -gt 0 ]; then
        # error has occured. need to send email and terminate the program
        _sub="Error occured in roll over log script for database connection $ORACLE_SID@$HOSTNAME_S"
        echo ${_sub}
        mailx -s "${_sub}" ${MAIL_TO} < /tmp/sql.err

        C_STATUS="fail"
        C_MSG="Error occured in roll over log script for database connection"
        call_stap

        exit
      else
        DIAG_DST="`cat /tmp/sql.err`"
      fi
    else
      # else some other error has occured.
      _msg="\n\nFile size of database connectivity output is zero.\n\nIdeally this should not happen.\n\nPlease check.\n"
      _sub="Error occured in roll over log script for database connection $ORACLE_SID@$HOSTNAME_S"
      echo ${_msg}
      echo -e "${_msg}" | mailx -s "${_sub}" ${MAIL_TO}

      C_STATUS="fail"
      C_MSG="Error occured in roll over log script for database connection"
      call_stap

      exit
    fi

    # remove the last "/"
    _l1=${#DIAG_DST}
    if [ "`echo ${DIAG_DST} | cut -c${_l1}`" = "/" ]; then
      _l2=`expr ${_l1} - 1`
      _tmp="`echo ${DIAG_DST} | cut -c1-${_l2}`"
      DIAG_DST=${_tmp}
    fi

    # check if this DIAG_DST is already present in the DIAG_DST_LST
    if [ ${_cnt} -gt 0 ]; then
      _i=1
      bFlag="n"
      while [ ${_i} -le ${_cnt} -a "${bFlag}" = "n" ]
      do
        if [ "${DIAG_DST_LST[${_i}]}" = "${DIAG_DST}" ]; then
          bFlag="y"
        fi
        _i=`expr ${_i} + 1`
      done
      if [ "${bFlag}" = "n" ]; then
        _cnt=`expr ${_cnt} + 1`
        DIAG_DST_LST[${_cnt}]=${DIAG_DST}
      fi
    else
      _cnt=`expr ${_cnt} + 1`
      DIAG_DST_LST[${_cnt}]=${DIAG_DST}
    fi
done


# iterate thru all the diag dest and roll over the alert logs
_i=1
while [ ${_i} -le ${_cnt} ]
do

  ###################################################################################
  #########   ROLL OVER ALERT LOGS (BOTH ASM & RDBMS)
  ###################################################################################

  DIAG_DST=${DIAG_DST_LST[${_i}]}
  for ALERTLOG in `ls -al ${DIAG_DST}/diag/*/*/*/trace/alert*.log | awk '{print $9}'`
  do
    # tmp oracle alert log
    cat /dev/null > /tmp/oracle_alert.log

    # get only the last 1000 lines
    tail -1000 $ALERTLOG > /tmp/oracle_alert.log

    # make a copy of the alert log
    cp $ALERTLOG $ALERTLOG.old.`date +%Y%m%d%H%M`
    cp /tmp/oracle_alert.log $ALERTLOG
    rm /tmp/oracle_alert.log
  done

  ###################################################################################
  #########   ROLL OVER THE LISTENER LOGS
  #########   LISTENER LOGS ARE AUTOMATICALLY ROLLED OVER BY ORACLE 11g
  #########   ONLY log.xml is autimatically rolled over. BUT trace/listener.log is not
  ###################################################################################
  # trim the listener log
  LISTENERLOG=$DIAG_DST/diag/tnslsnr/${HOSTNAME_S}/listener/trace/listener.log
  if [ -f $LISTENERLOG ]; then
    tail -1000 $LISTENERLOG > /tmp/listener.log
    # archive $LISTENERLOG if necessary, prior to being overwritten
    cp /tmp/listener.log $LISTENERLOG
    rm /tmp/listener.log
  fi

  _i=`expr ${_i} + 1`
done


###################################################################################
#########   ROLL OVER THE OCSSD LOGS
###################################################################################
CSSDLOG=${GRID_HOME}/log/$HOSTNAME_S/cssd/ocssd.log
if [[ -f $CSSDLOG ]]; then
  tail -1000 $CSSDLOG > /tmp/ocssd.log
  cp /tmp/ocssd.log $CSSDLOG
  rm /tmp/ocssd.log
fi

###################################################################################
#########   ROLL OVER THE EVMD  LOGS
###################################################################################
EVMDLOG=${GRID_HOME}/log/$HOSTNAME_S/evmd/evmdOUT.log
if [[ -f $EVMDLOG ]]; then
  tail -1000 $EVMDLOG > /tmp/evmdOUT.log
  cp /tmp/evmdOUT.log $EVMDLOG
  rm /tmp/evmdOUT.log
fi


###################################################################################
#########   ROLL OVER THE SCAN LISTENER LOGS
#########   LISTENER LOGS ARE AUTOMATICALLY ROLLED OVER BY ORACLE 11g
#########   ONLY log.xml is autimatically rolled over. BUT trace/listener.log is not
###################################################################################
# trim the scan_listener logs
_LISTENERLOG_=${GRID_HOME}/log/diag/tnslsnr/${HOSTNAME_S}/listener_scan*/trace/listener_scan*.log
for LISTENERLOG in `ls -al ${_LISTENERLOG_} | awk '{print $9}'`
do
  if [ -f $LISTENERLOG ]; then
    tail -1000 $LISTENERLOG > /tmp/listener.log
    # archive $LISTENERLOG if necessary, prior to being overwritten
    cp /tmp/listener.log $LISTENERLOG
    rm /tmp/listener.log
  fi
done

##########################################################################
# call STAP API.
##########################################################################
call_stap

