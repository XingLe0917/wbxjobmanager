#!/bin/bash

source /staging/gates/bash_common.sh
. /home/oracle/.bash_profile

killsession()
{
    host_name="${1}"
    spid="${2}"
    printmsg "kill -9 ${spid} on ${host_name}"
    ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey ${host_name} kill -9 ${spid}
}


##########################Main###################
#if [ $# -lt 1 ]; then
#cat << EOF
#sh $0 <DB_NAME>w
#<DB_NAME>:
#For example:
#sh $0 RACAAWEB
#EOF
#exit
#fi
MAILTO="cwopsdba@cisco.com"
localhostname=`hostname -s`
curuser=`whoami`
if [ "${curuser}" != "oracle" ]; then
    echo "Current user ${curuser} is not oracle. EXIT"
    exit
fi
if [ $# -ne 1 ]; then
    SID_LIST=`getmonitoreddblist "${localhostname}" "WEB"`
#    SID_LIST=`ps aux | grep ora_smon | grep -v grep | awk '{print $NF}' | awk -F '_' '{print $NF}' | grep -i -E "RACBTW2|WEB"`
else
    SID_LIST=`ps aux | grep -i "ora_smon_$1" | grep -v grep | awk '{print $NF}' | awk -F '_' '{print $NF}'`
    if [ -z ${SID_LIST} ]; then
        echo "The ORACLE_SID $1 is not running on this server."
        exit 1
    fi
fi

for localsid in ${SID_LIST[@]}
do
	emailcontent=""
	DB_NAME=$(echo "${localsid}" | sed "s/.$//")
    logfilename=`getlogfilenamemonthly "kill_block_session_${DB_NAME}"`
    printmsg "#######start on ${DB_NAME} at `date +%Y%m%d%H%M%S`"

TMOUT=60
export TMOUT

maillogfile="/tmp/block_session_mail_${localsid}.log"
if [ -f ${maillogfile} ]; then
    cat /dev/null > ${maillogfile}
else
    touch ${maillogfile}
fi
echo "To: ${MAILTO}" > ${maillogfile}
echo "From: dbamonitortool@cisco.com" >> ${maillogfile}
echo "Content-Type: text/html; charset='utf-8'" >> ${maillogfile}
echo "Subject: Block Sessions are found on ${localhostname} database ${DB_NAME}" >> ${maillogfile}

nodes=`olsnodes`
for node in ${nodes[@]}
do
    lres=`ssh -o ConnectTimeout=60 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey ${node} date | grep -i permission`
    if [ "x${lres}" != "x" ]; then
        echo "Current server ${localhostname} can not login to remote server ${node} by public key" >> ${maillogfile}
        echo "Please double check manually" >> ${maillogfile}
        sendmail -t < ${maillogfile}
        exit
    fi
done

checkdbenvparameter
if [ $? -ne 0 ]; then
    exit
fi
printmsg "WBXINFO: localsid=${localsid}"
export ORACLE_SID=${localsid}

curpid=$$
isexist=`ps -ef | grep -v grep | grep kill_block_session_one_node | grep -v ${curpid} | grep -i ${DB_NAME} | wc -l`
if [ $isexist -gt 0 ]; then
    printmsg "WBXINFO: the same program is running. EXIT"
    exit
fi

export ORACLE_SID=${localsid}
SQL="select decode(t.REQUEST, 0, 'Holder', 'Waiter') || '?' ||t.INST_ID||'?' ||inst.host_name||'?'||p.SPID||'?'||v.sid||'?'||v.serial#||'?'||t.CTIME|| '?' ||v.STATUS|| '?' ||v.OSUSER|| '?' ||v.USERNAME||'?'||v.PROGRAM||'?'||v.event||'?'||v.machine||'?'||v.SQL_ID||'?'||v.sql_child_number||'?'||v.sql_hash_value||'?'||t.LMODE||'?'||t.id1||'?'||t.id2||'?'||t.type
from gv\$lock t,gv\$session v, gv\$process p, gv\$instance inst
where (t.id1, t.id2, t.TYPE) in (select id1, id2, type from gv\$lock where request > 0)
and v.TYPE<>'BACKGROUND'
and v.INST_ID=t.INST_ID
and t.SID=v.SID
and p.addr = v.paddr
and p.INST_ID=v.INST_ID
and t.ctime > 2* 60
and t.inst_id=inst.inst_id
order by id1, request;
"

vsessions=`$ORACLE_HOME/bin/sqlplus -S "/ as sysdba" << EOF | sed "s/[[:space:]]/#/g"
SET pagesize 0 linesize 1000 feedback off heading off echo off serveroutput on
${SQL}
QUIT;
EOF
`
    haserror=`echo ${vsessions} | grep "ORA-" | grep "ERROR" | wc -l`
    printmsg "${inst_id} ${vsessions}"
    if [ ${haserror} -gt 0 ]; then
        exit
    fi
	
	sessioncontent=""
	
    for session in ${vsessions[@]}
    do
        isholder=`echo ${session} | awk -F? '{print $1}'`
        inst_id=`echo ${session} | awk -F? '{print $2}'`
        host_name=`echo ${session} | awk -F? '{print $3}'`
        spid=`echo ${session} | awk -F? '{print $4}'`
        sid=`echo ${session} | awk -F? '{print $5}'`
        serial=`echo ${session} | awk -F? '{print $6}'`
        ctime=`echo ${session} | awk -F? '{print $7}'`
        vstatus=`echo ${session} | awk -F? '{print $8}'`
        osuser=`echo ${session} | awk -F? '{print $9}'`
        username=`echo ${session} | awk -F? '{print $10}'`
        program=`echo ${session} | awk -F? '{print $11}' | sed "s/#/ /g"`
        vevent=`echo ${session} | awk -F? '{print $12}' | sed "s/#/ /g"`
        vmachine=`echo ${session} | awk -F? '{print $13}' | sed "s/#/ /g"`
        sql_id=`echo ${session} | awk -F? '{print $14}'`
        sql_child_number=`echo ${session} | awk -F? '{print $15}'`
        sql_hash_value=`echo ${session} | awk -F? '{print $16}'`
        lmode=`echo ${session} | awk -F? '{print $17}'`
        lid1=`echo ${session} | awk -F? '{print $18}'`
        lid2=`echo ${session} | awk -F? '{print $19}'`
        ltype=`echo ${session} | awk -F? '{print $20}'`
		iskilled="NO"

        if [ "${isholder}" == "Holder" ]; then
            if [ "${username}" == "TEST" ]; then
                killsession "${host_name}" "${spid}"
				iskilled="YES"
            fi
        fi
        bindval=""
        if [ "x${sql_id}" != "x" ]; then
            SQL="select listagg(tb.name||'='||tb.value_string,',') within group (order by position)
from v\$sql ta, v\$sql_bind_capture tb
where ta.sql_id='${sql_id}'
and ta.child_number=${sql_child_number}
and ta.hash_value=${sql_hash_value}
and ta.sql_id=tb.sql_id
and ta.hash_value=tb.hash_value
and ta.child_address=tb.child_address;"
            bindval=`execSQLASDBA "${SQL}"`
        fi
        emailcontent="${emailcontent}<tr><td>${isholder}</td><td>${inst_id}</td><td>${spid}</td><td>${sid}</td>
                      <td>${serial}</td><td>${ctime}</td><td>${vstatus}</td><td>${iskilled}</td>
                      <td>${osuser}</td><td>${username}</td><td>${program}</td><td>${vevent}</td><td>${vmachine}</td><td>${sql_id}</td>
                      <td>${lid1}</td><td>${ltype}</td><td>${bindval}</td></tr>"
        if [ "x${sql_id}" != "x" ]; then
            if [ `echo "${SQLCONTENT}" | grep "<td>${sql_id}</td>" | wc -l` -eq 0 ]; then
                SQLTEXT="select sql_fulltext from v\$sqlarea where sql_id='${sql_id}';"
vsqlfulltext=`sqlplus -S "/ as sysdba" << EOF
SET pagesize 0 linesize 1000 feedback off heading off echo off serveroutput on long 10000
${SQLTEXT}
QUIT;
EOF
`
                SQLCONTENT="${SQLCONTENT}<tr><td>${sql_id}</td><td>${vsqlfulltext}</td></tr>"
            fi
        fi
    done

if [ "x${emailcontent}" != "x" ]; then
    echo "Blocked sessions are found, the detailed info is as below<br>" >> ${maillogfile}
    echo "The lock holder session under TEST user will be killed automatically. " >> ${maillogfile}
    echo "<table border=\"1px\"><tr><td>Session Role</td><td>inst_id</td><td>spid</td><td>sid</td><td>serial#</td><td>block time</td><td>status</td><td>iskilled</td><td>osuser</td><td>Schema name</td><td>Program</td><td>Event</td><td>Machine</td><td>SQL_ID</td><td>LOCK_ID1</td><td>LOCK_TYPE</td><td>BIND_VALUE</td></tr>${emailcontent}</table>" >> ${maillogfile}
    echo -e "\n\n\n<br>" >> ${maillogfile}
    echo "Below is the SQL list that lock holder and waiter sessioin are running:" >> ${maillogfile}
    echo "<table border=\"1px\"><tr><td>SQL_ID</td><td>SQL_TEXT</td></tr>${SQLCONTENT}</table>" >> ${maillogfile}
	echo -e "\n\n\n<br><br>" >> ${maillogfile}
	echo "You can get detailed instruction about this tool from wiki: https://wiki.cisco.com/display/PRODDBA/Kill+Block+Session+in+DB" >> ${maillogfile}
    sendmail -t < ${maillogfile}
else
    printmsg "No lock found"
fi
done
printmsg "#######end at `date +%Y%m%d%H%M%S`"
