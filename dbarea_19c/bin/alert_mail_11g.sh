#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
# 
#  MODIFIED     (MM/DD/YY)
#    Gates         11/10/2020 - chwanged for Redhat 7 OS version, this script is not called by jobmanager, but by jenkins job
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/12/2017 - Add the STAP API calling.
#
##########################################################################
#
#  alert_mail.sh
#
#     This script is used to check alert log file
#     input:
#      1)   Oracle Service Name
#     output:
#      1)   send email to dba if there is ORA- error msg
#
#
##########################################################################

############################## for STAP API call using.
C_STATUS="success"
C_MSG=""


if [ $# != 1 ]; then
  echo
  echo "Usage: alert_mail.sh ORACLE_SID "
  echo
  exit
fi

. /home/oracle/.bash_profile

HOST=`/bin/uname -n`
MAIL=/bin/mailx
DISTLIST=cwopsdba@cisco.com
#DISTLIST=adantuve@cisco.com
# export HOST MAIL DISTLIST

ORACLE_SID="$1"
NODE_NO=`hostname|awk -F"." '{print $1}' |sed -e "s/^.*\(.\)$/\1/"`
ORA_LOG_NAME=alert_${ORACLE_SID}.log
# export ORA_LOG_NAME
HIST_NAME=alert_${ORACLE_SID}.hist
# export HIST_NAME

rm -f /tmp/oraerror_${ORACLE_SID}.cfg
rm -f /tmp/alert_${ORACLE_SID}.err

cd ${ORACLE_BASE}/diag/rdbms/*/$ORACLE_SID/trace
if [ -f ${ORA_LOG_NAME} ]
then
    mv ${ORA_LOG_NAME} alert_work.log
    cat alert_work.log >> ${HIST_NAME}
    cat alert_work.log |grep -B1 ORA- | grep -vi "$(egrep "ORA-28|ORA-609|ORA-1112|ORA-01403|ORA-06512|ORA-12012|ORA-1142|ORA-3217|ORA-3217|ORA-3136|ORA-3136|ORA-12805|ORA-01555" -B1  alert_work.log )" |grep -B1 ORA- > /tmp/alert_${ORACLE_SID}.err

   #grep -B1 ORA- alert_work.log | grep -v "ORA-279" | grep -v "ORA-308" | grep -v "ORA-1112" | grep -v "ORA-1642" | grep -v "ORA-01403" | grep -v "ORA-06512" | grep -v "ORA-12012" | grep -v "ORA-1142" | grep -v "ORA-3217"| grep -v "ORA-3136" |grep -v "ORA-609"|grep -v "ORA-28" |grep -vi "nt OS err code: 0" > /tmp/alert_${ORACLE_SID}.err
fi

if [ -s /tmp/alert_${ORACLE_SID}.err ]
then
    grep ORA- /tmp/alert_${ORACLE_SID}.err | sed '/^$/d' > /tmp/oraerror_${ORACLE_SID}.cfg
    instance_name=$ORACLE_SID
    if [ `cat /tmp/ORAErrorXmlReq_${ORACLE_SID}.log |wc -l` -ne `cat /tmp/ORAErrorXmlReq_${ORACLE_SID}.log |grep SUCCESS |wc -l` ] ; then
         C_MSG="found ora error for DB instance."
       mailx  -s " ALERT LOG ORA-ERROR  :  ${ORACLE_SID}@${HOST} Database Alert errors " $DISTLIST < /tmp/alert_${ORACLE_SID}.err
      _pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"
    mesg_str="DB-Alert Critical  ALERT LOG ORA-ERROR  : ${ORACLE_SID}@${HOST} Database Alert error "
    mailx -s "$mesg_str " ${_pager_duty}<  /tmp/alert_${ORACLE_SID}.err 
    fi
fi

rm -f /tmp/alert.err
rm -f /tmp/alert_work.log
rm -f /tmp/alert_${ORACLE_SID}.err 


### ASM   Alert  log
cd ${ORACLE_BASE}/diag/*/*/*/trace
# NODE_NO=`hostname|awk -F"." '{print $1}' |sed -e "s/^.*\(.\)$/\1/"`
ASM_SID="`ps -ef | grep asm_smon | grep -v grep | grep ASM | awk '{print $8}' | cut -d'_' -f3`"
ORA_LOG_NAME=alert_${ASM_SID}.log
HIST_NAME=alert_${ASM_SID}.hist
# export HIST_NAME

if [ -f ${ORA_LOG_NAME} ]
then
    mv ${ORA_LOG_NAME} alert_work.log
    cat alert_work.log >> ${HIST_NAME}
    grep -B1 ORA- alert_work.log | grep -v "ORA-279" | grep -v "ORA-308" | grep -v "ORA-1112" | grep -v "ORA-1642" | grep -v "ORA-01403" | grep -v "ORA-06512" | grep -v "ORA-12012" | grep -v "ORA-1142" | grep -v "ORA-3217" > /tmp/alert_${ASM_SID}.err  
fi

if [ -s /tmp/alert_${ASM_SID}.err ]
then
    grep ORA- /tmp/alert_${ASM_SID}.err |sed '/^$/d' > /tmp/oraerror_${ASM_SID}.cfg 
    instance_name=$ASM_SID
    if [ `cat /tmp/ORAErrorXmlReq_${ASM_SID}.log |wc -l` -ne `cat /tmp/ORAErrorXmlReq_${ASM_SID}.log |grep SUCCESS |wc -l` ] ; then
         C_MSG=${C_MSG}" found ora error for ASM instance."
       mailx  -s " ALERT LOG ORA-ERROR  :  ${ASM_SID}@${HOST} Database Alert errors " $DISTLIST < /tmp/alert_${ASM_SID}.err
    fi
fi

rm -f /tmp/alert_${ASM_SID}.err
rm -f /tmp/alert_work_${ASM_SID}.log
rm -f /tmp/oraerror_${ASM_SID}.cfg

