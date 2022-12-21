############################################################
#
#    gener_run_asm.sh
#
#     This script is used to run general sql on all scripts
#
#     08/06/07 By Canny Hua
#
############################################################

CallPythonASM()
{
echo "#!/usr/bin/env python
import httplib

HOST = \"stap.webex.com:80\"
API_URL = \"/stap/xmlapi/pca.action?AT=InsertPCAJobData\"
xml_location=\"/tmp/ASMXmlReq.xml\"

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
"  > /tmp/PythonASM.py
chmod 755 /tmp/PythonASM.py
python /tmp/PythonASM.py
}

XMLRequest()
{
asminfo=(`echo $1`)
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<stap>
<PCAMonitor tb=\"stap_dbaasmusage\" username=\"pcaapiuser\" password=\"TaCu#2012\">" > /tmp/ASMXmlReq.xml
for b in ${asminfo[*]}
do
echo "<Result>
    <audittime>"`date`"</audittime>
    <hostname>"`hostname`"</hostname>
    <name>"`echo ${b}|awk -F"," '{print $1}'`"</name>
    <total_mb>"`echo ${b}|awk -F"," '{print $2}'`"</total_mb>
    <free_mb>"`echo ${b}|awk -F"," '{print $3}'`"</free_mb>
    <left_per>"`echo ${b}|awk -F"," '{print $4}'`" </left_per>
</Result>" >> /tmp/ASMXmlReq.xml
done
echo "</PCAMonitor>
</stap>" >> /tmp/ASMXmlReq.xml
chmod 755 /tmp/ASMXmlReq.xml
test -f /tmp/ASMXmlReq.xml && CallPythonASM
rm -f /tmp/ASMXmlReq.xml /tmp/PythonASM.py 
}

. /home/oracle/.asm_profile
help_msg()
{
more <<EOF
Usage:  gener_run.sh xxx (this xxx.sql need under /u00/app/admin/dbarea/sql)
EOF
}

####################################################################
#Main
####################################################################
ARGV=$1
echo $ARGV
MAILLIST="cwopsdba@cisco.com"
#MAILLIST="canny.hua@cisco.com"
rm -rf $ADMIN_HOME/log/$ARGV.lst

if [ "x$ARGV" = "x" ]
then
  help_msg
  exit 0;
else
  if [ ! -f $ADMIN_HOME/sql/$ARGV.sql ]
  then
    help_msg
    exit 0;
  fi
fi

sqlplus -s sys/sysnotallow as sysdba << EOF
@$ADMIN_HOME/sql/$ARGV.sql
spool off;
EOF

mflag=`grep '[1-9]' $ADMIN_HOME/log/$ARGV.lst`
if [ "X$mflag" = 'X' ]
then
  mflag=0
else
  mflag=2
fi

if  [ $mflag -ge "1" ]
then
  if [ `cat $ADMIN_HOME/log/$ARGV.lst |grep "ORA-" |wc -l` -gt 0  ] ; then
     mailx -s "ALERT- the ASM storage alarm " $MAILLIST < $ADMIN_HOME/log/$ARGV.lst
  else
    a=`cat $ADMIN_HOME/log/$ARGV.lst |grep '[1-9]' |awk '{print $1","$2","$3","$4}'`
    XMLRequest "${a}" >/tmp/ASMXmlReq.log
    if [ `cat /tmp/ASMXmlReq.log |wc -l` -ne `cat /tmp/ASMXmlReq.log |grep SUCCESS |wc -l` ] ; then
       mailx -s "ALERT- the ASM storage alarm " $MAILLIST < $ADMIN_HOME/log/$ARGV.lst
    fi
    rm -f /tmp/ASMXmlReq.log
  fi
fi

