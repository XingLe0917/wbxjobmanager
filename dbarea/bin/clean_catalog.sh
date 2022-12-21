#!/bin/ksh
ORACLE_SID=cat11g02
ORACLE_HOME=/u00/app/oracle/product/11.2.0/db
export ORACLE_SID ORACLE_HOME

SCRIPT_DIR=/u00/app/admin/dbarea/bin
SCRIPT_LOG=/u00/app/admin/dbarea/log
export SCRIPT_DIR SCRIPT_LOG

# file to store all the catalog user info
_rman_db_par=${SCRIPT_LOG}/rman_db_clean_cat_$DATE.par
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

  for i in `cat ${_rman_db_par}`
  do
  echo $i >>$SCRIPT_LOG/cleanup_catalog.log
  sqlplus -S $i/rman << EOSQL >> $SCRIPT_LOG/cleanup_catalog.log
    @$SCRIPT_DIR/cleanup_catalog.sql
EOSQL
  done
else
  # file exists and size is 0.
  echo -e "No users with RECOVERY_CATALOG_OWNER privilege found for script `basename $0`.\n\nPlease verify." | /bin/mailx -s "No RMAN catalog user found" cwopsdba@cisco.com
fi

#if [ -s /tmp/status.log ]
#then
#/bin/mailx -s "RMAN Backups Failed For $i - On-Call DBA Please Check--URGENT" cwopsdba@cisco.com,atsdba.on-call@cisco.com </tmp/status.log
#/bin/mailx -s "RMAN Backups Failed For $i - On-Call DBA Please Check--URGENT" cwopsdba@cisco.com </tmp/status.log

#fi

#done

exit
