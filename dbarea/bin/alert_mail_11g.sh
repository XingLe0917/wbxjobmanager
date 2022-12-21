#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
# 
#  MODIFIED     (MM/DD/YY)
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/12/2017 - Add the STAP API calling.
# 
##########################################################################
#
#  alert_mail.sh
#
#     This script is used to check alert log file
#     input:
#      1)   Oracle Service Name
#     output:
#      1)   send email to dba if there is ORA- error msg
#
#
##########################################################################

############################## for STAP API call using.
START_TIME=`date "+%F %T"`
C_ID="$1"
C_STATUS="success"
C_MSG=""

call_stap() {
  END_TIME=`date "+%F %T"`
  
  C_DATA="{\"host\": \"${HOSTNAME}\", \"name\": \"$0\", \"start_time\": \"${START_TIME}\", \"end_time\": \"${END_TIME}\", \"status\": \"${C_STATUS}\", \"msg\": \"${C_MSG}\", \"id\": \"${C_ID}\"}"
  C_OUT=`/u00/app/admin/dbarea/bin/call_stap_api.py "${C_DATA}"`
  
  if [ ${C_OUT} = '{"result":"OKOKOK"}' ]
  then
    echo "==== call STAP API success."
  else
    echo "==== call STAP API fail."
  fi
}
############################## END.


CallPythonPCA()
{
echo "#!/usr/bin/env python
import httplib
HOST = \"stap.webex.com:80\"
API_URL = \"/stap/xmlapi/pca.action?AT=InsertPCAJobData\"
xml_location=\"/tmp/ORALOGPCAXmlReq.xml\"

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
"  > /tmp/ORALOGPythonPCA.py
chmod 755 /tmp/ORALOGPythonPCA.py
python /tmp/ORALOGPythonPCA.py
}


XMLRequest()
{
end=(`echo $1`)
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<stap>
<PCAMonitor tb=\"wbxdboraerrorlog\" username=\"pcaapiuser\" password=\"TaCu#2012\">" >/tmp/ORALOGPCAXmlReq.xml
for i in $(seq 1 $end)
do
echo "<Result>
    <hostname>"$HOST"</hostname>
    <itemname>"`cat /tmp/oraerror.cfg  |sed -n ''$i'p'`"</itemname>
    <itemvalue>"`cat /tmp/oraerror.cfg  |sed -n ''$i'p' |awk -F"ORA-" '{print $2}'|awk '{print $1}' |grep -o "[0-9]\+"`"</itemvalue>
    <instancename>"$instance_name"</instancename>
</Result>" >> /tmp/ORALOGPCAXmlReq.xml
done
echo "</PCAMonitor>
</stap>" >> /tmp/ORALOGPCAXmlReq.xml
chmod 755 /tmp/ORALOGPCAXmlReq.xml
test -f /tmp/ORALOGPCAXmlReq.xml && CallPythonPCA
rm -f /tmp/ORALOGPCAXmlReq.xml
}

GetOptStatus()
{
b=`cat /tmp/oraerror_${ORACLE_SID}.cfg  |wc -l`
XMLRequest "${b}"
}

