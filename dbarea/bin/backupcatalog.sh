#!/bin/ksh
export ORACLE_SID=cat11g02
export ORACLE_HOME=/u00/app/oracle/product/11.2.0/db
export SCRIPT_BIN=/u00/app/admin/dbarea/bin
BACKUP_DIR=/tadbwb_rman_vol/catalog/export
LOG_DIR=/tadbwb_rman_vol/catalog/export
DATE=`date +%Y%m%d%H%M`

# file to store all the catalog user info
_tmp_user_list=/tmp/catalog_user_$DATE.txt
> ${_tmp_user_list}
echo ${_tmp_user_list}

# 
# get all the catalog users in the _tmp_user_list file
# 

$ORACLE_HOME/bin/sqlplus -s /nolog << EOSQL > ${_tmp_user_list}
conn as sysdba
/
set pages 0 lines 2000 head off termout on serveroutput on feedback off echo off
declare
  cursor c_users is
    select distinct owner 
    from dba_views 
    where view_name = 'RC_DATABASE' 
       and owner in ( select grantee 
             from dba_role_privs
             where granted_role = 'RECOVERY_CATALOG_OWNER' and grantee not in ('SYS') )
    order by 1 ;
  v_users varchar2(4000) ;
begin
  v_users := '' ;
  for c_user in c_users
  loop
    v_users := v_users || c_user.owner || ',';
  end loop ;

  -- remove the last comma
  v_users := substr(v_users, 1, length(v_users) - 1 ) ;
  dbms_output.put_line ( v_users ) ;
end ;
/
EOSQL

# check if any user exists with RECOVERY_CATALOG_OWNER
if [ -s "${_tmp_user_list}" ]; then
  # file exists with size > 0

  # 
  # create the parfile for this export
  # 
  _exp_parfile=$BACKUP_DIR/exp_rac_catalog.par.$DATE
   > ${_exp_parfile}

  echo "userid=system/sysnotallow" >> ${_exp_parfile}
  echo "direct=Y"                  >> ${_exp_parfile}
  echo "buffer=2048000"            >> ${_exp_parfile}
  echo "statistics=none"           >> ${_exp_parfile}
  echo "owner=("                   >> ${_exp_parfile}
  cat ${_tmp_user_list}            >> ${_exp_parfile}
  echo ")"                         >> ${_exp_parfile}

  _exp_logfile=$BACKUP_DIR/exp_rac_catalog.log.$DATE
  _exp_dmpfile=$BACKUP_DIR/exp_rac_catalog.dmp.$DATE

  exp parfile=${_exp_parfile} log=${_exp_logfile} file=${_exp_dmpfile}

  grep "ORA-" ${_exp_logfile} > /tmp/error_log
  if [ -s /tmp/error_log ]; then
    /bin/mailx -s "Export of catalog schemas for 11G RAC failed" cwopsdba@cisco.com < ${_exp_logfile}
  fi

  gzip -f ${_exp_dmpfile}

  if [ $? -ne 0 ]; then
    echo -e "\nGzip Of RMAN catalog export failed.\n\nOlder backup files are not delete, which might cause disk space issues.\n\nPlease verify." | /bin/mailx -s "Gzip Of RMAN catalog export File failed" cwopsdba@cisco.com 
  else
    # remove export related files more than 10 days
    /usr/bin/find $BACKUP_DIR/ -name "exp_rac_catalog.log.*" -mtime +10 -exec rm -rf {} \;
    /usr/bin/find $BACKUP_DIR/ -name "exp_rac_catalog.par.*" -mtime +10 -exec rm -rf {} \;
    /usr/bin/find $BACKUP_DIR/ -name "exp_rac_catalog.dmp.*" -mtime +10 -exec rm -rf {} \;
  fi

else
  # file exists and size is 0.
  echo -e "No users with RECOVERY_CATALOG_OWNER privilege found.\n\nPlease verify." | /bin/mailx -s "No RMAN catalog user found" cwopsdba@cisco.com
fi

# remove temp files used
rm -rf ${_tmp_user_list}

exit 0

