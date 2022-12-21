#!/bin/sh

##########################################################################
#
#  Checking Logic
#    1. The SP_OCT_DENIED_USERID is set or not in the file "paramdb".
#    2. Check out the userid for SPLEX_DENY from the DB.
#    3. Send out alert if not match.
#
#
#  MODIFIED     (MM/DD/YYYY)
#    Edwin       05/24/2021 - Check the data in paramdb file.
#    Edwin       04/28/2021 - Move ahead for the export ENV statement.
#    Edwin       04/27/2021 - Remove the send mail.
#    Edwin       03/30/2021 - Send log to depot DB.
#    Edwin       03/16/2021 - Change to use sp_ctrl to get real DB.
#    Edwin       03/04/2021 - Add logic to handle configdb and its GSB.
#    Edwin       03/01/2021 - Created.
#
##########################################################################

if [ "$USER" != "oracle" ]; then
    echo "== Please run this audit under oracle user."
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "== Usage: $0 splex_port_number "
    echo "For example : $0 19001 "
    exit 1
fi

if ! [ "$1" -gt 0 ] 2>/dev/null
then
  echo "==== The input parameter $1 is not a number, exit."
  exit 1
fi

SPLEX_PORT=$1

# MAIL_LIST="cwopsdba@cisco.com"
MAIN_LOG=/tmp/splex_deny_monitor_4_${SPLEX_PORT}.log
NODE_NAME=`hostname -s`


## variables we using.
CK_STAT="N" # for depot log info using, Y is OK.
MSG=""      # for depot log info using.
FLAG_OK="Y" # Process using.
PID_CAPTURE=""
SP_PRODDIR=""
SP_VARDIR=""
SP_HOST=""
SP_ORA_HOME=""

CAPTURE_SID=""
TNSPING_SID=""
USERID_SPCTRL=""
USERID_DB=""
DENY_NAME="SPLEX_DENY" # default value, and for configdb, we use splex33333 as deny user.

get_pid() {

    PID_CAPTURE=`ps -eaf | grep sp_ocap | grep "${SPLEX_PORT}$" | tr -s " " | cut -d " " -f2`

    if [ "X${PID_CAPTURE}" = 'X' ]
    then
        echo "== " >> ${MAIN_LOG}
        echo "==  *** The capture process of port ${SPLEX_PORT} is not running." >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="capture process of port ${SPLEX_PORT} is not running"
    else
        if ! [ "${PID_CAPTURE}" -gt 0 ] 2>/dev/null
        then
            echo "== " >> ${MAIN_LOG}
            echo "==  *** The capture PID (${PID_CAPTURE}) we got is not a number." >> ${MAIN_LOG}
            FLAG_OK="N"
            MSG="capture PID (${PID_CAPTURE}) we got is not a number"
        fi
    fi

}

get_env_var() {

    ENV_VARS_FILE=/tmp/env_variables_4_${PID_CAPTURE}.log
    xargs --null --max-args=1 < /proc/${PID_CAPTURE}/environ > ${ENV_VARS_FILE}
    SP_VARDIR=`grep "^SP_SYS_VARDIR" ${ENV_VARS_FILE} | cut -d '=' -f 2`
    SP_HOST=`grep "^SP_SYS_HOST_NAME" ${ENV_VARS_FILE} | cut -d '=' -f 2`
    SP_PRODDIR=`grep "^SP_SYS_PRODDIR" ${ENV_VARS_FILE} | cut -d '=' -f 2`
    SP_ORA_HOME=`grep "^ORACLE_HOME" ${ENV_VARS_FILE} | cut -d '=' -f 2`

    if [ "X${SP_VARDIR}" = 'X' ]
    then
        echo "==  *** The SP_SYS_VARDIR of ${SPLEX_PORT} not found." >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="SP_SYS_VARDIR of ${SPLEX_PORT} not found"
    fi

    if [ "X${SP_HOST}" = 'X' ]
    then
        echo "==  *** The SP_SYS_HOST_NAME of ${SPLEX_PORT} not found." >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="SP_SYS_HOST_NAME of ${SPLEX_PORT} not found"
    fi

    if [ "X${SP_PRODDIR}" = 'X' ]
    then
        echo "==  *** The SP_SYS_PRODDIR of ${SPLEX_PORT} not found." >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="SP_SYS_PRODDIR of ${SPLEX_PORT} not found"
    fi

    if [ "X${SP_ORA_HOME}" = 'X' ]
    then
        echo "==  *** The ORACLE_HOME of ${SPLEX_PORT} not found." >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="ORACLE_HOME of ${SPLEX_PORT} not found"
    else
        export ORACLE_HOME=${SP_ORA_HOME}
        export PATH=$PATH:${ORACLE_HOME}/bin
    fi

}

