#!/bin/sh

##########################################################################
#
#  NOTE
#    1. process.
#       a. get the input parameter as SID.
#       b. check whether there is FULL backup or restore running.
#       c. take actions as below if we are good to run.
#          c1. mount the folder for image and retain.
#          c2. run RMAN command "restore database validate".
#          c3. run "restore archivelog from time 'sysdate-8' validate;".
#          c4. we DO NOT umount the folder as it may impact the backup.
#       d. Write the status into depot for reference.
#
#
#  MODIFIED     (MM/DD/YYYY)
#    Edwin       05/25/2020 - Add logic for the nonstandard mount point.
#    Edwin       11/15/2018 - Move the precheck of RMAN to use python.
#    Edwin       10/30/2018 - Check logic to send restore status to depot.
#    Edwin       10/27/2018 - Check rman process to avoid the overlapping.
#    Edwin       10/25/2018 - Add input parameter SID as Samuel's request.
#    Edwin       10/22/2018 - Created.
#
##########################################################################

source /staging/gates/bash_common.sh
. /home/oracle/.bash_profile

## make sure the SID is there and running.
if [ $# -ne 1 ]; then
    localhostname=`hostname -s`
    ORACLE_SID_LIST=`getmonitoreddblist "${localhostname}"`
    
#    ORACLE_SID_LIST=`ps aux | grep ora_smon | grep -v grep | awk '{print $NF}' | awk -F '_' '{print $NF}'`
else
    ORACLE_SID_LIST=($1)
	SID_CNT=`ps -aef | grep -v " grep " | grep -wc "ora_smon_"$1`
    if [ "X${SID_CNT}" != "X1" ]; then
        echo "The ORACLE_SID is not running at this server."
        exit 1
    fi
fi

for ORACLE_SID in ${ORACLE_SID_LIST[@]}
do
    isexist=`ps -aux | grep -v grep | grep -c ora_smon_${_sid}`
    if [ ${isexist} -eq 0 ]; then
        echo "The sid ${_sid} exist in depotdb but not on the server"
        continue
    fi
    ORACLE_SID=${ORACLE_SID}; export ORACLE_SID
    LEN=`expr ${#ORACLE_SID} - 1`
    DB_NAME=${ORACLE_SID:0:$LEN}
    LOG_PATH=/staging/datadomain/scripts/logs/${DB_NAME}
    MAILTO=cwopsdba@cisco.com
	
    ## make sure the folder is there.
    if ! [ -d ${LOG_PATH} ]; then
        mkdir -p ${LOG_PATH}
    fi
    
    DATENOW="`date +%Y%m%d%H%M%S`"
    RESTORE_LOG=${LOG_PATH}/rman_restore_validate_${ORACLE_SID}_${DATENOW}.log
    
    STAT_FILE=/tmp/tmp_rman_restore_stat_${ORACLE_SID}.txt
    cat /dev/null > ${STAT_FILE}
    
    TMP_FILE=/tmp/tmp_rman_session_cnt_${ORACLE_SID}.txt
    cat /dev/null > ${TMP_FILE}
    
    echo "== begin the validate for $ORACLE_SID" > ${RESTORE_LOG}
    echo "== start time: $DATENOW" >> ${RESTORE_LOG}
    
    echo "== " >> ${RESTORE_LOG}
    echo "== start to check whether there is RMAN full backup for restore running." >> ${RESTORE_LOG}
    echo "== " >> ${RESTORE_LOG}

###### make sure NO full backup or the restore process running for this SID.

_script_status="start"

python /staging/datadomain/scripts/check_rman_full_run.py ${ORACLE_SID} ${TMP_FILE}

_go=`grep "^FLAG:OK" ${TMP_FILE} | wc -l`

if [ ${_go} -eq 1 ]; then
  echo "== NO full backup or restore validate running now for ${ORACLE_SID}, will start the restore validate. " >> ${RESTORE_LOG}
  _script_status="ok_to_run_rman"
else
  echo "ERROR: Not run RMAN restore validate for DB: ${DB_NAME} " >> ${RESTORE_LOG}
  echo "The output of the RMAN process checking as below, in file ${TMP_FILE} " >> ${RESTORE_LOG}
  cat ${TMP_FILE} >> ${RESTORE_LOG}
  _script_status="rman_running_now"
  mailx -s "ERROR: Not run RMAN restore validate for DB: ${DB_NAME} " ${MAILTO} < ${RESTORE_LOG}
fi

###### END of checking RMAN process running or not.

## Now, it is OK to valdiate.
if [ ${_go} -eq 1 ]; then
  if sudo cat /etc/fstab | grep -v "^#" | grep -wc "/sg_rman_backup_new" &>/dev/null; then
    sudo mount /sg_rman_backup_new      # for SG
  elif sudo cat /etc/fstab | grep -v "^#" | grep -wc "/db_backup" &>/dev/null; then
    sudo mount /db_backup               # for SY
  elif sudo cat /etc/fstab | grep -v "^#" | grep -wc "/rman_offline_cndbwbao" &>/dev/null; then
    sudo mount /rman_offline_cndbwbao   # for TO
  elif sudo cat /etc/fstab | grep -v "^#" | grep -wc "/blrracth_backup" &>/dev/null; then
    sudo mount /blrracth_backup         # for BL
  else
    sudo mount /image_${DB_NAME}
    sudo mount /retain_${DB_NAME}
  fi

  _script_status="mount_and_run"
  ## run RMAN command.

rman target / << EOF >> ${RESTORE_LOG}
show all;
restore database validate;
restore archivelog from time 'sysdate-8' validate;
EXIT
EOF

  ## check out the LAST status for the restore, we know the start time of this script.
  _script_status="get_status_after_run"
  echo "== " >> ${RESTORE_LOG}
  echo "== end the restore validate command. will check the status from DB." >> ${RESTORE_LOG}
  echo "== " >> ${RESTORE_LOG}


sqlplus -s / as sysdba <<EOF 1>${STAT_FILE} 2>&1
alter session set optimizer_mode=RULE;

set pagesize 0 feedback off heading off echo off

select 'DBFULL_RESTORE,'||r.status||','||to_char(r.start_time, 'yyyymmddhh24miss')||','||to_char(r.end_time, 'yyyymmddhh24miss')
from v\$rman_status r
where r.operation = 'RESTORE VALIDATE' and r.object_type = 'DB FULL' and r.end_time = (
select max(end_time)
from v\$rman_status
where operation = 'RESTORE VALIDATE' and object_type = 'DB FULL' and start_time >= to_date('${DATENOW}', 'yyyymmddhh24miss') and end_time is not NULL);

select 'ARCHIVELOG_RESTORE,'||r.status||','||to_char(r.start_time, 'yyyymmddhh24miss')||','||to_char(r.end_time, 'yyyymmddhh24miss')
from v\$rman_status r
where r.operation = 'RESTORE VALIDATE' and r.object_type = 'ARCHIVELOG' and r.end_time = (
select max(end_time)
from v\$rman_status
where operation = 'RESTORE VALIDATE' and object_type = 'ARCHIVELOG' and start_time >= to_date('${DATENOW}', 'yyyymmddhh24miss') and end_time is not NULL);

EXIT;
EOF

fi


## write down the restore info into depot, call Python script and the tmp file as input.
_script_status="restore_script_finished"
ENDTIME="`date +%Y%m%d%H%M%S`"

echo "SCRIPT_INFO,${_script_status},${DATENOW},${ENDTIME}" >> ${STAT_FILE}
echo "BASE_INFO,`hostname -s`,${ORACLE_SID},${DB_NAME}" >> ${STAT_FILE}

python /staging/datadomain/scripts/send_rman_restore_validate_status_2_depot.py ${STAT_FILE}

## END of this RMAN validate job.
echo "== " >> ${RESTORE_LOG}
echo "== end the validaet for $ORACLE_SID" >> ${RESTORE_LOG}
echo "== end time: ${ENDTIME}" >> ${RESTORE_LOG}
done
