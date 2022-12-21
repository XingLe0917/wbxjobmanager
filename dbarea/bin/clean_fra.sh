#! /bin/sh

# @(#)auto_cleanup_fra.sh       5.00 May. 2014
# Enhanced at Mar. 2015 Ver 8.00
# Created by Jing Xu  Email: jingx@cisco.com

#
#This shell only for cleaning up Fra storage
#Configured item only for catalogDB, check with Juan if you have any question
#Wiki for details: http://wikicentral.cisco.com/display/GROUP/FRA+auto+clean+up+tool
#

#cron as below if server backup configured on catalogdb
#12,46 * * * * /u00/app/admin/dbarea/bin/clean_fra.sh CAT11G01 > /u00/app/admin/dbarea/log/cleanfratrace.log
#cron as below if server backup on local
#12,46 * * * * /u00/app/admin/dbarea/bin/clean_fra.sh local > /u00/app/admin/dbarea/log/cleanfratrace.log

CallPythonPCA()
{
echo "#!/usr/bin/env python
import httplib
HOST = \"stap.webex.com:80\"
API_URL = \"/stap/xmlapi/pca.action?AT=InsertPCAJobData\"
xml_location=\"/tmp/FRAPCAXmlReq.xml\"

def do_request():
    \"\"\"HTTP XML Post request\"\"\"
    request = open(xml_location, \"r\").read()

    webservice = httplib.HTTP(HOST)
    webservice.putrequest(\"POST\", API_URL)
    webservice.putheader(\"Host\", HOST)
    webservice.putheader(\"User-Agent\", \"Python post\")
    webservice.putheader(\"Content-type\", \"text/xml; charset=\\\"UTF-8\\\"\")
    webservice.putheader(\"Content-length\", \"%d\" % len(request))
    webservice.endheaders()
    webservice.send(request)
    statuscode,statusmessage,header1 = webservice.getreply()    
    result=webservice.getfile().read()
    print (result) 
try:
    do_request()
except:
    print (\"Oops! Connect to stap.webex.com failed.\")
"  > /tmp/FRAPythonPCA.py
chmod 755 /tmp/FRAPythonPCA.py
python /tmp/FRAPythonPCA.py
}


XMLRequest()
{
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<stap>
<PCAMonitor tb=\"wbxcleanfrahistory\" username=\"pcaapiuser\" password=\"TaCu#2012\">" >/tmp/FRAPCAXmlReq.xml
echo "<Result>
    <diskname>"$franame"</diskname>
    <hostname>"$vhostname"</hostname>
	  <totalsize>"$totalsize"</totalsize>
    <beforecleanfreesize>"$freesize_bc"</beforecleanfreesize>
	  <BeforecleanLeftPCT>"$Left_PCTbc"</BeforecleanLeftPCT>
    <aftercleanfreesize>"$freesize_ac"</aftercleanfreesize>
    <aftercleanLeftPCT>"$Left_PCTac"</aftercleanLeftPCT> 
    <logbackuped>"$logbackuped"</logbackuped> 
</Result>" >> /tmp/FRAPCAXmlReq.xml
echo "</PCAMonitor>
</stap>" >> /tmp/FRAPCAXmlReq.xml
chmod 755 /tmp/FRAPCAXmlReq.xml
test -f /tmp/FRAPCAXmlReq.xml && CallPythonPCA
rm -f /tmp/FRAPCAXmlReq.xml
}

GetOptStatus()
{
XMLRequest
}

. /home/oracle/.asm_profile

ARGV=$1
CATALOGDB=$1
#MAILLISTDBA="cwopsdba@cisco.com"
#MAILLIST="jingx@cisco.com,hatty@cisco.com,qima@cisco.com,jennzhou@cisco.com"
MAILLIST="jingx@cisco.com"
#ERRORMAILLIST="jingx@cisco.com,hatty@cisco.com,qima@cisco.com,jennzhou@cisco.com"
ERRORMAILLIST="jingx@cisco.com"
vhostname=`hostname`

if [ "x$ARGV" = "x" ]
then 
echo " Failed to attach catalogDB parameter for cronjob - clean_fra.sh " | mailx -s "ERROR: Failed to attach catalogDB parameter for FRA clean up job from $vhostname"  "$ERRORMAILLIST" 
  exit 0
fi
rm -f $ADMIN_HOME/log/$ARGV*.log

LOG=$ADMIN_HOME/log/$ARGV.log
  
echo "">$LOG

senddata=N
logbackuped=N

#needbackup only for some dbs that can't delete data only after archive logs backuped
DELVALUE=14
needbackup=N

if [ -z $ORA_DB_HOME ] ;then
   echo 
   in=`ps -ef|grep pmon|grep -v ASM|grep -v grep|awk '{print $8}'|awk -F_ '{print $3}' |sed -n 1p`
   n=`ps -ef|grep pmon|grep -v ASM|grep -v grep|awk '{print $8}'|awk -F_ '{print $3}' |wc -l`
   dn=`echo $in | cut -c 1-$(expr ${#in} - 1)` 
   if [ $n -gt "0" ] ;then
      export ORACLE_HOME=`cat /etc/oratab |grep -i "$dn" |awk -F":" '{print $2}' |sed -n 1p`
      echo ORACLE_HOME from /etc/oratab  [$ORACLE_HOME]
      if [ -z $ORACLE_HOME ] ;then
         echo "ERROR: Unable to find ORACLE_HOME from /etc/oratab" >>$LOG
         mailx -s "ERROR: Failed to check FRA storage utilization from $vhostname"  "$ERRORMAILLIST"   < $LOG
         exit 0
      fi 
   else
      echo "ERROR: Unable to find oracle service process(PMON) is running" >>$LOG
      mailx -s "ERROR: Failed to check FRA storage utilization from $vhostname"  "$ERRORMAILLIST" < $LOG
      exit 0  
   fi   
   
else
	export ORACLE_HOME=$ORA_DB_HOME;
	echo ORACLE_HOME=$ORACLE_HOME >>$LOG
fi

echo `date`": check fra free_mb < $DELVALUE%" >>$LOG

autocleanup()
{	  	  
rman target / catalog $dbname/rman@$CATALOGDB << EOF  > $ADMIN_HOME/log/$ARGV-autocleanup.log
delete noprompt archivelog until time 'sysdate -1' backed up 1 times to disk;
EXIT
EOF
return 101
}

autocleanup_force()
{	  	  
rman target / << EOF
delete noprompt archivelog all completed before 'sysdate-1';
crosscheck archivelog all;
EXIT
EOF
}

autocleanup_force21H()
{	   	  
rman target / << EOF
delete noprompt archivelog all completed before 'sysdate-0.875';
crosscheck archivelog all;
EXIT
EOF
}

autocleanup_force18H() 
{	   	
rman target / << EOF
delete noprompt archivelog all completed before 'sysdate-0.75';
crosscheck archivelog all;
EXIT
EOF
}

autocleanup_force15H()
{	   	  
rman target / << EOF
delete noprompt archivelog all completed before 'sysdate-0.625';
crosscheck archivelog all;
EXIT
EOF
}

Getdata_before()
{
sqlplus -S "/as sysdba"  <<EOF 
SET pagesize 0 feedback off heading off echo off  
SELECT a.name||','||a.total_mb||','||a.free_mb||','||round(a.free_mb*100/a.total_mb,2)||',$vinstancename,'||b.db_name FROM v\$asm_diskgroup a,v\$asm_client b,v\$parameter c 
WHERE c.name='db_name' AND c.value=b.db_name AND b.group_number=a.group_number AND a.FREE_MB*100/a.TOTAL_MB <$DELVALUE AND a.name like '%FRA%';
EXIT;
EOF
}

Getdata_after()
{
sqlplus -S / as sysdba << EOF 
SET pagesize 0 feedback off heading off echo off
SELECT name||','||total_mb||','||free_mb||','||round(free_mb*100/total_mb,2) FROM v\$asm_diskgroup WHERE  name='$franame';
QUIT;
EOF
}

for line in `ps -ef|grep pmon|grep -v ASM|grep -v grep|awk '{print $8}'|awk -F_ '{print $3}'`
do
  vinstancename=`echo $line`
  export ORACLE_SID=$vinstancename
  echo vinstancename: $vinstancename >>$LOG
  echo  "`Getdata_before`" > $ADMIN_HOME/log/$ARGV-needcleanup.log

if  [ -n "`cat $ADMIN_HOME/log/$ARGV-needcleanup.log | grep "ORA-"`" ] || [ -n "`cat $ADMIN_HOME/log/$ARGV-needcleanup.log | grep "ERROR"`" ] ;then
   echo "Error: Failed to check FRA storage utilization " >>$LOG
   cat $ADMIN_HOME/log/$ARGV-needcleanup.log >>$LOG
   mailx -s "ERROR: Failed to check FRA storage utilization from $vhostname"  "$ERRORMAILLIST" < $LOG
   exit 0
fi

if [ `cat $ADMIN_HOME/log/$ARGV-needcleanup.log | sed '/^$/d' |wc -l` -eq "1" ] ;then
     franame=`cat $ADMIN_HOME/log/$ARGV-needcleanup.log  |awk -F, '{print $1}'`
     totalsize=`cat $ADMIN_HOME/log/$ARGV-needcleanup.log |awk -F, '{print $2}'`
     freesize_bc=`cat $ADMIN_HOME/log/$ARGV-needcleanup.log |awk -F, '{print $3}'`
     Left_PCTbc=`cat $ADMIN_HOME/log/$ARGV-needcleanup.log |awk -F, '{print $4}'`

      dbname=`echo $vinstancename | cut -c 1-$(expr ${#vinstancename} - 1)`
      
      cat $ADMIN_HOME/log/$ARGV-needcleanup.log >>$LOG
      echo "rman target / catalog $dbname/rman@$CATALOGDB" >>$LOG
	    echo `date`": clean up FRA storage for ORACLE_SID - $ORACLE_SID" >>$LOG 

     if [ "$CATALOGDB" != "local" ] ;then
        autocleanup
        ret=$?
        if [ "$ret" = "101"  ] ;then  
           logbackuped=Y
        fi 
     else   
        echo  "`autocleanup_force`" > $ADMIN_HOME/log/$ARGV-autocleanup.log
     fi

      if [ -n "`cat $ADMIN_HOME/log/$ARGV-autocleanup.log | grep "Deleted.*objects"`" ] ;then
      echo  "`Getdata_after`" > $ADMIN_HOME/log/$ARGV-after.log      
         if [ -n "`cat $ADMIN_HOME/log/$ARGV-after.log | grep "ORA-"`" ] || [ -n "`cat $ADMIN_HOME/log/$ARGV-after.log | grep "ERROR"`" ] ;then
            echo "Error: Failed to check archive utilization after clean up action" >>$LOG
            cat $ADMIN_HOME/log/$ARGV-after.log >>$LOG
            mailx -s "ERROR: Failed to check FRA utilization by automated tool from $vhostname"  "$ERRORMAILLIST" < $ADMIN_HOME/log/$ARGV-after.log
            exit 0
         elif [ `cat $ADMIN_HOME/log/$ARGV-after.log | sed '/^$/d' |wc -l` -eq "1" ] ;then            
            freesize_ac=`cat $ADMIN_HOME/log/$ARGV-after.log |awk -F"," '{print $3}'`
            Left_PCTac=`cat $ADMIN_HOME/log/$ARGV-after.log |awk -F"," '{print $4}'`
            senddata=Y
            mailx -s "Auto Archive clean up job finished - $vhostname "  $MAILLIST < $LOG       
         else
            echo "Error: Failed to check archive utilization after clean up action since return records more than one" >>$LOG
            cat $ADMIN_HOME/log/$ARGV-after.log >>$LOG
            mailx -s "ERROR: Failed to check FRA utilization by automated tool from $vhostname"  "$ERRORMAILLIST" < $ADMIN_HOME/log/$ARGV-after.log
            exit 0           
         fi  
     else 
       if [ $needbackup != "Y" ] ;then
           logbackuped=N
           cat $ADMIN_HOME/log/$ARGV-autocleanup.log >>$LOG
           mailx -s "Warning: NO backuped Archive logs cleaned up - $vhostname "  $MAILLIST < $ADMIN_HOME/log/$ARGV-autocleanup.log
           echo "Warning: NO backuped Archive logs cleaned up, then try sysdate - 1/0.875/0.75/0.625 to clean up without backup " >>$LOG
           echo  "`autocleanup_force`" > $ADMIN_HOME/log/$ARGV-autocleanupnobackup.log    	
           if [ -z "`cat $ADMIN_HOME/log/$ARGV-autocleanupnobackup.log | grep "Deleted.*objects"`" ] ;then 
              mailx -s "ERROR: Failed to clean up FRA by force to sysdate-1 from $vhostname"  "$ERRORMAILLIST" < $ADMIN_HOME/log/$ARGV-autocleanupnobackup.log     
              echo  "`autocleanup_force21H`" > $ADMIN_HOME/log/$ARGV-autocleanupnobackup21H.log 
              if [ -z "`cat $ADMIN_HOME/log/$ARGV-autocleanupnobackup21H.log | grep "Deleted.*objects"`" ] ;then 
                 mailx -s "ERROR: Failed to clean up FRA by force to sysdate-0.825 from $vhostname"  "$ERRORMAILLIST" < $ADMIN_HOME/log/$ARGV-autocleanupnobackup21H.log     
                 echo  "`autocleanup_force18H`" > $ADMIN_HOME/log/$ARGV-autocleanupnobackup18H.log                   	
                 if [ -z "`cat $ADMIN_HOME/log/$ARGV-autocleanupnobackup18H.log | grep "Deleted.*objects"`" ] ;then 
                    mailx -s "ERROR: Failed to clean up FRA by force to sysdate-0.7 from $vhostname"  "$ERRORMAILLIST" < $ADMIN_HOME/log/$ARGV-autocleanupnobackup18H.log     
                    echo  "`autocleanup_force15H`" > $ADMIN_HOME/log/$ARGV-autocleanupnobackup15H.log                     
                    if [ -z "`cat $ADMIN_HOME/log/$ARGV-autocleanupnobackup15H.log | grep "Deleted.*objects"`" ] ;then
                       mailx -s "ERROR: Failed to clean up FRA by force to sysdate-0.625 from $vhostname"  "$ERRORMAILLIST" < $ADMIN_HOME/log/$ARGV-autocleanupnobackup15H.log
                       exit 0
                    fi    
                 fi
              fi
           fi  
           echo  "`Getdata_after`" > $ADMIN_HOME/log/$ARGV-afterforce.log  
           if [ -n "`cat $ADMIN_HOME/log/$ARGV-afterforce.log | grep "ORA-"`" ] || [ -n "`cat $ADMIN_HOME/log/$ARGV-afterforce.log | grep "ERROR"`" ] ;then
               echo "Error: Failed to check archive utilization after clean up by force" >>$LOG
               cat $ADMIN_HOME/log/$ARGV-afterforce.log >>$LOG
               mailx -s "ERROR: Failed to check FRA utilization by automated tool from $vhostname"  "$ERRORMAILLIST" < $ADMIN_HOME/log/$ARGV-afterforce.log
               exit 0
           elif [ `cat $ADMIN_HOME/log/$ARGV-afterforce.log | sed '/^$/d' |wc -l` -eq "1" ] ;then            
               freesize_ac=`cat $ADMIN_HOME/log/$ARGV-afterforce.log |awk -F"," '{print $3}'`
               Left_PCTac=`cat $ADMIN_HOME/log/$ARGV-afterforce.log |awk -F"," '{print $4}'`
               senddata=Y
               echo "$franame,$vhostname,$totalsize,$freesize_bc,$Left_PCTbc,$freesize_ac,$Left_PCTac,$logbackuped " >>$LOG
               mailx -s "Auto Archive clean up job finished without backup - $vhostname "  $MAILLIST < $ADMIN_HOME/log/$ARGV-autocleanupnobackup.log        
               if [ "$Left_PCTac" -le "$DELVALUE"  ] ;then
                  echo  "`autocleanup_force21H`" >>$LOG
                  mailx -s "Notice - Auto Archive clean up job finished without backup also failed on first run to clean data - $vhostname " $MAILLIST < $LOG
               fi
           else
               echo "Error: Failed to check archive utilization after clean up action since return records more than one" >>$LOG
               cat $ADMIN_HOME/log/$ARGV-afterforce.log >>$LOG
               mailx -s "ERROR: Failed to check FRA utilization by automated tool from $vhostname"  "$ERRORMAILLIST" < $ADMIN_HOME/log/$ARGV-afterforce.log
               exit 0           
           fi                              
       fi  
     fi           
 
   if [ "$senddata" = "Y" ] ;then
	    echo `date`": Write delete log ORACLE_SID - $ORACLE_SID" >>$LOG
      GetOptStatus 
   fi
fi

done

echo `date`": Done" >>$LOG
echo "logs file location: $LOG"