get_userid_sp_ctrl() {
    SP_CTRL_OUT_FILE=/tmp/sp_ctrl_output_4_${PID_CAPTURE}.log

    export SP_COP_TPORT=${SPLEX_PORT}
    export SP_COP_TPORT=${SPLEX_PORT}
    export SP_SYS_VARDIR=${SP_VARDIR}

    export SP_SYS_HOST_NAME=${SP_HOST}
    export SP_SYS_PRODDIR=${SP_PRODDIR}

    cd ${SP_PRODDIR}/bin
    ./sp_ctrl <<EOF > ${SP_CTRL_OUT_FILE}
show
list param capture
EOF

    CAPTURE_SID=`grep "^Capture" ${SP_CTRL_OUT_FILE} | tr -s " " | cut -d " " -f2 | grep "^o." | awk -F "." {'print $2'}`
    USERID_SPCTRL=`grep "^SP_OCT_DENIED_USERID" ${SP_CTRL_OUT_FILE} | tr -s " " | cut -d " " -f2`

    if [ "X${CAPTURE_SID}" = 'X' ]
    then
        echo "==  *** The capture SID of ${SPLEX_PORT} not found." >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="capture SID of ${SPLEX_PORT} not found"
    fi

    if [ "X${USERID_SPCTRL}" = 'X' ]
    then
        echo "==  *** The SP_OCT_DENIED_USERID of ${SPLEX_PORT} not found." >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="SP_OCT_DENIED_USERID of ${SPLEX_PORT} not found"
    fi

    if ! [ "${USERID_SPCTRL}" -gt 0 ] 2>/dev/null
    then
        echo "== " >> ${MAIN_LOG}
        echo "==  *** The SP_OCT_DENIED_USERID we got (${USERID_SPCTRL}) from sp_ctrl is not a number." >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="SP_OCT_DENIED_USERID we got (${USERID_SPCTRL}) from sp_ctrl is not a number"
    fi

}

check_userid_in_paramdb() {
    SP_PARAM_FILE="${SP_VARDIR}/data/paramdb"
    _cnt=`grep "^SP_OCT_DENIED_USERID" ${SP_PARAM_FILE} | grep -wc "\"${USERID_SPCTRL}\""`

    if [ "${_cnt}" -ne 1 ]
    then
        echo "==  *** The SP_OCT_DENIED_USERID of ${SPLEX_PORT} not correct in file: ${SP_PARAM_FILE}" >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="SP_OCT_DENIED_USERID of ${SPLEX_PORT} not correct in file: ${SP_PARAM_FILE}"
    fi
}

get_tns_sid() {
    TNSPING_SID=`tnsping ${CAPTURE_SID} | grep -i INSTANCE_NAME | awk {'print $NF'} | sed 's/)//g'`

    if [ "X${TNSPING_SID}" = 'X' ]
    then
        echo "==  *** The INSTANCE_NAME not found using tnsping of TNS: ${CAPTURE_SID}" >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="TNS entry of ${CAPTURE_SID} not correct."
    else
        TMP_CNT=`ps -aef | grep -v "grep " | grep -wc ora_smon_${TNSPING_SID}`

        if [ ${TMP_CNT} -ne 1 ]
        then
            echo "==  *** The SID: ${TNSPING_SID} not running at this server." >> ${MAIN_LOG}
            FLAG_OK="N"
            MSG="SID of ${TNSPING_SID} not found"
        fi
    fi

}

get_userid_db() {

    SQL_OUTPUT_FILE=/tmp/sql_output_4_${PID_CAPTURE}.log

    if [ ${SPLEX_PORT} -ne 33333 ]; then
        if echo "CFGDB_SPLEX GCFGDB_SPLEX CONFIGDB_SPLEX BGCFGDB_SPLEX" | grep -iwc "${CAPTURE_SID}" &>/dev/null; then
            DENY_NAME="SPLEX33333"
        fi
    fi

    export ORACLE_SID=${TNSPING_SID}

    echo "select 'USER_ID='||user_id from dba_users where username = '${DENY_NAME}';" | sqlplus -s "/as sysdba" > ${SQL_OUTPUT_FILE}

    USERID_DB=`grep "^USER_ID" ${SQL_OUTPUT_FILE} | cut -d '=' -f 2`

    if [ "X${USERID_DB}" = 'X' ]
    then
        echo "== " >> ${MAIN_LOG}
        echo "==  *** The user ${DENY_NAME} not found in DB instance ${ORACLE_SID}." >> ${MAIN_LOG}
        FLAG_OK="N"
        MSG="user ${DENY_NAME} not found in DB instance ${ORACLE_SID}"
    else
        if ! [ "${USERID_DB}" -gt 0 ] 2>/dev/null
        then
            echo "== " >> ${MAIN_LOG}
            echo "==  *** The USER_ID of ${DENY_NAME} user in DB (${USERID_DB}) is not a number." >> ${MAIN_LOG}
            FLAG_OK="N"
            MSG="USER_ID of ${DENY_NAME} user in DB (${USERID_DB}) is not a number"
        fi
    fi

}

