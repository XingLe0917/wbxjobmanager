#!/bin/sh
source /staging/gates/bash_common.sh
##########################################################################
#
#  NOTE
# 
# Check process usage for each instance on the server
#  Annapurna 
##########################################################################

MAIL_LIST=cwopsdba@cisco.com
_pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"
_THRESH_HOLD=90

usage() {
  echo ""
  echo "USAGE:"
  echo "      `basename $0` <ORACLE_SID>"
  echo ""
}

. /home/oracle/.bash_profile

### Checking All instances Resource utilization
localhostname=`hostname -s`
SID_LIST=`getmonitoreddblist "${localhostname}"`
for _inst_name in ${SID_LIST[@]}
do
   _DB_NAME=`echo "${_inst_name%?}"`
   export ORACLE_SID=$_inst_name
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
