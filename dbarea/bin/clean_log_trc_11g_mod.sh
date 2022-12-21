#!/bin/bash
# Functionality: To trim alert-log and listener-log
#

##########################################################################
# clean_log_trc_11g.sh
#
# Purpose:      This is shell program will be used to roll the
#                alert/listener/crs logs
#
# input:        1) SID list, seperated by comma
#
#
#
# By:          cwopsdba
# date:        16-Mar-2011
#
##########################################################################

export DEBUG=0
myEcho() {
  if [ $DEBUG -ge 1 ]; then
    echo $*
  fi
}

usage() {
  echo ""
  echo "Scripts needs three parameter."
  echo
  echo "Usage: `basename $0` <sid_list> <DAYS> <MAILTO>"
  echo ""
  echo "         <sid_list>: list of NON ASM sid's seperated by COMMA. Please dont pass ASM sid, it is taken care in the script."
  echo "         <DAYS>    : the days to keep the files "
  echo "         <MAILTO>  : the DL without cisco.com (e.g. cwopsdba)"
  echo ""
  echo "e.g. "
  echo "`basename $0` btsystoo1 7 cwopsdba"
  exit
}

if [ $# -ne 3 ]; then
  usage
  exit
fi

_sid_list="`echo $1 | tr ',' ' '`"
export DAYS="+$2"
export MAIL_TO=$3@cisco.com
#export MAIL_TO=cwopsdba@cisco.com

echo "start time `date`" > /tmp/clean_log_trc_11g.lst

HOSTNAME="`hostname | cut -d'.' -f1`"
export HOSTNAME

# get the GRID_HOME and ASM SID for this server.
GRID_HOME="`cat /etc/oratab | grep -v "^#" | grep -v ^$ | grep -i asm | cut -d':' -f2 | sort -u`"
ASM_SID="`ps -ef | grep smon | grep -v grep | grep ASM | awk '{print $r8}' | cut -d'_' -f3`"
RDBMS_HOME="`cat /etc/oratab | grep -v "^#" | grep -v ^$ | grep -iv asm | grep -v agent | cut -d':' -f2 | sort -u`"

if [ -z "${GRID_HOME}" -o -z "${RDBMS_HOME}" ]; then
  # no ASM home found. could not proceed.
  _sub="Error occured in roll over log script @$HOSTNAME"
  _msg="\n\nNO ASM home or RDBMS home found in /etc/oratab.\n\nPlease check.\n"
  echo -e ${_msg}
  echo -e ${_msg} | mailx -s "${_sub}" "${MAIL_TO}"
  exit
fi

if [ -z "${ASM_SID}" ]; then
  # no ASM SID found. could not proceed.
  _sub="Error occured in roll over log script @$HOSTNAME"
  _msg="\n\nNO ASM found to be running on $HOSTNAME.\n\nPlease check.\n"
  echo -e ${_msg}
  echo -e ${_msg} | mailx -s "${_sub}" "${MAIL_TO}"
  exit
fi

myEcho "GRID_HOME=$GRID_HOME"
myEcho "ASM_SID=$ASM_SID"
myEcho "RDBMS_HOME=$RDBMS_HOME"
myEcho "HOSTNAME=$HOSTNAME"

_sid_list="${_sid_list} ${ASM_SID}"
_cnt=0
for _sid in ${_sid_list}
do
  # check if the passed SID is a valid SID
  if [ "${_sid}" != "${ASM_SID}" -a `ps -ef  | grep smon | grep -v grep | grep -v ASM | grep -c ${_sid}` -ne 1 ]; then
    _msg="The Passed SID (${_sid}) is not a valid SID on $HOSTNAME."
    _sub="Error occured in roll over log script @$HOSTNAME"
    echo -e ${_msg}
    echo -e ${_msg} | mailx -s "${_sub}" "${MAIL_TO}"
    exit
  else

    # get the RDBMS_HOME for this sid
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
        _sub="Error occured in roll over log script for database connection $ORACLE_SID@$HOSTNAME"
        echo ${_sub}
        mailx -s "${_sub}" ${MAIL_TO} < /tmp/sql.err
        exit
      else
        DIAG_DST="`cat /tmp/sql.err`"
      fi
    else
      # else some other error has occured.
      _msg="\n\nFile size of database connectivity output is zero.\n\nIdeally this should not happen.\n\nPlease check.\n"
      _sub="Error occured in roll over log script for database connection $ORACLE_SID@$HOSTNAME"
      echo ${_msg}
      echo -e "${_msg}" | mailx -s "${_sub}" ${MAIL_TO}
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
  fi
done
        
#_i=1
#while [ ${_i} -le ${_cnt} ]
#do
#  myEcho "DIAG_DST_LST[${_i}]=${DIAG_DST_LST[${_i}]}"
#  _i=`expr ${_i} + 1`
#done
#myEcho ""

# iterate thru all the diag dest and roll over the alert logs
_i=1
while [ ${_i} -le ${_cnt} ]
do

  ###################################################################################
  #########   DELETE OLD LOG/TRACE FILES
  ###################################################################################
  DIAG_DST=${DIAG_DST_LST[${_i}]}
  DEST_DIR=${DIAG_DST}/diag

myEcho "DEST_DIR=${DEST_DIR}"

  /usr/bin/find ${DEST_DIR}/*/*/*/alert/ -name "*.trc" -mtime $DAYS -exec rm -rf {} \;
  /usr/bin/find ${DEST_DIR}/*/*/*/alert/ -name "*.aud" -mtime $DAYS -exec rm -rf {} \;

  /usr/bin/find ${DEST_DIR}/*/*/*/cdump/ -name "cdmp*" -mtime $DAYS -exec rm -rf {} \;
  /usr/bin/find ${DEST_DIR}/*/*/*/trace/ -name "*.aud" -mtime $DAYS -exec rm -rf {} \;
  /usr/bin/find ${DEST_DIR}/*/*/*/trace/ -name "*.trc" -mtime $DAYS -exec rm -rf {} \;
  /usr/bin/find ${DEST_DIR}/*/*/*/trace/ -name "*.trm" -mtime $DAYS -exec rm -rf {} \;
  
  /usr/bin/find ${DEST_DIR}/*/*/*/trace/ -name "alert*.old.*"  -mtime  +30 -exec rm {} \;

  /usr/bin/find ${DIAG_DST}/admin/*/adump -name "*.aud" -mtime ${DAYS} -exec rm -rf {} \;

  # remove listener old logs
  if [ -d "${DEST_DIR}/tnslsnr/${HOSTNAME}/listener/alert/" ]; then
    /usr/bin/find ${DEST_DIR}/tnslsnr/${HOSTNAME}/listener/alert/ -name "log_*.xml" -mtime $DAYS -exec rm -rf {} \;
  fi

  _i=`expr ${_i} + 1`
done


## Remove Audit files for ASM 
/usr/bin/find ${GRID_HOME}/rdbms/audit/ -name "*.aud" -mtime $DAYS -exec rm -rf {} \;


# remove scan listener old logs
/usr/bin/find ${GRID_HOME}/log/diag/tnslsnr/${HOSTNAME}/listener_scan*/alert/ -name "log_*.xml" -mtime $DAYS -exec rm -rf {} \;


# remove crsd,cssd,evmd,ohasd old logs

/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/crsd/ -name "crsd.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/cssd/ -name "ocssd.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/evmd/ -name "evmd.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/ohasd/ -name "ohasd.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/ctssd/ -name "octssd.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/gipcd/ -name "gipcd.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;

/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/agent/crsd/application_oracle/ -name "application_oracle.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/agent/crsd/oraagent_oracle/ -name "oraagent_oracle.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/agent/crsd/scriptagent_oracle/ -name "scriptagent_oracle.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${GRID_HOME}/log/$HOSTNAME/agent/ohasd/oraagent_oracle/ -name "oraagent_oracle.l[0-9]*" -mtime $DAYS -exec rm -rf {} \;
