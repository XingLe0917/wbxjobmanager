#!/bin/sh

source /staging/gates/bash_common.sh
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
#   zhiwliu        1/19/2021 - compatiable with oracle 19C, called by jobmanager
#   zhiwliu        12/18/2021 - Add kill session limitation as 2000
##########################################################################

export MAIL_TO=cwopsdba@cisco.com

usage() {
  echo ""
  echo "USAGE:"
  echo "      `basename $0` <ORACLE_SID>"
  echo "<ORACLE_SID>: if this parameter is missed, then scan all instance on this server"
}

#modify by wentazha @2020-12-02
. /home/oracle/.bash_profile

localhostname=`hostname -s`
curuser=`whoami`
if [ "${curuser}" != "oracle" ]; then
    echo "Current user ${curuser} is not oracle. EXIT"
    exit
fi
if [ $# -ne 1 ]; then
    SID_LIST=`getmonitoreddblist "${localhostname}"`
else
    SID_LIST=`ps aux | grep -i "ora_smon_$1" | grep -v grep | awk '{print $NF}' | awk -F '_' '{print $NF}'`
    if [ -z ${SID_LIST} ]; then
        echo "Invalid ORACLE_SID"
        echo "ERROR - The argument passed ($1) is not a valid ORACLE_SID on `hostname`." | /bin/mailx -s "ERROR - Terminate inactive session on `hostname`" ${MAIL_TO}
        exit 1
    fi
fi

export BIN_DIR=/u00/app/admin/dbarea/bin
export SQL_DIR=/u00/app/admin/dbarea/sql
export LOG_DIR=/u00/app/admin/dbarea/log

export PATH=$ORACLE_HOME/bin:$PATH

for sid in ${SID_LIST[@]}
do
    export ORACLE_SID=${sid}
    log_file="${LOG_DIR}/kill_session_${sid}.log"
    echo `date` >> ${log_file}
    totalcnt=0

    for i in `seq 1 20`
    do
$ORACLE_HOME/bin/sqlplus -S /nolog << EOSQL
conn as sysdba
/
set lines 80 pages 0
set feedback off
col username for a25
col "Minutes Inactive" for 999,999.99
set trims on
set trim on
set heading off
col SQL for a45
spool $SQL_DIR/kill_session.log
SELECT  '!kill -9 '||p.spid||';  |alter system kill session '''||s.sid||', '||s.serial#||'''; '
FROM v\$session s, v\$process p
WHERE s.paddr = p.addr
AND (s.last_call_et / 60) > 1440
AND s.status = 'INACTIVE'
AND s.type='USER'
AND s.username not like 'SPLEX%'
AND s.username not like 'SYS%'
AND s.username not like '%SYS'
AND s.username not in (
'AADINARAYAN', 'AGUJARE', 'AMIKUMAR', 'ANONYMOUS', 'ANVENKA', 'ATAMIZHMANI', 'BSUSAIMANICKAM', 'CHUA', 'CTXSYS', 'DBHEALTH', 'DBSNMP', 'DIP', 'DMSYS',
'EXFSYS', 'GUNSINGH', 'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OLAPSYS', 'ORACLE_OCM', 'ORDPLUGINS', 'ORDSYS', 'OUTLN', 'PKUMAR', 'PNAGABHUSHANAIAH', 'SBHADUPO',
'SCOTT', 'SI_INFORMTN_SCHEMA', 'SPLEX_DENY', 'SYS', 'SYSMAN', 'SYSTEM', 'TOUYANG', 'TSMSYS', 'WBXBACKUP', 'WBXDBA', 'WMSYS', 'XDB','SYSRAC')
AND rownum <=100;
spool off
exit
EOSQL
        _iCnt=0
        if [ -s $SQL_DIR/kill_session.log ]; then
            cat $SQL_DIR/kill_session.log >> ${log_file}
            cat /dev/null > $SQL_DIR/kill_session.sql
            while read _line
            do
                if [ "x${_line}" != "x" ]; then
                     _iCnt=`expr $_iCnt + 1`
                     _kill=`echo $_line|cut -d"|" -f1`
                     _sql=`echo $_line|cut -d"|" -f2`
                     echo $_sql  >> $SQL_DIR/kill_session.sql
                     echo $_kill >> $SQL_DIR/kill_session.sql
                     echo ""     >> $SQL_DIR/kill_session.sql
                fi
            done < $SQL_DIR/kill_session.log
           if [ ${_iCnt} -gt 0 ]; then
                totalcnt=$(( totalcnt + _iCnt ))
                sleep 30
$ORACLE_HOME/bin/sqlplus -S /nolog << EOSQL1
conn as sysdba
/
set feedback on
set echo on
set termout on
set head off
@$SQL_DIR/kill_session.sql
exit
EOSQL1
           else
               ##No more inactive session to kill
               break
           fi
        fi
    done
    echo "Killed ${totalcnt} session at `date`" >> ${log_file}
	linecnt=`wc -l ${log_file} | awk '{print $1}'`
	if [ ${linecnt} -gt 15000 ]; then
	    sed -i "1,5000d" ${log_file}
	fi
done