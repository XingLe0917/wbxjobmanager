#!/bin/sh
. /www/htdocs/webex/webex.sh
. /home/oracle/.bash_profile

##touch /tmp/test.txt
##echo|mailx -s "test.txt" cahua@cisco.com

$ORACLE_HOME/bin/sqlplus -s system/sysnotallow@racopdbha<<EOF
spool /tmp/pedp_opdb.lst
select count(*) 
from (
SELECT processid, count(*)   FROM TEST.WBXDISTMTGLOG WHERE starttime > SYSDATE-12/24 
AND (num_of_Late_pmtg > 0 OR num_of_pmtg > 0)  and processid >=0
and FINISHTIME is not null
group by processid
having count(*) >0) a;
spool off
EOF

flag_num=`grep  "[0-9]"  /tmp/pedp_opdb.lst`

if  [ "X$flag_num" = 'X' ]
then
flag_num=0
fi


if [ $flag_num -le 5 ] 
then
$ORACLE_HOME/bin/sqlplus -s system/sysnotallow@racopdbha<<EOF
spool /tmp/pedp_opdb.rpt
SELECT  count(unique processid) PROCESSID FROM TEST.WBXDISTMTGLOG WHERE starttime > SYSDATE - 12/24
AND (num_of_Late_pmtg > 0 OR num_of_pmtg > 0)  and processid >=0
and FINISHTIME is not null
and PROCESSID in ('0','1')
having count(*) >0;
spool off
EOF

flag_process=`grep  "[0-9]"  /tmp/pedp_opdb.rpt`

if  [ "X$flag_process" = 'X' ] 
then
flag_process=0
fi

if [ $flag_process -le 1 ]
then
sudo -u root  cp /etc/cron.d/pedp_cron /tmp/cron_current
sudo -u root  cat /tmp/cron_current|sed "s/\*\/2/####/g">/tmp/cron_temp
sudo -u root  cp /tmp/cron_temp  /etc/cron.d/pedp_cron

$ORACLE_HOME/bin/sqlplus -s sys/sysnotallow@racopdb1 as sysdba<<EOF
spool /tmp/pedp_sid.sql
@/u00/app/admin/dbarea/bin/pedr_kill.sql
@/u00/app/admin/dbarea/bin/pedr_kill.sql
@/u00/app/admin/dbarea/bin/pedr_kill.sql
@/u00/app/admin/dbarea/bin/pedr_kill.sql
@/u00/app/admin/dbarea/bin/pedr_kill.sql
@/u00/app/admin/dbarea/bin/pedr_kill.sql
@/u00/app/admin/dbarea/bin/pedr_kill.sql
@/u00/app/admin/dbarea/bin/pedr_kill.sql
@/u00/app/admin/dbarea/bin/pedr_kill.sql
spool off
@/tmp/pedp_sid.sql
EOF

$ORACLE_HOME/bin/sqlplus -s sys/sysnotallow@racopdb1 as sysdba<<EOF
@/tmp/pedp_sid.sql
EOF

$ORACLE_HOME/bin/sqlplus -s sys/sysnotallow@racopdb1 as sysdba<<EOF
@/tmp/pedp_sid.sql
EOF

sleep 3 

sudo -u root  cp /tmp/cron_current  /etc/cron.d/pedp_cron

###echo|mailx -s "PEDP is not running correctly and  and re-start it automatically in `hostname`" cahua@cisco.com
echo|mailx -s "PEDP is not running correctly and  and re-start it automatically in `hostname`" cwopsdba@cisco.com

sudo -u root  rm -rf /www/htdocs/webex/edr/*sql
fi

rm /tmp/pedp_opdb*
fi
