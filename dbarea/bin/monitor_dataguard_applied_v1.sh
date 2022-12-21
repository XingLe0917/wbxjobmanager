#!/bin/bash

#set -x

usage() {
  echo ""
  echo "USAGE:"
  echo "      `basename $0` [ORACLE_SID]"
  echo ""
}

if [ $# -eq 0 ]; then
  # see if only one oracle database is running in this box.
  _cnt=`ps -ef | grep smon | grep -v "grep" | grep -v "+ASM"|wc -l`
  if [ $_cnt -eq 1 ]
  then
    _sid=`ps -ef | grep smon | grep -v "grep" | grep -v "+ASM" | cut -c58-`
    #echo "_sid = $_sid"
    export ORACLE_SID=$_sid
  else
    echo "More than 1 sid found"
    echo "ERROR(1) - No valid ORACLE_SID has been passed. More than one ORACLE_SID running in `hostname`." | /bin/mailx -s "ERROR -check dataguard status  on `hostname`" cwopsdba@cisco.com
    usage
    exit 1
  fi
elif [ $# -eq 1 ]; then
  # check if the passed sid is a vaild one
  _cnt=`ps -ef | grep ora_smon_$1| grep -v "grep" | wc -l`
  #echo "ps count = $_cnt"
  if [ $_cnt -ne 1 ]
  then
    echo "Invalid ORACLE_SID"
    echo "ERROR(2) - The argument passed ($1) is not a valid ORACLE_SID on `hostname`." | /bin/mailx -s "ERROR -check dataguard status  on `hostname`" cwopsdba@cisco.com
    usage
    exit 2
  else
    export ORACLE_SID=$1
  fi
else
  # more than 0 or 1 parameter passed
  echo "More than 0 or 1 parameter passed."
  echo "ERROR(3) - No valid argument passed." | /bin/mailx -s "ERROR -check dataguard status  on `hostname`" cwopsdba@cisco.com
  usage
  exit 3
fi

export BIN_DIR=/u00/app/admin/dbarea/bin
export SQL_DIR=/u00/app/admin/dbarea/sql
export LOG_DIR=/u00/app/admin/dbarea/log


export ORACLE_HOME=`cat /etc/oratab | grep -v ^# | grep -v ^$ | grep -v ^* | grep -v agent | grep -v ASM | grep -v oms | cut -d':' -f2 | sort -u | head -1`

export PATH=$ORACLE_HOME/bin:$PATH

$ORACLE_HOME/bin/sqlplus -S /nolog << EOSQL
conn as sysdba
/
set lines 300 
set feedback off
alter session set NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';
spool /u00/app/admin/dbarea/log/check_status.log
@/u00/app/admin/dbarea/sql/check_dg_status.sql
spool off
exit
EOSQL

_cat=`cat /u00/app/admin/dbarea/log/check_status.log|wc -l` 

if [ $_cat -gt 1 ]; then  
  /bin/mailx -s " opdb standby applied archive log delay more 30 min on `hostname`" cwopsdba@cisco.com < $LOG_DIR/check_status.log
fi

exit 0
