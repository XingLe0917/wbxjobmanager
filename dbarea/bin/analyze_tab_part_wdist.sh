#!/bin/ksh
set -x
############################################################
#
#  analyze tables and current partitions
#
#      1)   Oracle Service Name
#      2)   password file
#       3)   Schema owenr
#      4)   mailto email address
#
#     output:
#      1)   log file in standard log directory
#
#  25/01/08 By Annapurna
#
############################################################
if [ $# != 4 ]; then
echo
echo "Usage: analyze_tab_part.sh ORACLE_SID PASSWORDFILE  MAILTO"
echo
exit
fi

. /u00/app/admin/dbarea/.dbaprofile
ORACLE_SID=$1
export ORACLE_SID
SIGNON=`cat $PWDDIR/$2.pwd`
export SIGNON
MOWNER="'$3'"
export MOWNER
MAILTO=$4@cisco.com
export MAILTO
echo $ORACLE_SID


### Get current partitioned Date

m=`$SQLBIN/sqlplus -s $SIGNON << END
set heading off
select to_char(add_months(sysdate,1),'yyyy-mm')||'-01' from dual;
exit;
END`

a=`$SQLBIN/sqlplus -s $SIGNON << END
set heading off
select 'P'||to_char(add_months(sysdate,0),'yyyymm') from dual;
exit;
END`


####  Get the Partitioned Table List

$SQLBIN/sqlplus -s $SIGNON << END
set pages 0
set lin 350
spool $SQLDIR/temp.sql
set colsep ':'
select chr(39)||table_name||chr(39),chr(39)||partition_name||chr(39),chr(39)||'PARTITION'||chr(39),high_value
from dba_Tab_PARTITIONS where  table_OWNER=${MOWNER}
AND table_name='WBXMEETINGLOG_DIST'; 
spool off
exit;
END

#### Grep only for the current Partitions
ownnamee="ownname=>"${MOWNER}","

more $SQLDIR/temp.sql |grep $m |awk -F: '{print "exec dbms_stats.gather_table_stats('"$ownnamee"'tabname=>"$1",partname=>"$2",estimate_percent=>10,granularity=>"$3",cascade=> TRUE,degree=>8);"}' > $SQLDIR/analyze_part_dist.sql
more $SQLDIR/temp.sql |grep $a |awk -F: '{print "exec dbms_stats.gather_table_stats('"$ownnamee"'tabname=>"$1",partname=>"$2",estimate_percent=>10,granularity=>"$3",cascade=> TRUE,degree=>8);"}' >> $SQLDIR/analyze_part_dist.sql


## Get the list of tables to be analyzed

$SQLBIN/sqlplus -s $SIGNON << END
SET HEADING OFF
SET PAGES 0
SET LIN 250
set feedback off
spool $SQLDIR/analyze_ind_dist.sql
select 'exec dbms_stats.gather_index_stats('||chr(39)||owner||chr(39)||','||chr(39)||index_name||chr(39)||',estimate_percent=>10,granularity =>'||chr(39)||'ALL'||chr(39)||',degree=>8);' from dba_indexes where table_name='WBXMEETINGLOG_DIST';
spool off
exit;
END

## Analyze Tables and current Partitions
$SQLBIN/sqlplus -s $SIGNON << END
set echo on
spool $LOGDIR/analyze_dist_$ORACLE_SID.log
@$SQLDIR/analyze_part_dist.sql
@$SQLDIR/analyze_ind_dist.sql
spool off
exit;
END