write_depot() {
    SQL_DEPOT_OUTPUT_FILE=/tmp/sql_write_depot_4_${SPLEX_PORT}.log

    DB_PASS=`echo "U2FsdGVkX19XYDUWHI0yxAnRKvCdbQ==" | openssl enc -aes-256-cfb -d -base64 -k SJDBGRIDCTRL`
    DB_TNS="sjdbormt020a-scan:1701/auditdb.webex.com"

    sqlplus -S depot/${DB_PASS}@${DB_TNS} <<EOF > ${SQL_DEPOT_OUTPUT_FILE}
delete from SP_OCT_DENIED_USERID_LOG where host_name = '${NODE_NAME}' and port_number = '${SPLEX_PORT}';
insert into SP_OCT_DENIED_USERID_LOG(host_name, port_number, check_stat, user_name, userid_db, userid_sp, comments)
values('${NODE_NAME}', '${SPLEX_PORT}', '${CK_STAT}', '${DENY_NAME}', '${USERID_DB}', '${USERID_SPCTRL}', '${MSG}');
commit;
EOF

}

echo "====================================== " > ${MAIN_LOG}
echo "== " >> ${MAIN_LOG}
echo "== `date "+%F %T"` *** Start *** " >> ${MAIN_LOG}

#------------------------------------------------------------------------------
# 1. get PID of capture process.
#------------------------------------------------------------------------------
get_pid

#------------------------------------------------------------------------------
# 2. get environment variables.
#------------------------------------------------------------------------------
if [ ${FLAG_OK} = "Y" ]
then
    echo "== " >> ${MAIN_LOG}
    echo "== Get the PID of the capture process is ${PID_CAPTURE} " >> ${MAIN_LOG}

    get_env_var

fi

#------------------------------------------------------------------------------
# 3. get parameter from file.
#------------------------------------------------------------------------------
if [ ${FLAG_OK} = "Y" ]
then
    echo "== " >> ${MAIN_LOG}
    echo "== Get the envionment variables for capture process as below: " >> ${MAIN_LOG}
    echo "== The SP_SYS_VARDIR is: ${SP_VARDIR} " >> ${MAIN_LOG}
    echo "== The SP_SYS_PRODDIR is: ${SP_PRODDIR} " >> ${MAIN_LOG}
    echo "== The SP_SYS_HOST_NAME is: ${SP_HOST} " >> ${MAIN_LOG}
    echo "== The ORACLE_HOME is: ${SP_ORA_HOME} " >> ${MAIN_LOG}

    get_userid_sp_ctrl

fi

if [ ${FLAG_OK} = "Y" ]
then
    echo "== " >> ${MAIN_LOG}
    echo "== Get the SP_OCT_DENIED_USERID within sp_ctrl is: ${USERID_SPCTRL} " >> ${MAIN_LOG}

    check_userid_in_paramdb

fi

#------------------------------------------------------------------------------
# 4. get the running SID on this server basis on the CAPTURE SID, using tnsping.
#------------------------------------------------------------------------------
if [ ${FLAG_OK} = "Y" ]
then

    echo "== " >> ${MAIN_LOG}
    echo "== Get the CAPTURE SID within sp_ctrl is: ${CAPTURE_SID} " >> ${MAIN_LOG}

    get_tns_sid

fi

#------------------------------------------------------------------------------
# 5. get USERID fron DB.
#------------------------------------------------------------------------------
if [ ${FLAG_OK} = "Y" ]
then

    echo "== " >> ${MAIN_LOG}
    echo "== Get the runngin SID is: ${TNSPING_SID} " >> ${MAIN_LOG}

    get_userid_db

fi

#------------------------------------------------------------------------------
# 6. Check the ID is same or NOT.
#------------------------------------------------------------------------------
if [ ${FLAG_OK} = "Y" ]
then

    echo "== " >> ${MAIN_LOG}
    echo "== Get the USER_ID of ${DENY_NAME} user in DB is: ${USERID_DB} " >> ${MAIN_LOG}

    echo "== " >> ${MAIN_LOG}
    if [ ${USERID_DB} -eq ${USERID_SPCTRL} ]
    then
        echo "== The ${DENY_NAME} in DB and SP_OCT_DENIED_USERID within sp_ctrl are same." >> ${MAIN_LOG}
        CK_STAT="Y"
    else
        echo "== The ${DENY_NAME} in DB is ${USERID_DB} and SP_OCT_DENIED_USERID within sp_ctrl is ${USERID_SPCTRL}." >> ${MAIN_LOG}
        # mailx -s "Critical Alert: SP_OCT_DENIED_USERID is wrong for port ${SPLEX_PORT} at server ${NODE_NAME} " $MAIL_LIST < ${MAIN_LOG}
    fi

# else
    # mailx -s "Critical Alert: Error while check the SP_OCT_DENIED_USERID for port ${SPLEX_PORT} at server ${NODE_NAME} " $MAIL_LIST  < ${MAIN_LOG}

fi

#------------------------------------------------------------------------------
# 7. Write into depot.
#------------------------------------------------------------------------------
write_depot


echo "== " >> ${MAIN_LOG}
echo "== `date "+%F %T"` *** End ***" >> ${MAIN_LOG}
echo "====================================== " >> ${MAIN_LOG}
echo " " >> ${MAIN_LOG}

exit 0

