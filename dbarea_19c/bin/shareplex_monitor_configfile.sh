#!/bin/bash
source /staging/gates/bash_common.sh

# This script can only be port level or db level for the case that multiple ports are used to replicate one db->db table list
if [ $# -ne 2 ]; then
cat << EOF
sh $0 <DB_NAME> <GRANULARITY>
<GRANULARITY>: the db_name which will be monitored
<METHOD>: FULL/INCREMENTAL
For example:
sh $0 RACFTWEB INCREMENTAL
EOF
exit
fi

GRANULARITY=`echo "$1" | tr '[a-z]' '[A-Z]'`
if [ "${2}" != "FULL" ]; then
    MTMETHOD="INCREMENTAL"
else
    MTMETHOD="FULL"
fi

MAILTO="zhiwliu@cisco.com brzhu@cisco.com"
localhostname=`hostname -s`
curuser=`whoami`
if [ "${curuser}" != "oracle" ]; then
    echo "Current user ${curuser} is not oracle. EXIT"
    exit
fi
logfilename=`getlogfilenamemonthly "shareplex_monitor_configfile"`
printmsg "#######start at `date +%Y%m%d%H%M%S`"
if [ ! -f /etc/oraport ]; then
    printmsg "WBXERROR: /etc/oraport does not exist. WBXEXIT"
    exit
fi
checkdbenvparameter
if [ $? -ne 0 ]; then
    exit
fi

depotDBConnectStr="`getdepotdbconnectinfo`"
if [ "x${depotDBConnectStr}" == "x" ]; then
    printmsg "WBXERROR: can not get DepotDB connection info. EXIT"
    exit
fi

isnumeric "${GRANULARITY}"
if [ $? -eq 0 ]; then
    SPPORT="${GRANULARITY}"
    SQL=" select distinct src_db||','||src_splex_sid||','||port||','||sdi.application_type||','||sdi.appln_support_code
          from shareplex_info si, instance_info sii, database_info sdi, instance_info tii, database_info tdi
          where si.port='${SPPORT}'
          and si.src_db=sii.db_name
          and si.src_host=sii.host_name
          and sii.db_name=sdi.db_name
          and sii.trim_host=sdi.trim_host
          and sdi.db_type in ('PROD','BTS_PROD')
          and si.tgt_db=tii.db_name
          and si.tgt_host=tii.host_name
          and tii.db_name=tdi.db_name
          and tii.trim_host=tdi.trim_host
          and tdi.db_type in ('PROD','BTS_PROD')
          and si.src_host in "
else
    DB_NAME="${GRANULARITY}"
    SQL=" select distinct src_db||','||src_splex_sid||','||port||','||sdi.application_type||','||sdi.appln_support_code
          from shareplex_info si, instance_info sii, database_info sdi, instance_info tii, database_info tdi
          where si.src_db='${DB_NAME}'
          and si.src_db=sii.db_name
          and si.src_host=sii.host_name
          and sii.db_name=sdi.db_name
          and sii.trim_host=sdi.trim_host
          and sdi.db_type in ('PROD','BTS_PROD')
          and si.tgt_db=tii.db_name
          and si.tgt_host=tii.host_name
          and tii.db_name=tdi.db_name
          and tii.trim_host=tdi.trim_host
          and tdi.db_type in ('PROD','BTS_PROD')
          and si.src_host in "
fi
hostinfo=""
nodes=`olsnodes`
for node in ${nodes[@]}
do
    hostinfo="${hostinfo},'${node}'"
done
SQL="${SQL}(${hostinfo:1});"
spports=`execSQL "${depotDBConnectStr}" "${SQL}"`
if [ "x${spports}" == "x" ]; then
    printmsg "WBXERROR: can not get shareplex ports by inputted parameter ${GRANULARITY}. WBXEXIT"
    exit
fi

cur_application_type="PRI"
cur_appln_support_code="WEB"
hasdiff="N"
# Used to handle multiple shareplex bin dir case
DEFAULT_SPLEX_BIN_DIR=""
while read line 
do
    SPLEX_PORT=`echo "${line}" | awk -F: '{print $1}'`
    DEFAULT_SPLEX_BIN_DIR=`echo "${line}" | awk -F: '{print $2}'`
    isnumeric "${SPLEX_PORT}"
    if [ $? -ne 0 ]; then
        continue
    fi
    if [ "x${DEFAULT_SPLEX_BIN_DIR}" != "x" ] && [ ! -d ${DEFAULT_SPLEX_BIN_DIR} ]; then
        continue
    fi
    break
done < /etc/oraport

. /home/oracle/.19c_grid
for spport in ${spports[@]}
do
    echo "${spport}"
    DB_NAME=`echo "${spport}" | awk -F, '{print $1}'`
    src_splex_sid=`echo "${spport}" | awk -F, '{print $2}'`
    SPLEX_PORT=`echo "${spport}" | awk -F, '{print $3}'`
    SP_SERVICE="shareplex${SPLEX_PORT}"
    cur_application_type=`echo "${spport}" | awk -F, '{print $4}'`
    cur_appln_support_code=`echo "${spport}" | awk -F, '{print $5}'`
    
    isonline=`crsstat | grep ${SP_SERVICE} | grep ONLINE | wc -l`
    if [ ${isonline} -eq 0 ]; then
        printmsg "WBXERROR: the shareplex port ${SPLEX_PORT} is not running"
        continue
    fi
    SPLEX_BIN_DIR=`cat /etc/oraport |grep "^${SPLEX_PORT}"|awk -F: '{print $2}'`
    if [ "x${SPLEX_BIN_DIR}" == "x" ]; then
        SPLEX_BIN_DIR="${DEFAULT_SPLEX_BIN_DIR}"
    fi
    PROFILE_PORT="${SPLEX_BIN_DIR}/.profile_u${SPLEX_PORT}"
    if [ ! -f ${PROFILE_PORT} ]; then
        printmsg "WBXERROR: The shareplex port profile ${PROFILE_PORT} does not exist. WBXEXIT"
        exit
    fi
    . ${PROFILE_PORT}
    statusdbfile="${SP_SYS_VARDIR}/data/statusdb"
    if [ ! -f ${statusdbfile} ]; then
        printmsg "WBXERROR: can not get ${statusdbfile} file for port ${SPLEX_PORT}. WBXEXIT"
        exit
    fi
done

localsid=`getlocalsidbydbname ${DB_NAME}`
if [ $? -ne 0 ]; then
    printmsg "${localsid}"
    exit
fi

errormsg=""
schemavers=""

# Store all queried schema release version into an array; 
# when query second time, it get from the array directly, but not need to query db again
getSchemaReleaseNumber()
{
    vschemaname=`echo "${1}" | tr '[a-z]' '[A-Z]'`
    vschemaver=""
    for schemaver in ${schemavers[@]}
    do
        schemaname=`echo ${schemaver} | awk -F: '{print $1}' | tr '[a-z]' '[A-Z]'`
        ver=`echo ${schemaver} | awk -F: '{print $2}'`
        if [ "${schemaname}" == "${vschemaname}" ]; then
            vschemaver="${ver}"
            break
        fi
    done
    if [ "x${vschemaver}" == "x" ]; then
        . /home/oracle/.19c_db
        export ORACLE_SID=${localsid}
        if [ "${cur_appln_support_code}" == "WEB" -a "${cur_application_type}" == "GSB" ]; then
            SQL="select distinct tdi.web_domain||'dblink'||'@'||f_get_deencrypt(api.password)
                 from shareplex_info si, database_info tdi, database_info sdi, appln_pool_info api
                 where si.src_db='${DB_NAME}'
                 and si.tgt_db=tdi.db_name
                 and si.tgt_host like tdi.trim_host||'%'
                 and si.src_db=sdi.db_name
                 and si.src_host like sdi.trim_host||'%'
                 and tdi.appln_support_code=sdi.appln_support_code
                 and sdi.db_name=api.db_name
                 and sdi.trim_host=api.trim_host
                 and upper(api.schema)='${vschemaname}';"
            dblink_info=`execSQL "${depotDBConnectStr}" "${SQL}"`
            if [ "x${dblink_info}" == "x" ]; then
                printmsg "WBXERROR: can not get dblink by ${vschemaname}. WBXEXIT"
                return -1
            fi
            dblink_name=`echo "${dblink_info}" | awk -F@ '{print $1}'`
            schpwd=`echo "${dblink_info}" | awk -F@ '{print $2}'`
            SQL="select RELEASE_NUMBER FROM ${vschemaname}.wbxdatabaseversion@${dblink_name};"
            vschemaver=`execSQL "${schemaname}/${schpwd}" "${SQL}" | sed 's/[[:space:]]//g'`
        else
            SQL="select RELEASE_NUMBER FROM ${vschemaname}.wbxdatabaseversion;"
            vschemaver=`execSQLASDBA "${SQL}" | sed 's/[[:space:]]//g'`
        fi
        
        isnumeric "${vschemaver}"
        if [ $? -eq 0 ]; then
            schemavers="${schemavers} ${vschemaname}:${vschemaver}"
        else
            printmsg "WBXERROR: can not get release_number from ${vschemaname}.wbxdatabaseversion with msg: ${vschemaver}. WBXEXIT"
            return -1
        fi
    fi
    echo "${vschemaver}"
}

# Get schema release version and insert data into wbxshareplextable table
# wbxshareplextable is used to store all shareplex tables from config file.
# if execute this tool multiple times for one port, wbxshareplextable only store the last version
analyzeconfigfile()
{
    SPLEX_PORT="$1"
    SP_CONFIGFILE="$2"
    SPLEX_USER="SPLEX${SPLEX_PORT}"
	shareplexsqlfile="/tmp/shareplex_init_data_${SPLEX_PORT}.sql"
    if [ -f ${shareplexsqlfile} ]; then
        rm -f ${shareplexsqlfile}
    fi
    echo "SET FEEDBACK OFF" > ${shareplexsqlfile}
	
	SPLEX_BIN_DIR=`cat /etc/oraport |grep "^${SPLEX_PORT}"|awk -F: '{print $2}'`
    PROFILE_PORT="${SPLEX_BIN_DIR}/.profile_u${SPLEX_PORT}"
    . ${PROFILE_PORT}
	SP_PARTITIONFILE="${SP_SYS_VARDIR}/data/horizontal_partitioning.yaml"
	if [ -f ${SP_PARTITIONFILE} ]; then
	    printmsg "shareplex partition file for port ${SPLEX_PORT} is ${SP_PARTITIONFILE}"
	fi
    cd ${SPLEX_BIN_DIR}
	spversion=`echo 'version' | ./sp_ctrl | grep 'SharePlex Version' | grep 8`
    if [ "x${spversion}" != "x" ]; then
        spversion="8"
	else
	    spversion="9"
    fi
    
    src_splex_sid=`grep -i ^Datasource ${SP_CONFIGFILE} | awk -F. '{print $NF}' | sed "s/[[:space:]]//g" | tr '[a-z]' '[A-Z]'`
    printmsg "WBXINFO: start to analyze active config file under port ${SPLEX_PORT} with datasource ${src_splex_sid} ${CONFIG_FILE}"
    
    SQL="select distinct src_db||','||upper(src_schema) from shareplex_info where upper(src_splex_sid)='${src_splex_sid}' and port=${SPLEX_PORT};"
    schemainfos=`execSQL "${depotDBConnectStr}" "${SQL}"`
    for schemainfo in ${schemainfos}
    do
        DB_NAME=`echo "${schemainfo}" | awk -F, '{print $1}'`
        schemaname=`echo "${schemainfo}" | awk -F, '{print $2}'`
        localsid=`getlocalsidbydbname ${DB_NAME}`
        getSchemaReleaseNumber "${schemaname}"
        if [ $? -eq -1 ]; then
            exit
        fi
    done
    
    printmsg "WBXINFO: ${schemavers}"
    
    echo "DELETE FROM wbxshareplextable WHERE src_splex_sid='${src_splex_sid}' and port=${SPLEX_PORT};" >> ${shareplexsqlfile}
    while read line
    do
        iscomment=`echo "${line}" | sed 's/[[:space:]]//g' | grep ^# | wc -l`
        if [ ${iscomment} -gt 0 ]; then
            continue
        fi
        isnull=`echo "${line}" | sed 's/[[:space:]]//g'`
        if [ "x${isnull}" == "x" ]; then
            continue
        fi
        isdatasrc=`echo "${line}" | grep -i ^datasource | wc -l`
        if [ ${isdatasrc} -gt 0 ]; then
            continue
        fi
    
        isvalid=`echo "${line}" | grep [\!\|@] | wc -l`
        if [ ${isvalid} -eq 0 ]; then
            printmsg "WBXERROR: invalid line: ${line}"
            continue
        fi
        #for one line to multiple targetdb case
        line=`echo "${line}" | sed "s/[[:space:]]*+[[:space:]]*/+/g"`

        src_owner=`echo "${line}" | awk '{print $1}' | awk -F. '{print $1}' | tr '[a-z]' '[A-Z]'`
        if [ `echo ${src_owner} | grep -i ^splex | wc -l` -gt 0 ]; then
            printmsg "WBXINFO: ignore shareplex table ${line}"
            continue
        fi
        
        schemareleaseno=`getSchemaReleaseNumber "${src_owner}" | sed "s/[[:space:]]*//g"`
        src_tablename=`echo "${line}" | awk '{print $1}' | awk -F. '{print $2}' | tr '[a-z]' '[A-Z]'`
        if [ "${src_tablename}" == "SPLEX_REP_MINITOR" -o  "${src_tablename}" == "CONFIGDB_REP_MONITOR" -o  "${src_tablename}" == "GCFGDB_REP_MONITOR" ]; then
            printmsg "WBXINFO: ignore shareplex table ${line}"
            continue
        fi
        
        haspartition=`echo "${line}" | awk '{print $NF}' | grep '^!' | wc -l`
        if [ ${haspartition} -gt 0 ]; then
            tgt_owner=`echo "${line}" | awk '{print $2}' | awk -F. '{print $1}' | tr '[a-z]' '[A-Z]'`
            tgt_tablename=`echo "${line}" | awk '{print $2}' | awk -F. '{print $2}' | tr '[a-z]' '[A-Z]'`
            partitionscheme=`echo "${line}" | awk '{print $NF}' | grep '^!' | sed 's/!//'`
            if [ "x${partitionscheme}" != "x" ]; then
			    if [ "${spversion}" == "8" ]; then
                    SQL="select route from ${SPLEX_USER}.shareplex_partition where upper(partition_scheme)=upper('${partitionscheme}') and rownum=1;"
                    channels=`execSQLASDBA "${SQL}"`
				else
				    ispartition="N"
				    while read line
					do
					    if [ "${line}" == "${partitionscheme}:" ]; then
						    ispartition="Y"
						fi
						if [ "${ispartition}" == "Y" ]; then
						    if [ `echo ${line} | grep "route:" | wc -l` -gt 0 ]; then
							    channels=`echo "${line}" | sed "s/.*route://g" | sed "s/[[:space:]]//g" | sed "s/+/ /g"`
								break
							fi
						fi
					done < ${SP_PARTITIONFILE}
				fi
			    echo "${channels}"
			    
                if [ "x${channels}" == "x" ]; then
                    printmsg "WBXERROR: ${partitionscheme} does not exist in ${SPLEX_USER}.shareplex_partition table: ${line}"
                    continue
                fi
            else
                printmsg "WBXERROR: the partition scheme is null: ${line}"
                continue
            fi
        else
            tgt_owner=`echo "${line}" | awk '{print $(NF-1)}' | awk -F. '{print $1}' | tr '[a-z]' '[A-Z]'`
            tgt_tablename=`echo "${line}" | awk '{print $(NF-1)}' | awk -F. '{print $2}' | tr '[a-z]' '[A-Z]'`
            channels=`echo "${line}" | awk '{print $NF}' | sed "s/+/ /g"`
        fi
        # One line can contain one of below 3 cases or not any case
        # If one line contain multiple case, the script is not supported
        # XXRPTH.XXRPT_HGSRAREPORT_CO !key(HGSSITEID,CHANGEID) 
        # XXRPTH.XXRPT_HGSSITE_OP_MAPA (HGSSITEID,SITEID,WINCODE)
        # test.WBXMMCONFERENCE !(MTGUUID,JOINCONFID)
        specifiedkey=""
        columnfilter=""
        specifiedcolumn=""
        isspecified=`echo "${line}" | grep \( | wc -l`
        if [ ${isspecified} -gt 0 ]; then
            haskey=`echo "${line}" | grep \!KEY | wc -l`
            if [ ${haskey} -gt 0 ]; then
                specifiedkey=`echo "${line}" | awk -F\( '{print $2}' | awk -F\) '{print $1}' | sed "s/[[:space:]]//g"`
                specifiedkey="!KEY(${specifiedkey})"
            else
                hascolumnfilter=`echo "${line}" | grep \! | wc -l`
                if [ ${hascolumnfilter} -gt 0 ]; then
                    columnfilter=`echo "${line}" | awk -F\( '{print $2}' | awk -F\) '{print $1}' | sed "s/[[:space:]]//g"`
                else
                    specifiedcolumn=`echo "${line}" | awk -F\( '{print $2}' | awk -F\) '{print $1}' | sed "s/[[:space:]]//g"`
                fi
            fi
        fi
        
        for channel in ${channels[@]}
        do
            tgt_splex_sid=`echo "${channel}" | awk -F. '{print $NF}' | tr '[a-z]' '[A-Z]'`
            echo "
INSERT INTO wbxshareplextable(src_splex_sid,src_owner,releasenumber,src_tablename,port,tgt_splex_sid,tgt_owner,tgt_tablename,SPECIFIEDKEY,COLUMNFILTER,SPECIFIEDCOLUMN,createtime)
VALUES ('${src_splex_sid}','${src_owner}',${schemareleaseno},'${src_tablename}',${SPLEX_PORT},'${tgt_splex_sid}','${tgt_owner}','${tgt_tablename}', '${specifiedkey}','${columnfilter}','${specifiedcolumn}',SYSDATE);
" >> ${shareplexsqlfile}
        done
        
        tabcount=$(( tabcount + 1 ))
       #  if [ ${tabcount} -gt 2 ]; then
#             break
#         fi
    done < ${SP_CONFIGFILE}
    echo "COMMIT;" >> ${shareplexsqlfile}
    echo "EXIT;"  >> ${shareplexsqlfile}
    printmsg "WBXINFO: processed ${tabcount} valid lines"
    sqlplus -S "${depotDBConnectStr}" @${shareplexsqlfile}
#   For the case that does not find config file or is not analyzed config file successfully
    hasdiff="Y"
    printmsg "WBXINFO: The config file is analyzed"
}

compareconfigfile()
{
    . /home/oracle/.19c_db
    export ORACLE_SID=${localsid}
    printmsg "WBXINFO: start to compareconfigfile"
    maillogfile="/tmp/shareplex_monitor_configfile_${SPLEX_PORT}.log"
    if [ -f ${maillogfile} ]; then
        rm -f ${maillogfile} 
    fi
    echo "To: ${MAILTO}" > ${maillogfile}
    echo "From: dbamonitortool@cisco.com" >> ${maillogfile}
    echo "Content-Type: text/html; charset='utf-8'" >> ${maillogfile}
    echo "Subject: Shareplex config file monitor on server ${localhostname} for ${GRANULARITY}" >> ${maillogfile}
    echo "The difference between shareplex config file and baseline as below<br>" >> ${maillogfile}
    echo "<table border=\"1px\"><tr><td>src_splex_sid</td><td>src_appln_support_code</td><td>src_tablename</td><td>tgt_splex_sid</td><td>tgt_appln_support_code</td><td>tgt_tablename</td><td>specifiedkey</td><td>columnfilter</td><td>specifiedcolumn</td><td>Status</td></tr>" >> ${maillogfile}
    
    isnumeric "${GRANULARITY}"
    if [ $? -eq 0 ]; then
        SPPORT="${GRANULARITY}"
        SQL="select distinct si.src_splex_sid||','||si.tgt_splex_sid||','||si.src_schema||','||upper(srcai.appln_support_code)||','||upper(tgtai.appln_support_code)||','||tdi.application_type||','||sdi.application_type
from shareplex_info si, appln_pool_info srcai,appln_pool_info tgtai, instance_info sii, database_info sdi, instance_info tii, database_info tdi
where si.port=${SPPORT} 
and si.src_host=sii.host_name
and si.src_db=sii.db_name
and sii.db_name=sdi.db_name
and sii.trim_host=sdi.trim_host
and sdi.db_type in ('PROD','BTS_PROD')
and si.tgt_host=tii.host_name
and si.tgt_db=tii.db_name
and tdi.db_type in ('PROD','BTS_PROD')
and sii.db_name=srcai.db_name
and sii.trim_host=srcai.trim_host
and tii.db_name=tgtai.db_name
and tii.trim_host=tgtai.trim_host
and si.src_schema=srcai.schema
and si.tgt_db=tgtai.db_name
and si.tgt_schema=tgtai.schema
and tii.db_name=tdi.db_name
and tii.trim_host=tdi.trim_host
and lower(srcai.appln_support_code) in ('web','config')
and lower(tgtai.appln_support_code) in ('web','opdb','lookup','tel')
and src_host in "
    else
        DB_NAME="${GRANULARITY}"
        SQL="select distinct si.src_splex_sid||','||si.tgt_splex_sid||','||si.src_schema||','||upper(srcai.appln_support_code)||','||upper(tgtai.appln_support_code)||','||tdi.application_type||','||sdi.application_type
from shareplex_info si, appln_pool_info srcai,appln_pool_info tgtai, instance_info sii, database_info sdi, instance_info tii, database_info tdi
where si.src_db='${DB_NAME}'
and si.src_host=sii.host_name
and si.src_db=sii.db_name
and sii.db_name=sdi.db_name
and sii.trim_host=sdi.trim_host
and si.tgt_host=tii.host_name
and si.tgt_db=tii.db_name
and sdi.db_type in ('PROD','BTS_PROD')
and sii.db_name=srcai.db_name
and sii.trim_host=srcai.trim_host
and tii.db_name=tgtai.db_name
and tii.trim_host=tgtai.trim_host
and si.src_schema=srcai.schema
and si.tgt_db=tgtai.db_name
and si.tgt_schema=tgtai.schema
and tii.db_name=tdi.db_name
and tii.trim_host=tdi.trim_host
and tdi.db_type in ('PROD','BTS_PROD')
and lower(srcai.appln_support_code) in ('web','config')
and lower(tgtai.appln_support_code) in ('web','opdb','lookup','tel')
and src_host in "
    fi
    SQL="${SQL}(${hostinfo:1});"
    spportinfos=`execSQL "${depotDBConnectStr}" "${SQL}"`
    if [ "x${spports}" == "x" ]; then
        printmsg "WBXERROR: can not get shareplex ports by inputted parameter ${GRANULARITY}. WBXEXIT"
        exit
    fi
    
    tabcnt=0
    
    for spportinfo in ${spportinfos[@]}
    do
        printmsg "Compare shareplex table with info: ${spportinfo}"
        src_splex_sid=`echo "${spportinfo}" | awk -F, '{print $1}'`
        tgt_splex_sid=`echo "${spportinfo}" | awk -F, '{print $2}'`
        src_schema=`echo "${spportinfo}" | awk -F, '{print $3}'`
        src_appln_support_code=`echo "${spportinfo}" | awk -F, '{print $4}'`
        tgt_appln_support_code=`echo "${spportinfo}" | awk -F, '{print $5}'`
		tgt_application_type=`echo "${spportinfo}" | awk -F, '{print $6}'`
		src_application_type=`echo "${spportinfo}" | awk -F, '{print $7}'`
        schemareleaseno=`getSchemaReleaseNumber "${src_schema}" | sed "s/[[:space:]]*//g"`
		
        if [ "x${schemareleaseno}" == "x" ]; then
            errormsg="${errormsg}\n Does not get release number under schema ${src_schema} on db ${src_splex_sid}"
            continue
        fi
        sptabcnt=0
        SQL="DELETE FROM wbxshareplexmonitordetail WHERE src_splex_sid='${src_splex_sid}' and tgt_splex_sid='${tgt_splex_sid}' and src_appln_support_code='${src_appln_support_code}' and tgt_appln_support_code='${tgt_appln_support_code}';
             COMMIT;"
        execSQL "${depotDBConnectStr}" "${SQL}"
        
        SQL="
select src_appln_support_code||'?'||src_tablename||'?'||tgt_appln_support_code||'?'||tgt_tablename||'?'||
       listagg(NVL(specifiedkey,'NULL'),';') WITHIN GROUP(ORDER BY datasrc)||'?'||
       listagg(NVL(columnfilter,'NULL'),';') WITHIN GROUP(ORDER BY datasrc)||'?'||
       listagg(NVL(specifiedcolumn,'NULL'),';') WITHIN GROUP(ORDER BY datasrc)||'?'||
       sum(decode(datasrc,'DB',1,'baseline',-1))
from (
    (select releasenumber,'${src_appln_support_code}' as src_appln_support_code, src_tablename,'${tgt_appln_support_code}' as tgt_appln_support_code,
           tgt_tablename, specifiedkey,decode('${src_application_type}','GSB',NULL,columnfilter) as columnfilter, specifiedcolumn,'ADDED' tablestatus,'DB' as datasrc
     from wbxshareplextable
     where src_splex_sid='${src_splex_sid}' 
     and tgt_splex_sid='${tgt_splex_sid}'
     minus
     select releasenumber, src_appln_support_code, src_tablename,tgt_appln_support_code, tgt_tablename,
           specifiedkey, columnfilter, specifiedcolumn,decode(tablestatus, 'remove_table','REMOVED','ADDED'),'DB' as datasrc
     from wbxshareplexbaseline 
     where releasenumber=${schemareleaseno}
     and src_appln_support_code='${src_appln_support_code}' 
     and tgt_appln_support_code='${tgt_appln_support_code}'
	 and tgt_application_type like '%${tgt_application_type}%')
     union all
     (select releasenumber, src_appln_support_code, src_tablename,tgt_appln_support_code, tgt_tablename,
            specifiedkey, columnfilter, specifiedcolumn,decode(tablestatus, 'remove_table','REMOVED','ADDED'),'baseline' as datasrc
      from wbxshareplexbaseline 
      where releasenumber=${schemareleaseno}
      and src_appln_support_code='${src_appln_support_code}' 
      and tgt_appln_support_code='${tgt_appln_support_code}'
	  and tgt_application_type like '%${tgt_application_type}%'
      and tablestatus != 'remove_table'
      minus
      select releasenumber,'${src_appln_support_code}' as src_appln_support_code, src_tablename,'${tgt_appln_support_code}' as tgt_appln_support_code,
            tgt_tablename, specifiedkey,decode('${src_application_type}','GSB',NULL,columnfilter) as columnfilter, specifiedcolumn,'ADDED' tablestatus,'baseline' as datasrc
      from wbxshareplextable 
      where src_splex_sid='${src_splex_sid}' 
      and tgt_splex_sid='${tgt_splex_sid}')
   ) group by releasenumber, src_appln_support_code, src_tablename, tgt_appln_support_code, tgt_tablename;"
   
       tablist=`execSQL "${depotDBConnectStr}" "${SQL}"`
        
        for tabinfo in ${tablist[@]}
        do
            printmsg "Compare result: ${tabinfo}"
            src_appln_support_code=`echo "${tabinfo}" | awk -F? '{print $1}'`
            src_tablename=`echo "${tabinfo}" | awk -F? '{print $2}'`
            tgt_appln_support_code=`echo "${tabinfo}" | awk -F? '{print $3}'`
            tgt_tablename=`echo "${tabinfo}" | awk -F? '{print $4}'`
            specifiedkey=`echo "${tabinfo}" | awk -F? '{print $5}'`
            columnfilter=`echo "${tabinfo}" | awk -F? '{print $6}'`
            specifiedcolumn=`echo "${tabinfo}" | awk -F? '{print $7}'`
            ismissed=`echo "${tabinfo}" | awk -F? '{print $8}'`
            if [ ${ismissed} -eq -1 ]; then
                SQL="select releasenumber 
                     from wbxshareplexbaseline 
                     where src_appln_support_code='${src_appln_support_code}' 
                     and tgt_appln_support_code='${tgt_appln_support_code}' 
                     and src_tablename='${src_tablename}' 
                     and changerelease=releasenumber;"
                releaseno=`execSQL "${depotDBConnectStr}" "${SQL}" | sed "s/[[:space:]]//g"`
                SQL="SELECT count(1) FROM ${schemaname}.wbxdatabase where version='${releaseno}';"
                isexist=`execSQLASDBA "${SQL}"`
                if [ ${isexist} -eq 0 ]; then
                    continue
                fi
            fi
            tabcnt=$(( tabcnt + 1 ))
            sptabcnt=$(( sptabcnt + 1 ))
            if [ ${ismissed} -eq -1 ]; then
                status="Missed in Config file"
                
            elif [ ${ismissed} -eq 0 ]; then
                if [ "${specifiedkey}" == "NULL;NULL" ]; then
                    specifiedkey=""
                fi
                if [ "${columnfilter}" == "NULL;NULL" ]; then
                    columnfilter=""
                fi
                if [ "${specifiedcolumn}" == "NULL;NULL" ]; then
                    specifiedcolumn=""
                fi
                status="Different"
            elif [ ${ismissed} -eq 1 ]; then
                status="Not in baseline"
            fi
            echo "<tr><td>${src_splex_sid}</td><td>${src_appln_support_code}</td><td>${src_tablename}</td><td>${tgt_splex_sid}</td><td>${tgt_appln_support_code}</td><td>${tgt_tablename}</td><td>${specifiedkey}</td><td>${columnfilter}</td><td>${specifiedcolumn}</td><td>${status}</td></tr>" >> ${maillogfile}
            SQL="INSERT INTO wbxshareplexmonitordetail(src_splex_sid,src_appln_support_code,src_tablename,tgt_splex_sid,tgt_appln_support_code,tgt_tablename,specifiedkey,columnfilter,specifiedcolumn,status) 
                 values('${src_splex_sid}','${src_appln_support_code}','${src_tablename}','${tgt_splex_sid}','${tgt_appln_support_code}','${tgt_tablename}','${specifiedkey}','${columnfilter}','${specifiedcolumn}','${status}');
                 COMMIT;"
            execSQL "${depotDBConnectStr}" "${SQL}"
        done
        if [ ${sptabcnt} -eq 0 ]; then
            SQL="INSERT INTO wbxshareplexmonitordetail(src_splex_sid,src_appln_support_code,tgt_splex_sid,tgt_appln_support_code,status) 
                 values('${src_splex_sid}','${src_appln_support_code}','${tgt_splex_sid}','${tgt_appln_support_code}','SAME');
                 COMMIT;"
            execSQL "${depotDBConnectStr}" "${SQL}"
        fi
    done
    echo "</table>" >> ${maillogfile}
    
    echo "${errormsg}" >> ${maillogfile}
    printmsg "WBXINFO: there are ${tabcnt} tables are different in total"
    
    if [ ${tabcnt} -gt 0 ]; then
        echo "sendmail -t < ${maillogfile}"
        sendmail -t < ${maillogfile}
    fi
    
}
##############main################
for spport in ${spports[@]}
do
    DB_NAME=`echo "${spport}" | awk -F, '{print $1}'`
    src_splex_sid=`echo "${spport}" | awk -F, '{print $2}'`
    SPLEX_PORT=`echo "${spport}" | awk -F, '{print $3}'`
    
    schemavers=""
    ischanged=0
    
    SPLEX_BIN_DIR=`cat /etc/oraport |grep "^${SPLEX_PORT}"|awk -F: '{print $2}'`
    if [ "x${SPLEX_BIN_DIR}" == "x" ]; then
        SPLEX_BIN_DIR="${DEFAULT_SPLEX_BIN_DIR}"
    fi
    PROFILE_PORT="${SPLEX_BIN_DIR}/.profile_u${SPLEX_PORT}"
    . ${PROFILE_PORT}
    statusdbfile="${SP_SYS_VARDIR}/data/statusdb"

#   This script does not support the case that one port contains multiple active config files
    CONFIG_FILE_NAME=`cat ${statusdbfile} | grep "Replication active from" | awk -F\| '{print $9}'`
    CONFIG_FILE="${SP_SYS_VARDIR}/config/${CONFIG_FILE_NAME}"
    if [ ! -f ${CONFIG_FILE} ]; then
        printmsg "WBXERROR: Do not find shareplex config file under port ${SPLEX_PORT} ${CONFIG_FILE}"
        continue
    fi
    
    if [ "${MTMETHOD}" == "INCREMENTAL" ]; then
        CONFIGFILE_CREATETS=`stat -c %Y ${CONFIG_FILE}`
        CURTS=`date +%s`
        if [ $(( CURTS - CONFIGFILE_CREATETS )) -lt 86400 ]; then
            printmsg "WBXINFO: the active config file ${CONFIG_FILE} under port ${SPLEX_PORT} is created in recent 1 days."
            ischanged=1
        else
            printmsg "WBXINFO: the active config file ${CONFIG_FILE} under port ${SPLEX_PORT} is created at ${CONFIGFILE_CREATETS}, no change in recent 1 day. Skip it"
            continue
        fi
    else
        ischanged=1
    fi
    
    if [ $ischanged -eq 1 ]; then
        analyzeconfigfile "${SPLEX_PORT}" "${CONFIG_FILE}"
    fi
done
#hasdiff="N"
if [ "${hasdiff}" == "Y" ]; then
    compareconfigfile
else
    printmsg "WBXINFO: no config file is analyzed. so no compare"
fi

printmsg "WBXINFO: Shareplex config file monitor end SUCCEED"
