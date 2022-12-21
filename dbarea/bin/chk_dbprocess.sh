#!/bin/sh

##########################################################################
#
#  NOTE
# 
# Check process usage for each instance on the server
#  Annapurna 
##########################################################################

START_TIME=`date "+%F %T"`
C_ID="$1"
C_STATUS="success"
C_MSG=""

MAIL_LIST=cwopsdba@cisco.com
_pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"
_THRESH_HOLD=90

usage() {
  echo ""
  echo "USAGE:"
  echo "      `basename $0` <ORACLE_SID>"
  echo ""
}

#if [ $# -ne 1 ]; then
#  usage
#  exit
#fi

#_cnt=`ps -ef | grep ora_smon_$1| grep -wc -v "grep"`
#if [ $_cnt -ne 1 ]
#then
#  echo "Invalid ORACLE_SID"
#  echo "ERROR - The argument passed ($1) is not a valid ORACLE_SID on `hostname`." | /bin/mailx -s "ERROR - Terminate inactive session on `hostname`" ${MAIL_TO}
#  usage

#  C_STATUS="fail"
#  C_MSG="Invalid ORACLE_SID."
#  call_stap
#  exit 1
#else
  export ORACLE_SID=$1
#fi

### Checking All instances Resource utilization
for _inst_name in `ps -ef |grep _smon_ |grep -v grep |grep -vi ASM |awk '{print $NF}' |awk -F "_" '{print $NF}'`
do
   _DB_NAME=`echo "${_inst_name%?}"`
   export ORACLE_SID=$_inst_name
   export ORACLE_HOME=`cat /etc/oratab | grep -v ^# | grep -v ^$ | grep -v ^* | grep -v agent | grep -v ASM | grep -v oms | grep $_DB_NAME |cut -d':' -f2 | sort -u | head -1`
export PATH=$ORACLE_HOME/bin:$PATH
export ORACLE_SID=${_inst_name}
_SPOOL_FILE=/tmp/${ORACLE_SID}_$$_proc.log
_EMAIL=/tmp/${ORACLE_SID}_$$_proc_email.log
 echo $_inst_name
$ORACLE_HOME/bin/sqlplus -S /nolog << EOSQL
conn as sysdba
/
set lines 80 pages 0
set feedback off
col RESOURCE_NAME for a25
set trims on
set trim on
col SQL for a45
spool $_SPOOL_FILE
SELECT RESOURCE_NAME,ALLOCATION,CURRENT_UTILIZATION,Usage_in_percent FROM (
select RESOURCE_NAME,INITIAL_ALLOCATION ALLOCATION ,CURRENT_UTILIZATION,CURRENT_UTILIZATION/INITIAL_ALLOCATION*100 Usage_in_percent from v\$resource_limit where RESOURCE_NAME='processes'
) WHERE Usage_in_percent > ${_THRESH_HOLD};
spool off
exit
EOSQL
if [ -s  ${_SPOOL_FILE} ]; then
   echo "Hi, On-call " > ${_EMAIL}
   echo "  " >>  ${_EMAIL}
   echo "  " >>  ${_EMAIL}
   echo " The below resources are reaching max utiliztion, Please check . " >>  ${_EMAIL}
   echo "  " >>  ${_EMAIL}
   echo "  " >>  ${_EMAIL}
   echo "Resource Name          Allocation      Curent Utilization      Usage% " >> ${_EMAIL}
   echo "=========================================================================" >>  ${_EMAIL}
   cat  ${_SPOOL_FILE} >> ${_EMAIL}
   echo "  " >> ${_EMAIL} 
   echo "  " >>  ${_EMAIL}
   echo "Thanks, " >> ${_EMAIL}
   echo "DBA Team "  >>  ${_EMAIL}
   mailx -s "DB Alert Critical - Process Utilization grether than $_THRESH_HOLD% for $ORACLE_SID " $MAIL_LIST < ${_EMAIL}
   mesg_str="DB-Alert Critical  DB process usage greater than  $_THRESH_HOLD% ${ORACLE_SID} "
   mailx -s "$mesg_str " ${_pager_duty}<  ${_EMAIL}
fi
rm -rf ${_SPOOL_FILE}
rm -rf ${_EMAIL}
done
