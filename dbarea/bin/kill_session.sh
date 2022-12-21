#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
# 
#  MODIFIED     (MM/DD/YY)
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         12/14/2017 - Change the logic to must have 1 SID as input.
#    Edwin         10/12/2017 - Add the STAP API calling.
#                               Change the logic to get SID while no input.
# 
##########################################################################

############################## for STAP API call using.
START_TIME=`date "+%F %T"`
C_ID="$1"
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

export MAIL_TO=cwopsdba@cisco.com

usage() {
  echo ""
  echo "USAGE:"
  echo "      `basename $0` <ORACLE_SID>"
  echo ""
}

if [ $# -ne 1 ]; then
  usage
  exit
fi

_cnt=`ps -ef | grep ora_smon_$1| grep -wc -v "grep"`
if [ $_cnt -ne 1 ]
then
  echo "Invalid ORACLE_SID"
  echo "ERROR - The argument passed ($1) is not a valid ORACLE_SID on `hostname`." | /bin/mailx -s "ERROR - Terminate inactive session on `hostname`" ${MAIL_TO}
  usage

  C_STATUS="fail"
  C_MSG="Invalid ORACLE_SID."
  call_stap
  exit 1
else
  export ORACLE_SID=$1
fi


export BIN_DIR=/u00/app/admin/dbarea/bin
export SQL_DIR=/u00/app/admin/dbarea/sql
export LOG_DIR=/u00/app/admin/dbarea/log

export ORACLE_HOME=`cat /etc/oratab | grep -v ^# | grep -v ^$ | grep -v ^* | grep -v agent | grep -v ASM | grep -v oms | cut -d':' -f2 | sort -u | head -1`

export PATH=$ORACLE_HOME/bin:$PATH

$ORACLE_HOME/bin/sqlplus -S /nolog << EOSQL
conn as sysdba
/
set lines 80 pages 0
set feedback off
col username for a25
col "Minutes Inactive" for 999,999.99
set trims on
set trim on
col SQL for a45
spool $SQL_DIR/kill_session.log
SELECT '!kill -9 '||p.spid||'  |alter system kill session '''||s.sid||', '||s.serial#||'''; '
FROM v\$session s, v\$process p
WHERE s.paddr = p.addr AND (s.last_call_et / 60) > 1440 AND s.status = 'INACTIVE' AND s.username not in (
'AADINARAYAN', 'AGUJARE', 'AMIKUMAR', 'ANONYMOUS', 'ANVENKA', 'ATAMIZHMANI', 'BSUSAIMANICKAM', 'CHUA', 'CTXSYS', 'DBHEALTH', 'DBSNMP', 'DIP', 'DMSYS', 
'EXFSYS', 'GUNSINGH', 'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OLAPSYS', 'ORACLE_OCM', 'ORDPLUGINS', 'ORDSYS', 'OUTLN', 'PKUMAR', 'PNAGABHUSHANAIAH', 'SBHADUPO', 
'SCOTT', 'SI_INFORMTN_SCHEMA', 'SPLEX_DENY', 'SYS', 'SYSMAN', 'SYSTEM', 'TOUYANG', 'TSMSYS', 'WBXBACKUP', 'WBXDBA', 'WMSYS', 'XDB')
;
spool off
exit
EOSQL

if [ -s $SQL_DIR/kill_session.log ]; then

  #echo "file exist with >0 bytes"
  echo "spool $LOG_DIR/kill_inactive_sessions.log" > $SQL_DIR/kill_session.sql
  echo "" >> $SQL_DIR/kill_session.sql
  _iCnt=0
  while read _line
  do
    _iCnt=`expr $_iCnt + 1`
    _kill=`echo $_line|cut -d"|" -f1`
    _sql=`echo $_line|cut -d"|" -f2`
    echo $_sql  >> $SQL_DIR/kill_session.sql
    echo $_kill >> $SQL_DIR/kill_session.sql
    echo ""     >> $SQL_DIR/kill_session.sql
  done < $SQL_DIR/kill_session.log
  echo "spool off" >> $SQL_DIR/kill_session.sql
  echo "Total Sessions to terminate: $_iCnt" > $LOG_DIR/kill_session_email.txt

  #cat $SQL_DIR/kill_session.sql

  $ORACLE_HOME/bin/sqlplus -S /nolog << EOSQL1
    conn as sysdba
    /
    set feedback on
    set echo on
    set termout on
    set head off
    @$SQL_DIR/kill_session.sql
    set feedback off
    spool $LOG_DIR/session_cnt.txt
    select count(1)
    FROM v\$session s
    WHERE (s.last_call_et / 60) > 1440 AND s.status = 'INACTIVE' AND s.username not in ( 
     'AADINARAYAN', 'AGUJARE', 'AMIKUMAR', 'ANONYMOUS', 'ANVENKA', 'ATAMIZHMANI', 'BSUSAIMANICKAM', 'CHUA', 'CTXSYS', 'DBHEALTH', 'DBSNMP', 'DIP', 'DMSYS', 
     'EXFSYS', 'GUNSINGH', 'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OLAPSYS', 'ORACLE_OCM', 'ORDPLUGINS', 'ORDSYS', 'OUTLN', 'PKUMAR', 'PNAGABHUSHANAIAH', 'SBHADUPO', 
     'SCOTT', 'SI_INFORMTN_SCHEMA', 'SPLEX_DENY', 'SYS', 'SYSMAN', 'SYSTEM', 'TOUYANG', 'TSMSYS', 'WBXBACKUP', 'WBXDBA', 'WMSYS', 'XDB')   ;
    spool off
    exit
EOSQL1

  typeset -i _session_cnt
  _session_cnt=`cat $LOG_DIR/session_cnt.txt | grep -v ^$`
  if [ ${_session_cnt} -ne 0 ]; then
    echo "Total Sessions still to be terminated: ${_session_cnt}" >> $LOG_DIR/kill_session_email.txt
  fi

  C_STATUS="warning"
  C_MSG="found and kill sessions."

fi

##########################################################################
# call STAP API.
##########################################################################
call_stap

