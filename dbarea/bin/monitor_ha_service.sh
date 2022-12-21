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
# script to check if the instance is properly
# registerd to the HA service.
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

_host_name=`hostname -s`

_MAILTO=cwopsdba@cisco.com

_tmp_email_file="/tmp/chkHA_email.txt"
cat /dev/null > ${_tmp_email_file}

_DEBUG=1 # any value greater than 0 will display debug info
Log() {
  if [ "${_DEBUG}" != "0" ]; then
    if [ $# -gt 1 ]; then
      # the input is a file
      cat $1
    else
      echo $1
    fi
  fi
}

######################################################################################
# get the CRS Home
######################################################################################
_crs_home="`ps -ef | grep -v grep | grep crsd\.bin | awk '{print $8}' | awk -F'/' '{for(x=1;x<=NF-2;x++){printf("/%s", $x);} print "\n"; }' | sed -e 's/\/\//\//g'`"
Log "_crs_home=${_crs_home}"

######################################################################################
# get ASM Home
######################################################################################
_asm_home="`cat /etc/oratab 2>/dev/null | grep -v ^# | grep -v ^$ | grep ASM | cut -d':' -f2`"
Log "_asm_home=${_asm_home}"

######################################################################################
# DB Home
######################################################################################
_db_home="`cat /etc/oratab 2>/dev/null | grep -v ^# | grep -v ^$ | egrep -iv "ASM|agent11g|_splex|^\\*" | cut -d':' -f2 | sort -u`"
Log "_db_home=${_db_home}"

# exit if no CRS or DB home is found.
if [ -z "${_crs_home}" -o `echo "${_crs_home}" | wc -w` -ne 1 ] ; then
  echo "Either could not determine OR Zero/More than 1 CRS HOME found. (_crs_home=${_crs_home}) on ${_host_name}. VERIFY" >> ${_tmp_email_file}
  Log "Either could not determine OR Zero/More than 1 CRS HOME found. (_crs_home=${_crs_home})."
elif [ -z "${_asm_home}" -o `echo "${_asm_home}" | wc -w` -ne 1 ] ; then
  echo "Either could not determine OR Zero/More than 1 ASM HOME found. (_asm_home=${_asm_home}) on ${_host_name}. VERIFY the /etc/oratab file entries." >> ${_tmp_email_file}
  Log "Either could not determine OR Zero/More than 1 ASM HOME found. (_asm_home=${_asm_home})."
elif [ -z "${_db_home}" -o `echo "${_db_home}" | wc -w` -ne 1 ] ; then
  echo "Either could not determine OR Zero/More than 1 DB HOME found. (_db_home=${_db_home}) on ${_host_name}. VERIFY the /etc/oratab file entries." >> ${_tmp_email_file}
  Log "Either could not determine OR Zero/More than 1 DB HOME found. (_db_home=${_db_home})."
else
  
  ######################################################################################
  # get the installed ORACLE version
  ######################################################################################
  _ora_version="`export ORACLE_HOME=${_db_home};${_db_home}/bin/sqlplus /nolog << EOS | grep "Release" | awk '{print $3}' | awk -F'.' '{print $1}'
EOS`"
  Log "_ora_version=${_ora_version}"

  ######################################################################################
  # instances running on this server (as of now, not being used in this script.)
  ######################################################################################
  _instances="`ps -ef | grep -v grep | grep pmon | grep -v ASM | awk '{print $8}' | awk -F'_' '{print $3}'`"
  Log "_instances=${_instances}"

  ######################################################################################
  # get the DB Names
  ######################################################################################
  _dbs="`export ORACLE_HOME=${_db_home};${_db_home}/bin/srvctl config`"
  Log "_dbs=${_dbs}"

  ######################################################################################
  # get the number of instances for each DB running on this server
  # and put in a file.
  # assuming that all DB will have same number of instance configured.
  ######################################################################################
  if [ -n "${_dbs}" ]; then
    _tmp_inst_cnt="/tmp/chkHA1.txt" # file used to get the database instance count for the DB from CRS
    cat /dev/null > ${_tmp_inst_cnt}
    Log "_tmp_inst_cnt=${_tmp_inst_cnt}"

    _tmp_srv_frm_crs="/tmp/chkHA2.txt" # file used to get the service name for the DB from CRS; in the format db_name:server_name
    cat /dev/null > ${_tmp_srv_frm_crs}
    Log "_tmp_srv_frm_crs=${_tmp_srv_frm_crs}"

    export ORACLE_HOME=${_db_home}
    case ${_ora_version} in
      10)
          # oracle 10g version

          # get the # of instanse registered for the DB from CRS registery.
          for _db in ${_dbs}
          do
            ${_db_home}/bin/srvctl config database -d ${_db} | wc -l >> ${_tmp_inst_cnt}
            
            # get the service names registered for the DB from CRS registery.
            ${_db_home}/bin/srvctl config service -d ${_db} | awk -v db=${_db} '{print db":"$1}' >> ${_tmp_srv_frm_crs}
          done

          # get the listeners running on this server
          _listeners="`ps -ef  | grep tnsl | grep -v grep | awk '{print $9}' | tr '\n' ' '`"
          #_lsnr_home="${_db_home}"
          _lsnr_homes="`ps -ef | grep tnsl | grep -v grep | awk '{print $8}' | awk -F'/' '{for(x=2;x<NF-1;x++) printf(\"/%s\", $x); printf(\"%s\", \" \");}'`"
          ;;
      11)
          # oracle 11g version

          # get the # of instanse registered for the DB from CRS registery.
          for _db in ${_dbs}
          do
            ${_db_home}/bin/srvctl config database -d ${_db} | grep "^Database instances:" | cut -d':' -f2 | awk -F',' '{print NF}' >> ${_tmp_inst_cnt}
            
            # get the service names registered for the DB from CRS registery.
            ${_db_home}/bin/srvctl config service -d ${_db} | grep "^Service name:" | awk -v db=${_db} -F':' '{print db":"$2}' | tr -d ' ' >> ${_tmp_srv_frm_crs}
          done


          # get the listeners running on this server; only the scan for 11g as the node listener
          # will listen only for that node's instances.
          # and also scan listener is the one which appln. are using.
          #_listeners="`ps -ef | grep -v grep | grep tnsl | awk '{print $9}' | grep -vw LISTENER`"
          _listeners="`ps -ef  | grep tnsl | grep -v grep | awk '{print $9}' | tr '\n' ' '`"
          #_lsnr_home="${_crs_home}"
          _lsnr_homes="`ps -ef | grep tnsl | grep -v grep | awk '{print $8}' | awk -F'/' '{for(x=2;x<NF-1;x++) printf(\"/%s\", $x); printf(\"%s\", \" \");}'`"
          ;;
      *)
          # unknown version as of now. (May 12 12)
          exit 2
          ;;
    esac
    Log "_listeners=${_listeners}"
    Log "_lsnr_homes=${_lsnr_homes}"

    # get the max instance count for the DBs on this server
    if [ -s "${_tmp_inst_cnt}" ]; then
      _inst_cnt=`cat ${_tmp_inst_cnt} 2>/dev/null | awk 'mx < $0 {mx=$0} END{print mx}'`
    else
      _inst_cnt=0
    fi
    Log "_inst_cnt=${_inst_cnt}"

    if [ -n "${_listeners}" ]; then
      # get all the services for the listeners running on this node.
      _tmp_lsnrs="/tmp/chkHA3.txt" # file used to store all the non-system HA services running from lsnrctl command
      cat /dev/null > ${_tmp_lsnrs}
      Log "_tmp_lsnrs=${_tmp_lsnrs}"

      _x=1
      for _listener in ${_listeners}
      do
        _lsnr_home="`echo ${_lsnr_homes} | awk -v i=${_x} '{print $i}'`"
        export ORACLE_HOME=${_lsnr_home}
        ${_lsnr_home}/bin/lsnrctl status ${_listener} | grep "^Service" | egrep -v "Summary|ASM|PLSExtProc|XDB|XPT|SYS" | awk -v lsnr=${_listener} '{print lsnr" "$2" "$4}' >> ${_tmp_lsnrs}
        _x=`expr ${_x} + 1`
      done

      # check if the configured HA service for the DB is being listned by the listener
      _tmp_srv_not_wt_lsnr="/tmp/chkHA4.txt" # file will have all service registerd with CRS which are not in listener.
      cat /dev/null > ${_tmp_srv_not_wt_lsnr}
      Log "_tmp_srv_not_wt_lsnr=${_tmp_srv_not_wt_lsnr}"

      while read _line
      do
        _d="`echo ${_line} | cut -d':' -f1`" # database name
        _s="`echo ${_line} | cut -d':' -f2`" # service name

        # check if the service is being listining by the ALL listener
        for _listener in ${_listeners}
        do
          _w=`cat ${_tmp_lsnrs} | grep -w ${_listener} | grep -c ${_s}`
          if [ ${_w} -eq 0 ]; then
            echo "${_listener}:${_line}" >> ${_tmp_srv_not_wt_lsnr}
          fi
        done
      done < ${_tmp_srv_frm_crs}
    else
      # no listeners seems to be running
      # send an email
      echo "THERE ARE NO LISTENER(S) RUNNING ON ${_host_name}. VERIFY" >> ${_tmp_email_file}
      Log "THERE ARE NO LISTENER(S) RUNNING ON ${_host_name}. VERIFY"
    fi

    # iterate thru the listener file _tmp_lsnrs
    # and check if the registered services are equal to
    # the _inst_cnt
    # in 11g, the LISTENER will listen only for the instance on that node.

    if [ -s "${_tmp_lsnrs}" ]; then
      _tmp_srv_wt_less_inst_cnt="/tmp/chkHA5.txt" # file will have all the violating HA services list.
      cat /dev/null > ${_tmp_srv_wt_less_inst_cnt}
      Log "_tmp_srv_wt_less_inst_cnt=${_tmp_srv_wt_less_inst_cnt}"

      cat ${_tmp_lsnrs} | grep -vw "LISTENER" | awk -v c=${_inst_cnt} '{if($3 != c) {print $0;} }' >> ${_tmp_srv_wt_less_inst_cnt}
      #cat ${_tmp_lsnrs} | awk -v c=${_inst_cnt} '{if($3 != c) {print $0;} }' >> ${_tmp_srv_wt_less_inst_cnt}

      if [ -s "${_tmp_srv_wt_less_inst_cnt}" ]; then
        # send the email
        echo "THE BELOW SERVICE(S) HAS NOT REGISTERED THE INSTANCES PROPERLY ON HOST (${_host_name}). VERIFY IMMEDIATELY." >> ${_tmp_email_file}
        echo "" >> ${_tmp_email_file}
        echo "The number of instance(s) registed with CRS for each running database on this host is ${_inst_cnt}" >> ${_tmp_email_file}
        echo "" >> ${_tmp_email_file}
        cat ${_tmp_srv_wt_less_inst_cnt}  | awk 'BEGIN {
          printf("%-35s %-30s %-10s\n", "Service Name", "Listener Name", "Registered Inst. count");
          printf("%-35s %-30s %-10s\n", "-------------", "------------", "----------------------")
        }
        {  printf("%-35s %-30s %-10s\n", $2, $1, $3);}' >> ${_tmp_email_file}
      fi
    else
      # no services other than the default services seems to registerd.
      # need to send email for this too.
      echo "OTHER THAN THE SYSTEM SERVICE, THERE ARE NO OTHER HA SERVICE(S) RUNNING ON HOST (${_host_name}). VERIFY IMMEDIATELY." >> ${_tmp_email_file}
      Log "OTHER THAN THE SYSTEM SERVICE, THERE ARE NO OTHER HA SERVICE(S) RUNNING ON HOST (${_host_name}). VERIFY IMMEDIATELY."
    fi

    # check for the service registerd in CRS and not listining by the listener
    if [ -s "${_tmp_srv_not_wt_lsnr}" ]; then
      if [ -s "${_tmp_email_file}" ]; then
        echo "" >> ${_tmp_email_file}
        echo "" >> ${_tmp_email_file}
      fi
      echo "THE BELOW SERVICE(S) WHICH ARE REGISTERED WITH CRS ARE NOT BEING LISTENED BY THE LISTENER NOW." >> ${_tmp_email_file}
      echo "" >> ${_tmp_email_file}
      cat ${_tmp_srv_not_wt_lsnr} | awk -F ':' 'BEGIN {
        printf("%-35s %-15s %-30s\n", "Service Name", "Database Name", "Listener Name");
        printf("%-35s %-15s %-30s\n", "------------", "-------------", "-------------")
      }
      { printf("%-35s %-15s %-30s\n", $3, $2, $1); }' >> ${_tmp_email_file}
    fi
  else
    # no databases found to be running on this box.
    echo "No databases running on ${_host_name}. VERIFY" >> ${_tmp_email_file}
    Log "No databases running on this node."
  fi
fi

if [ -s "${_tmp_email_file}" ]; then
  # send the email.

  _email_file="/tmp/emailHA.txt"
  cat /dev/null > ${_email_file}

  cat ${_tmp_email_file} | awk 'BEGIN{printf("%s\n\n","Hi,")} {print $0;} END{printf("\n\n%s\n\n","~DBA Team")}' >> ${_email_file}

  mailx -s "Urgent!! Instance(s) not registerd properly on ${_host_name}" ${_MAILTO} < ${_email_file}

  Log "================================================"
  Log ${_tmp_email_file} "f"

  C_STATUS="warning"
  C_MSG="Instance(s) not registerd properly."

fi


##########################################################################
# call STAP API.
##########################################################################
call_stap

