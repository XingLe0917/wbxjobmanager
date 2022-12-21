#!/bin/bash

CallPythonDSK()
{
echo "#!/usr/bin/env python
import httplib

HOST = \"stap.webex.com:80\"
API_URL = \"/stap/xmlapi/pca.action?AT=InsertPCAJobData\"
xml_location=\"/tmp/DSKXmlReq.xml\"

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
"  > /tmp/PythonDSK.py
chmod 755 /tmp/PythonDSK.py
python /tmp/PythonDSK.py
}

XMLRequest() 
{
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<stap>
<PCAMonitor tb=\"stap_dbadiskusage\" username=\"pcaapiuser\" password=\"TaCu#2012\">" > /tmp/DSKXmlReq.xml
echo "<Result>
    <hostname>"`hostname`"</hostname>
    <mountpoint>"${1}"</mountpoint>	
    <usedpct>"${2}%"</usedpct>
    <availsize>"${3}"</availsize> 
    <audittime>"`date`"</audittime>   
</Result>" >> /tmp/DSKXmlReq.xml
echo "</PCAMonitor>
</stap>" >> /tmp/DSKXmlReq.xml
chmod 755 /tmp/DSKXmlReq.xml
test -f /tmp/DSKXmlReq.xml && CallPythonDSK
rm -f /tmp/DSKXmlReq.xml /tmp/PythonDSK.py
}

export _DF=`echo /tmp/df_$$.txt`
export _TMP_EMAIL=`echo /tmp/tmp_email_$$.txt`
export _EMAIL=`echo /tmp/email_$$.txt`
export _THRESHOLD=90

cat /dev/null > ${_DF}

# get the unix file system mount point information
#df -H | grep '%' | grep -vE 'Filesystem|tmpfs' | grep -v "^ " | awk '{ print $4 " " $5 " " $6 }' > ${_DF}

# get the shared (dd) mount point information and append it to the file
df -H | grep '%' | grep -vE 'Filesystem|tmpfs' | grep "^ " | grep -E  'image|retain'  |awk '{ print $3 " " $4 " " $5 }'    > ${_DF}

#cat ${_DF}

cat /dev/null > ${_TMP_EMAIL}
cat /dev/null > ${_EMAIL}
_MAIL_SUB=

while read output
do
#echo $output
  usep=$(echo $output | awk '{ print $2}' | cut -d'%' -f1  )
  partition=$(echo $output | awk '{ print $3 }' )
avail=`echo $output |awk '{print $1}'`
#echo "usep = ${usep}"
#echo "partition = ${partition}"
  if [ $usep -ge ${_THRESHOLD} ]; then
       echo "`date`:$(hostname):$partition ($usep%): Available ($avail)" >> ${_TMP_EMAIL}
       XMLRequest $partition $usep $avail >>/tmp/DSKXmlReq.log 
	if [ $partition = "/sjrac_rman_vol" -o $partition = "/sjcon_rman_vol" -o $partition = "/sjracrpt_rman_vol" ]; then
echo "" >> ${_TMP_EMAIL}
echo "Deleting backup files older than 2 days" >> ${_TMP_EMAIL}
echo "" >> ${_TMP_EMAIL}
/opt/emc/scripts/clean.sh
echo "Deleted old backup files" >> ${_TMP_EMAIL}
echo "" >> ${_TMP_EMAIL}
fi
       _MAIL_SUB=`echo "${_MAIL_SUB} $partition ($usep%): Available ($avail)"`
  fi
done < ${_DF}

# send an email if the temp_email file has a size greater than 0 bytes.
if [ -s ${_TMP_EMAIL} ]
then
  #cat ${_TMP_EMAIL}
  cat /dev/null > ${_EMAIL}
  echo "Hi," >> ${_EMAIL}
  echo ""  >> ${_EMAIL}
  echo "The below file system(s) are running out of space. Please investigate."  >> ${_EMAIL}
  echo ""  >> ${_EMAIL}
  cat ${_TMP_EMAIL} >> ${_EMAIL}
  echo ""  >> ${_EMAIL}
  echo "Thanks,"  >> ${_EMAIL}
  echo "DBA Team"  >> ${_EMAIL}
  echo ""  >> ${_EMAIL}

  cat ${_EMAIL}
  if [ `cat /tmp/DSKXmlReq.log |wc -l` -ne `cat /tmp/DSKXmlReq.log |grep SUCCESS |wc -l` ] ; then 
     mail -s "Urgent: DD Backup -  Almost out of disk space on $(hostname). ${_MAIL_SUB} " cwopsdba@cisco.com < ${_EMAIL}
  fi
  rm -f /tmp/DSKXmlReq.log
fi

