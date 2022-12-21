#!/bin/sh

##########################################################################
#
#  NOTE
#    1. Add step to call STAP API to send out the script running status.
#    2. process.
#       a. get the running SID list.
#       b. for each SID, loop 4 times as below.
#          b1. check whether it has FRA size issue.
#          b2. run RMAN cleanup command if has size issue.
#          b3. exist the loop if no size issue.
#          b4. send alert mail if the auto cleanup can not fix the issue.
#       c. send status to STAP.
# 
# 
#  MODIFIED     (MM/DD/YY)
#    Edwin         04/28/2018 - Change shreshold from 14 to 10.
#    Edwin         04/26/2018 - Re-write the whole logic.
#    Edwin         03/23/2018 - Re-write the scirpt basis on the size 13026.
# 
##########################################################################
source /staging/gates/bash_common.sh
. /home/oracle/.bash_profile
## the threshold for when shall we run the clean.
FREE_PERCENT=10

MAILTO=cwopsdba@cisco.com
LOG_FILE=/tmp/clean_fra.log

## temp variables.
TMP_FILE_FRA_SIZE=/tmp/fra_size_4_clean.txt
TMP_FILE_RMAN_OUT=/tmp/rman_out_4_clean.txt

GET_DG()
{
cat /dev/null > ${TMP_FILE_FRA_SIZE}

sqlplus -s / as sysdba <<EOF 1>${TMP_FILE_FRA_SIZE} 2>&1 
set pagesize 0 feedback off heading off echo off 
select '===' tag, g.name, g.total_mb, g.free_mb, round(g.free_mb*100/g.total_mb) aa, c.db_name
from v\$asm_client c, v\$asm_diskgroup g
where c.status = 'CONNECTED' and c.group_number = g.group_number and g.name like '%FRA%' and g.total_mb != 0 and g.free_mb*100/g.total_mb < ${FREE_PERCENT}
;
EXIT;
EOF
}

NEED_CLEAN()
{
  export ORACLE_SID=$1
  
  ## check out the FRA info.
  GET_DG
  _fra_cnt=`grep "^===" ${TMP_FILE_FRA_SIZE} | wc -l`
  _ora_cnt=`grep "ORA-" ${TMP_FILE_FRA_SIZE} | wc -l`
  _err_cnt=`grep "ERROR" ${TMP_FILE_FRA_SIZE} | wc -l`

  if [[ ${_ora_cnt} -gt 0 || ${_err_cnt} -gt 0 ]]; then
    echo "=== Error while query the FRA size info in ${ORACLE_SID}: " >> ${LOG_FILE}
    cat ${TMP_FILE_FRA_SIZE} >> ${LOG_FILE}
    _return_val=2
  fi

  # the output start with "=== " means we got the FAR which has size issue. but we don't care the detail name.
  if [ ${_fra_cnt} -gt 0 ]; then
    echo "=== found FRA DG with size issue in ${ORACLE_SID}: " >> ${LOG_FILE}
    cat ${TMP_FILE_FRA_SIZE} >> ${LOG_FILE}
    _return_val=1
  else
    echo "=== NO size issue for FRA in ${ORACLE_SID}. " >> ${LOG_FILE}
    _return_val=0
  fi
	
  return $_return_val
}

AUTOCLEANUP_FORCE()
{                 
  export ORACLE_SID=$1
  _time_range=`awk -v _run_sequence=$2 'BEGIN{print 1-0.125*_run_sequence}'`
  echo "`date`, run rman for ${ORACLE_SID} with 'sysdate - $_time_range' " >> ${LOG_FILE}

  cat /dev/null > ${TMP_FILE_RMAN_OUT}


rman target / << EOF 1>${TMP_FILE_RMAN_OUT} 2>&1
delete noprompt archivelog all completed before 'sysdate - $_time_range';
crosscheck archivelog all;
EXIT
EOF

  # we should keep the RMAN output.
  cat ${TMP_FILE_RMAN_OUT} > /tmp/rman_out_${ORACLE_SID}_$2.txt
  _tmp_cnt=`grep "Deleted.*objects" ${TMP_FILE_RMAN_OUT} | wc -l`
  if [ ${_tmp_cnt} -eq 0 ]; then
    echo "`date`, Failed to clean up FRA by force for ${ORACLE_SID} with 'sysdate - $_time_range' " >> ${LOG_FILE}
  fi

}

cat /dev/null > ${LOG_FILE}
echo "========================= `date`, START. " >> ${LOG_FILE}

localhostname=`hostname -s`
_sid_list=`getmonitoreddblist "${localhostname}"`
#_sid_list=`ps -ef | grep ora_smon | grep -v " grep" | awk '{print $8}' | cut -d'_' -f3`

echo "======= get all the SID running at the server. " >> ${LOG_FILE}
echo "== SID list: " >> ${LOG_FILE}
echo "${_sid_list}" >> ${LOG_FILE}

## for each instance, we should loop 4 times to check and clean (if needed) with different time range.
for _sid in ${_sid_list} 
do
  isexist=`ps -aux | grep -v grep | grep -c ora_smon_${_sid}`
  if [ ${isexist} -eq 0 ]; then
      echo "The sid ${_sid} exist in depotdb but not on the server" >> ${LOG_FILE}
      continue
  fi
  echo " " >> ${LOG_FILE}
  echo "======= " >> ${LOG_FILE}

  _sn=0
  _is_ok=0
  
  while [ $_sn -lt 4 ]
  do

    echo " " >> ${LOG_FILE}
    echo "=== for SID: ${_sid}, loop sequence: ${_sn}" >> ${LOG_FILE}
    NEED_CLEAN ${_sid}
    _has_fra_issue=$?

    if [ $_has_fra_issue -eq 2 ]
    then
      echo "`date`, error while query FRA size for SID: ${_sid} " >> ${LOG_FILE}
      mailx -s "ERROR: error while query FRA size for SID: ${_sid} " ${MAILTO} < ${TMP_FILE_FRA_SIZE}
      break
    elif [ $_has_fra_issue -eq 0 ]
    then
      echo "=== FRA size is OK for SID: ${_sid}, will exist." >> ${LOG_FILE}
      _is_ok=1
      break
    else
      # echo "=== will call RMAN command to cleanup FRA for SID: ${_sid}" >> ${LOG_FILE}
      AUTOCLEANUP_FORCE ${_sid} ${_sn}
    fi
    
    let _sn++
  done  # end loop for the 4 times cleanup.

  ## we should verify again whether the FRA DG size is OK.
  if [[ ${_is_ok} -eq 0 && ${_sn} -gt 0 ]]
  then
    echo " " >> ${LOG_FILE}
    echo "=== for SID: ${_sid}, check the FRA size after ${_sn} times auto cleanup." >> ${LOG_FILE}
    NEED_CLEAN ${_sid}
    _has_fra_issue=$?
    
    if [ $_has_fra_issue -eq 1 ]
    then
      echo "`date`, can not fix FRA size issue for SID: ${_sid} after ${_sn} times cleanup." >> ${LOG_FILE}
      mailx -s "ERROR: Failed to clean up FRA by force for SID: ${_sid} after ${_sn} times cleanup" ${MAILTO} < ${TMP_FILE_FRA_SIZE}
    fi
  fi
  	
done  # end loop for the SID list.


echo " " >> ${LOG_FILE}
echo "========================= `date`, END. " >> ${LOG_FILE}

