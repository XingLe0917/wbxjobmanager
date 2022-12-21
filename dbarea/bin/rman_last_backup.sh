#!/bin/ksh
ORACLE_SID=cat11g02
ORACLE_HOME=/u00/app/oracle/product/11.2.0/db
export ORACLE_SID ORACLE_HOME PATH

SCRIPT_DIR=/u00/app/admin/dbarea/bin/
SCRIPT_LOG=/u00/app/admin/dbarea/log
export SCRIPT_DIR SCRIPT_LOG

export _MAIL_TO=cwopsdba@cisco.com

cat /dev/null > $SCRIPT_DIR/rman_last_backup.sql
cat /dev/null > $SCRIPT_LOG/rman_last_backup.sql
cat /dev/null > $SCRIPT_LOG/rman_last_backup.log

export _TMP_FILE=$SCRIPT_LOG/rman_last_backup.sql
export _SQL_FILE=$SCRIPT_DIR/rman_last_backup.sql

echo "set lines 151 pages 100" > ${_SQL_FILE}
echo "col status for a23" >> ${_SQL_FILE}
echo "select * from ( " >> ${_SQL_FILE}

DATE=`date +%Y%m%d%H%M`

# file to store all the catalog user info
_rman_db_par=${SCRIPT_LOG}/rman_db_last_$DATE.par
> ${_rman_db_par}
echo ${_rman_db_par}

#
# get all the catalog users in the _tmp_user_list file
#

$ORACLE_HOME/bin/sqlplus -s /nolog << EOSQL > ${_rman_db_par}
conn as sysdba
/
set pages 0 lines 2000 head off termout on serveroutput on feedback off echo off
select distinct owner 
from dba_views 
where view_name = 'RC_DATABASE' 
   and owner in ( select grantee 
             from dba_role_privs
             where granted_role = 'RECOVERY_CATALOG_OWNER' and grantee not in ('SYS') )
order by 1 ;
EOSQL

# check if any user exists with RECOVERY_CATALOG_OWNER
if [ -s "${_rman_db_par}" ]; then
  # file exists with size > 0

  typeset -i iCnt
  iCnt=0
  for i in `cat ${_rman_db_par}`
  do
    echo "select a.db_name \"Database\", " >> ${_TMP_FILE}
    echo "       db.dbid \"DBID\", db.RESETLOGS_TIME, " >> ${_TMP_FILE}
    echo "       to_char(a.end_time,'YYYY-MM-DD HH24:MI:SS') \"Latest Backup\", " >> ${_TMP_FILE}
    echo "       a.output_bytes/1024/1024/1024 \"GB Processed\", " >> ${_TMP_FILE}
    echo "       (end_time - start_time) * 60 * 60 * 24 \"Seconds Taken\", " >> ${_TMP_FILE}
    echo "       status, round(sysdate - a.end_time) \"Days Behind\" " >> ${_TMP_FILE}
    echo "from $i.rc_rman_status a, (select * from $i.rc_database where RESETLOGS_TIME = (select max(RESETLOGS_TIME) from $i.rc_database))  db " >> ${_TMP_FILE}
    echo "where object_type in ('DB FULL') " >> ${_TMP_FILE}
    echo "       and operation = 'BACKUP' " >> ${_TMP_FILE}
    echo "       and db.db_key = a.db_key " >> ${_TMP_FILE}
    echo "       and end_time = (select max(end_time) from $i.rc_rman_status b " >> ${_TMP_FILE}
    echo "                        where b.db_key = db.db_key " >> ${_TMP_FILE}
    echo "                        and b.db_name = a.db_name " >> ${_TMP_FILE}
    echo "                        and object_type in ('DB FULL') " >> ${_TMP_FILE}
    echo "                        and operation = 'BACKUP' " >> ${_TMP_FILE}
    echo "                       ) " >> ${_TMP_FILE}
    echo "union all " >> ${_TMP_FILE}
  done

  iCnt=`cat ${_TMP_FILE} | wc -l`

#echo "cnt 1: $iCnt"
  iCnt=`expr $iCnt - 1`
#echo "cnt 2: $iCnt"

  cat ${_TMP_FILE} | head -${iCnt} >> ${_SQL_FILE}
  echo ") " >> ${_SQL_FILE}
#echo "where status in ('FAILED', 'COMPLETED WITH WARNINGS') or (status = 'COMPLETED' and \"Days Behind\" > 1 )" >> ${_SQL_FILE}
  echo "order by 7 desc, 8 desc;" >> ${_SQL_FILE}
#echo "order by 8 desc;" >> ${_SQL_FILE}

  $ORACLE_HOME/bin/sqlplus -s /nolog << EOSQL 
    conn as sysdba
    /
    spool $SCRIPT_LOG/rman_last_backup.log
    @${_SQL_FILE}
    spool off
EOSQL

#_cnt=`cat $SCRIPT_LOG/rman_last_backup.log | grep "no rows selected" | wc -l`
#echo "_cnt = ${_cnt}"
#if [ ${_cnt} -eq 0 ]
#then
#  /bin/mailx -s "RMAN Backups STATUS for SJ" ${_MAIL_TO} < $SCRIPT_LOG/rman_last_backup.log
#else
  #echo "No rows selected...."
#fi

  /bin/mailx -s "RMAN Backups STATUS for SJ - ${ORACLE_SID}" ${_MAIL_TO} < $SCRIPT_LOG/rman_last_backup.log
else
  # file exists and size is 0.
  echo -e "No users with RECOVERY_CATALOG_OWNER privilege found for script `basename $0`.\n\nPlease verify." | /bin/mailx -s "No RMAN catalog user found" cwopsdba@cisco.com
fi

# remove the par file
rm -rf ${_rman_db_par}

exit