if [ $# != 1 ]; then
  echo
  echo "Usage: alert_mail.sh ORACLE_SID "
  echo
  exit
fi

. /home/oracle/.bash_profile

HOST=`/bin/uname -n`
MAIL=/bin/mailx
DISTLIST=cwopsdba@cisco.com
# export HOST MAIL DISTLIST

ORACLE_SID=$1
# export ORACLE_SID
NODE_NO=`hostname|awk -F"." '{print $1}' |sed -e "s/^.*\(.\)$/\1/"`
ORA_LOG_NAME=alert_${ORACLE_SID}.log
# export ORA_LOG_NAME
HIST_NAME=alert_${ORACLE_SID}.hist
# export HIST_NAME

rm -f /tmp/oraerror_${ORACLE_SID}.cfg
rm -f /tmp/alert_${ORACLE_SID}.err

cd ${ORACLE_BASE}/diag/rdbms/*/$ORACLE_SID/trace
if [ -f ${ORA_LOG_NAME} ]
then
    mv ${ORA_LOG_NAME} alert_work.log
    cat alert_work.log >> ${HIST_NAME}
    cat alert_work.log |grep -B1 ORA- | grep -vi "$(egrep "ORA-28|ORA-609|ORA-1112|ORA-01403|ORA-06512|ORA-12012|ORA-1142|ORA-3217|ORA-3217|ORA-3136|ORA-3136|ORA-12805|ORA-01555" -B1  alert_work.log )" |grep -B1 ORA- > /tmp/alert_${ORACLE_SID}.err

   #grep -B1 ORA- alert_work.log | grep -v "ORA-279" | grep -v "ORA-308" | grep -v "ORA-1112" | grep -v "ORA-1642" | grep -v "ORA-01403" | grep -v "ORA-06512" | grep -v "ORA-12012" | grep -v "ORA-1142" | grep -v "ORA-3217"| grep -v "ORA-3136" |grep -v "ORA-609"|grep -v "ORA-28" |grep -vi "nt OS err code: 0" > /tmp/alert_${ORACLE_SID}.err
fi

if [ -s /tmp/alert_${ORACLE_SID}.err ]
then
    grep ORA- /tmp/alert_${ORACLE_SID}.err | sed '/^$/d' > /tmp/oraerror_${ORACLE_SID}.cfg
    instance_name=$ORACLE_SID
    GetOptStatus > /tmp/ORAErrorXmlReq_${ORACLE_SID}.log
    if [ `cat /tmp/ORAErrorXmlReq_${ORACLE_SID}.log |wc -l` -ne `cat /tmp/ORAErrorXmlReq_${ORACLE_SID}.log |grep SUCCESS |wc -l` ] ; then
         C_MSG="found ora error for DB instance."
       mailx  -s " ALERT LOG ORA-ERROR  :  ${ORACLE_SID}@${HOST} Database Alert errors " $DISTLIST < /tmp/alert_${ORACLE_SID}.err
      _pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"
    mesg_str="DB-Alert Critical  ALERT LOG ORA-ERROR  : ${ORACLE_SID}@${HOST} Database Alert error "
    mailx -s "$mesg_str " ${_pager_duty}<  /tmp/alert_${ORACLE_SID}.err 
    fi
fi

rm -f /tmp/alert.err
rm -f /tmp/alert_work.log

### ASM   Alert  log
cd ${ORACLE_BASE}/diag/*/*/*/trace
# NODE_NO=`hostname|awk -F"." '{print $1}' |sed -e "s/^.*\(.\)$/\1/"`
ORA_LOG_NAME=alert_+ASM${NODE_NO}.log
HIST_NAME=alert_+ASM${NODE_NO}.hist
# export HIST_NAME

if [ -f ${ORA_LOG_NAME} ]
then
    mv ${ORA_LOG_NAME} alert_work.log
    cat alert_work.log >> ${HIST_NAME}
    grep -B1 ORA- alert_work.log | grep -v "ORA-279" | grep -v "ORA-308" | grep -v "ORA-1112" | grep -v "ORA-1642" | grep -v "ORA-01403" | grep -v "ORA-06512" | grep -v "ORA-12012" | grep -v "ORA-1142" | grep -v "ORA-3217" > /tmp/alert.err
fi

if [ -s /tmp/alert_${ORACLE_SID}.err ]
then
    grep ORA- /tmp/alert_${ORACLE_SID}.err |sed '/^$/d' > /tmp/oraerror_${ORACLE_SID}.cfg 
    instance_name=ASM${NODE_NO}
    GetOptStatus > /tmp/ORAErrorXmlReq_${ORACLE_SID}.log
    if [ `cat /tmp/ORAErrorXmlReq_${ORACLE_SID}.log |wc -l` -ne `cat /tmp/ORAErrorXmlReq_${ORACLE_SID}.log |grep SUCCESS |wc -l` ] ; then
         C_MSG=${C_MSG}" found ora error for ASM instance."
       mailx  -s " ALERT LOG ORA-ERROR  :  +ASM${NODE_NO}@${HOST} Database Alert errors " $DISTLIST < /tmp/alert_${ORACLE_SID}.err
    fi
fi

rm -f /tmp/alert_${ORACLE_SID}.err
rm -f /tmp/alert_work_${ORACLE_SID}.log
rm -f /tmp/oraerror_${ORACLE_SID}.cfg

##########################################################################
# call STAP API.
##########################################################################
call_stap

