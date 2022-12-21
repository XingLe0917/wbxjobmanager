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
$0 schema_username schema_password gsbtns_name gsb_domainname
  Parameter list as following:
    [schema_username]: connected PRI database schema's owner user [test]
    [password_type]: connected GSB database password type [newpwd,oldpwd,newpwd_php]
    [instance_name]:   connected PRI database tns name [racbvwebha]
    [gsb_domainname]:  PRI domain name like [atwd,gtwd]
    
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
PRI_DOMAINNAME=$4
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

if [ "`checkDBType`" != "WEBDB" ] 
then
   echo "  Error: Check DB type "$ORACLE_USER"/"$ORACLE_PASSWORD"@"$ORACLE_SID" [FAILED]" | tee -a $LOGERR
   echo " The DB type is not in Primary webdb " | tee -a $LOGERR
   echo " "
   exit 
fi

##########################check if primary failover already##############################
$ORACLE_HOME/bin/sqlplus -S wbxdba/$WBXDBA_PASSWORD@racopdbha >$TEMP_HOME/domain.lst<< EOF
  SET SERVEROUTPUT off ;
  SET FEEDBACK OFF;
  SET HEADING OFF;
  SET ECHO OFF;
  SET TERM OFF;
  SET LINESIZE 255;
  col  gsb_domain for a10
  col  pri_domain for a10

  SELECT  case when domainname like 'd%' and domainname not like 'dzwd' then
 'http://gpstest-'||to_char(substr(domainname,2, instr(domainname,'wd')-2))||'.webex.com/webex/gsbstatus.php'
  when domainname like 'dzwd' then
  'http://mcttest-'||to_char(substr(domainname,2, instr(domainname,'wd')-2))||'.webex.com/webex/gsbstatus.php'
  else
 'http://gpstest-'||to_char(substr(domainname,1, instr(domainname,'wd')-1))||'.webex.com/webex/gsbstatus.php'
  end
 from test.wbxwebdomain
 WHERE upper(domainname)  =upper('$PRI_DOMAINNAME');
EOF

pri_num=`cat $TEMP_HOME/domain.lst|grep -i gsbstatus|wc -l`

if [ $pri_num = 0 ]
then
   echo "No This Primaries Running $PRI_DOMAINNAME, pls check it..." | tee -a $LOGERR
   exit
fi

vcluster=`cat $TEMP_HOME/domain.lst`
echo $vcluster
result=`curl $vcluster`
echo $result 

if [ "$result" = "FALSE" ]; then  {
     echo " Primary :cluster $PRI_DOMAINNAME has  not been failover,execute gsb channel table in primary" 
     echo " Primary :cluster $PRI_DOMAINNAME has  not been failover,execute gsb channel tables in primary" >> $TEMP_HOME/checkfailover.log
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
    and table_name not like '%PRI2_GSB'
    and   num_rows > 0
    and  substr(partition_name,-2) !=  to_char(sysdate,'mm')
    order by  table_name;
EOF
    }
else if [ "$result" = "TRUE" ]; then {
   echo " Primary :cluster $PRI_DOMAINNAME has been failover,execute primary channel table in primary"
   echo " Primary :cluster $PRI_DOMAINNAME has been failover,execute primary channel tables in primary" >> $TEMP_HOME/checkfailover.log
   $ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID >$TEMP_HOME/partition_drop.sql<< EOF
    SET SERVEROUTPUT off ;
    SET FEEDBACK OFF;
    SET HEADING OFF;
    SET ECHO off;
    SET TERM OFF;
    SET LINESIZE 255;

    select 'alter table '||table_name||' truncate partition '|| partition_name||' UPDATE GLOBAL INDEXES PARALLEL (DEGREE 10);'
    from user_tab_partitions 
    where table_name like '%PRI2_GSB'
    and   num_rows > 0
    and  substr(partition_name,-2) !=  to_char(sysdate,'mm')
    order by  table_name;
EOF
    }
else
    echo " Primary :cluster $PRI_DOMAINNAME fail to check failover status"
    echo " Primary :cluster $PRI_DOMAINNAME fail to check failover status" >> $TEMP_HOME/checkfailover.log
    exit
    fi
fi
##########################end checking failover status#############################

##########################start to run truncate parttition and rebuild index sql##
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


#########analyze all gsb tables##################
$ORACLE_HOME/bin/sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID >$TEMP_HOME/partition_ana.sql<< EOF
  SET SERVEROUTPUT off ;
  SET FEEDBACK OFF;
  SET HEADING OFF;
  SET ECHO off;
  SET TERM OFF;
  SET LINESIZE 255;

  select distinct 'analyze table '|| table_name||' estimate statistics sample 7 percent ;'
  from user_tab_partitions where (table_name like '%LOOKUP%' or  table_name like '%GSB%'
  or table_name like 'OPDB%' or   table_name like 'GWDB%' )
  and   num_rows > 0
  and  substr(partition_name,-2) !=  to_char(sysdate,'mm') ;
EOF

sqlplus -S $ORACLE_USER/$ORACLE_PASSWORD@$ORACLE_SID << EOF
@$TEMP_HOME/partition_ana.sql
EOF


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
###echo|mailx -s "Some indexes is unusable in $ORACLE_SID, oncall dba pls check and rebuild it manually" cwopsdba@cisco.com
echo|mailx -s "These indexes in GSB channel tables is unusable in $ORACLE_SID, oncall dba pls check and rebuild it manually" < $TEMP_HOME/index_rebuild.sql cahua@cisco.com
fi
