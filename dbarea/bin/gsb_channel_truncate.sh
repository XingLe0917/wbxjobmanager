#! /bin/sh
. /home/oracle/.bash_profile
SCRIPT_HOME='/u00/app/admin/dbarea/bin'
TEMP_HOME=$SCRIPT_HOME/tmp
LOG_HOME=$SCRIPT_HOME/log

test -d $TEMP_HOME
if [ $? = 1 ]  ;then
    mkdir -m 777 -p $TEMP_HOME
fi

test -d $LOG_HOME
if [ $? = 1 ]  ;then
    mkdir -m 777 -p $LOG_HOME
fi

########################################################################
# Log File
########################################################################
DATE_D=`date +%Y%m%d%H%M%S`
LOGFILENAME="$DATE_D"_gsb_channel_truncate.log
LOG=$LOG_HOME/$LOGFILENAME

LOGERRFILENAME="$DATE_D"_gsb_channel_truncate_error.log
LOGERR=$SCRIPT_HOME/log/$LOGERRFILENAME

:>$LOG
:>$LOGERR

help_msg()
{
more <<EOF
Usage:
$0 schema_username gsbtns_name gsb_domainname
  Parameter list as following:
    [schema_username]: connected GSB database schema's owner user [test]
    [password_type]: connected GSB database password type [newpwd,oldpwd,newpwd_php]
    [instance_name]:   connected GSB database tns name [racbvwebha]
    [gsb_domainname]:  GSB domain name like [atwd,gtwd]
    
EOF
}

#MAIN

  if [ $# != 4 ]; then
      echo "The attached parameters are wrong, Please check Usage:"
      help_msg
      echo
      exit 0
  fi            

############read Pwd from file#######################
ORACLE_USER=$1
ORACLE_SID=$3
GSB_DOMAINNAME=$4
export ORACLE_DBA=/u00/app/admin/dbarea
export ORACLE_PASSWORD=`cat $ORACLE_DBA/pwdfile/$2.pwd`
export WBXDBA_PASSWORD=`cat $ORACLE_DBA/pwdfile/wbxdba.pwd`
#######################################################

echo "Check DB connection ..." |tee -a $LOG
checkDBConn()
{
    $ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID << EOF
    SET SERVEROUTPUT ON ;
    SET FEEDBACK OFF;
    SET HEADING ON;
    SET ECHO OFF;
    SET TERM OFF;
    SET LINESIZE 255;
    DECLARE
        v_Time DATE;
    BEGIN
        SELECT SYSDATE INTO v_Time FROM DUAL;
        DBMS_OUTPUT.PUT_LINE('OK');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('FAILED');
    END;
/
EXIT
EOF
    return
}

if [ -z `checkDBConn | grep "OK"` ]
then
   vhostname=`hostname`
   echo "  Error: Test connecting to DB by "$ORACLE_USER"/"$ORACLE_PASSWORD"@"$ORACLE_SID" [FAILED]" | tee -a $LOGERR
   echo " "
   exit 
fi

echo "Check DB type ..." |tee -a $LOG
checkDBType()
{
    $ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID << EOF
    SET SERVEROUTPUT ON ;
    SET FEEDBACK OFF;
    SET HEADING ON;
    SET ECHO OFF;
    SET TERM OFF;
    SET LINESIZE 255;
    DECLARE
        vdbtype VARCHAR2(56);
    BEGIN
        SELECT dbtype INTO vdbtype FROM wbxdatabaseversion;
        DBMS_OUTPUT.PUT_LINE(vdbtype);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('FAILED');
    END;
/
EXIT
EOF
    return
}

if [ "`checkDBType`" != "WEBDB_GSB" ] 
then
   echo "  Error: Check DB type "$ORACLE_USER"/"$ORACLE_PASSWORD"@"$ORACLE_SID" [FAILED]" | tee -a $LOGERR
   echo " The DB type is not in (WEBDB_GSB) " | tee -a $LOGERR
   echo " "
   exit 
fi

####checking related primary failover status##########
$ORACLE_HOME/bin/sqlplus -S wbxdba/$WBXDBA_PASSWORD@racopdbha >$TEMP_HOME/domain.lst<< EOF
  SET SERVEROUTPUT off ;
  SET FEEDBACK OFF;
  SET HEADING OFF;
  SET ECHO OFF;
  SET TERM OFF;
  SET LINESIZE 255;
  col  gsb_domain for a10
  col  pri_domain for a10

  SELECT   gsb_domain.domainname AS gsb_domain,pri_domain.domainname as pri_domain,
         'http://gpstest-'||to_char(substr(pri_domain.domainname,1, instr(pri_domain.domainname,'wd')-1))||'.webex.com/webex/gsbstatus.php' AS pri_url 
           FROM (SELECT b.domainid, b.domainname, a.gsblocation,b.active
           FROM test.wbxgsbdomainconfig a, test.wbxwebdomain b
          WHERE a.domaintype = 0 AND a.domainid = b.domainid) gsb_domain,
        (SELECT b.domainid, b.domainname, a.gsblocation, a.VERSION,b.active
           FROM test.wbxgsbdomainconfig a, test.wbxwebdomain b
          WHERE a.domaintype = 1 AND a.domainid = b.domainid) pri_domain
  WHERE gsb_domain.gsblocation = pri_domain.gsblocation
  and upper(gsb_domain.domainname)  =upper('$GSB_DOMAINNAME')
  and pri_domain.domainname not like 'd%'
  and pri_domain.active ='1'
  ORDER BY gsb_domain.domainname, pri_domain.domainname;

  SELECT          gsb_domain.domainname AS gsb_domain,pri_domain.domainname as pri_domain,
       'http://gpstest-'||to_char(substr(pri_domain.domainname,2, instr(pri_domain.domainname,'wd')-2))||'.webex.com/webex/gsbstatus.php' AS pri_url
   FROM (SELECT b.domainid, b.domainname, a.gsblocation,b.active
           FROM test.wbxgsbdomainconfig a, test.wbxwebdomain b
          WHERE a.domaintype = 0 AND a.domainid = b.domainid) gsb_domain,
        (SELECT b.domainid, b.domainname, a.gsblocation, a.VERSION,b.active
           FROM test.wbxgsbdomainconfig a, test.wbxwebdomain b
          WHERE a.domaintype = 1 AND a.domainid = b.domainid) pri_domain
  WHERE gsb_domain.gsblocation = pri_domain.gsblocation
  and upper(gsb_domain.domainname)  =upper('$GSB_DOMAINNAME')
  and pri_domain.domainname   like 'd%' and pri_domain.domainname  not like 'dz%'
  and  pri_domain.active ='1'
  ORDER BY gsb_domain.domainname, pri_domain.domainname;

   SELECT          gsb_domain.domainname AS gsb_domain,pri_domain.domainname as pri_domain,
       'http://mcttest-'||to_char(substr(pri_domain.domainname,2, instr(pri_domain.domainname,'wd')-2))||'.webex.com/webex/gsbstatus.php' AS pri_url
   FROM (SELECT b.domainid, b.domainname, a.gsblocation,b.active
           FROM test.wbxgsbdomainconfig a, test.wbxwebdomain b
          WHERE a.domaintype = 0 AND a.domainid = b.domainid) gsb_domain,
        (SELECT b.domainid, b.domainname, a.gsblocation, a.VERSION,b.active
           FROM test.wbxgsbdomainconfig a, test.wbxwebdomain b
          WHERE a.domaintype = 1 AND a.domainid = b.domainid) pri_domain
  WHERE gsb_domain.gsblocation = pri_domain.gsblocation
  and upper(gsb_domain.domainname)  =upper('$GSB_DOMAINNAME')
  and pri_domain.domainname  like 'dz%'
  and  pri_domain.active ='1'
  ORDER BY gsb_domain.domainname, pri_domain.domainname;
EOF

pri_num=`cat $TEMP_HOME/domain.lst|grep -i wd|wc -l`

if [ $pri_num = 0 ]
then
   echo "No Any Primaries Running Under this gdb domain $GSB_DOMAINNAME, pls check it..." | tee -a $LOGERR
   exit
fi

:> $TEMP_HOME/checkfailover.log

cat $TEMP_HOME/domain.lst|grep -i wd |while read line
do
  vcluster=`echo $line|awk '{print $2}'`
  urlstr=`echo $line|awk '{print $3}'`
  echo $urlstr
  result=`curl $urlstr`
  if [ "$result" != "FALSE" ]; then
      echo "Error:cluster $vcluster has failover or fail to check,can not execute this change" >> $TEMP_HOME/checkfailover.log
     exit
  fi
done

if [ $? -ne 0 ] || [ -n "`cat $TEMP_HOME/checkfailover.log | grep -i "ERROR"`" ] ; then
    cat $TEMP_HOME/checkfailover.log | tee -a $LOGERR
    exit
fi
##########################end checking failover status#############################

##########################start to generate truncate parttition and rebuild index sql##
$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID >$TEMP_HOME/partition_drop.sql<< EOF
  SET SERVEROUTPUT off ;
  SET FEEDBACK OFF;
  SET HEADING OFF;
  SET ECHO off;
  SET TERM OFF;
  SET LINESIZE 255;

  select 'alter table '||table_name||' truncate partition '|| partition_name||' UPDATE GLOBAL INDEXES PARALLEL (DEGREE 10);' 
  from user_tab_partitions where (table_name like '%LOOKUP%' or  table_name like '%GSB%' 
  or table_name like 'OPDB%' or   table_name like 'GWDB%' ) 
 -- and table_name not like '%PRI2_GSB'
  and   num_rows > 0
  and  substr(partition_name,-2) !=  to_char(sysdate,'mm')
  order by  table_name;
EOF

$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID << EOF
@$TEMP_HOME/partition_drop.sql
EOF

$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID >$TEMP_HOME/index_rebuild.sql<< EOF
  SET SERVEROUTPUT off ;
  SET FEEDBACK OFF;
  SET HEADING OFF;
  SET ECHO off;
  SET TERM OFF;
  SET LINESIZE 255;

  select 'alter index '||index_name||' rebuild;' 
  from user_indexes
  where status like 'UN%';
EOF

$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID << EOF
@$TEMP_HOME/index_rebuild.sql
exec TEST.spValidate
EOF


#########analyze all gsb tables############################
$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID >$TEMP_HOME/partition_ana.sql<< EOF
  SET SERVEROUTPUT off ;
  SET FEEDBACK OFF;
  SET HEADING OFF;
  SET ECHO off;
  SET TERM OFF;
  SET LINESIZE 255;

  select 'analyze table '||table_name||' estimate statistics sample 7 percent ;'
  from user_tab_partitions where (table_name like '%LOOKUP%' or  table_name like '%GSB%'
  or table_name like 'OPDB%' or   table_name like 'GWDB%' )
  --and table_name not like '%PRI2_GSB'
  and   num_rows > 0
  and  substr(partition_name,-2) !=  to_char(sysdate,'mm')
  order by  table_name;
EOF

sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID << EOF
@$TEMP_HOME/partition_ana.sql
EOF
###############################################################

##################################verification part####################################################
$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID >$TEMP_HOME/index_unnum<< EOF
  SET SERVEROUTPUT off ;
  SET FEEDBACK OFF;
  SET HEADING OFF;
  SET ECHO off;
  SET TERM OFF;
  SET LINESIZE 255;

  select count(*)
  from user_indexes
  where status like 'UN%';
EOF

flag_num=`grep  "[0-9]"  $TEMP_HOME/index_unnum`

if [ $flag_num -ge 1 ]
then
$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID >$TEMP_HOME/index_rebuild.sql<< EOF
  SET SERVEROUTPUT off ;
  SET FEEDBACK OFF;
  SET HEADING OFF;
  SET ECHO off;
  SET TERM OFF;
  SET LINESIZE 255;

  select 'alter index '||index_name||' rebuild;'
  from user_indexes
  where status like 'UN%';
EOF

$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID >$TEMP_HOME/index_unnum<< EOF
  SET SERVEROUTPUT off ;
  SET FEEDBACK OFF;
  SET HEADING OFF;
  SET ECHO off;
  SET TERM OFF;
  SET LINESIZE 255;

@$TEMP_HOME/index_rebuild.sql
exec TEST.spValidate
select count(*) from user_indexes where status like 'UN%';
EOF
fi

flag_num=`grep  "[0-9]"  $TEMP_HOME/index_unnum`

if [ $flag_num -ge 1 ]
then
###echo|mailx -s "These indexes in GSB channel tables is unusable in $ORACLE_SID, oncall dba pls check and rebuild it manually" < $TEMP_HOME/index_rebuild.sql cahua@cisco.com
echo|mailx -s "These indexes in GSB channel tables is unusable in $ORACLE_SID, oncall dba pls check and rebuild it manually" < $TEMP_HOME/index_rebuild.sql cwopsdba@cisco.com
fi
