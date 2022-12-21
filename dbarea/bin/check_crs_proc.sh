#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
# 
#  MODIFIED     (MM/DD/YY)
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/13/2017 - remove the input parameter "mailto".
#    Edwin         10/11/2017 - Add the STAP API calling.
# 
##########################################################################
# clean_ora_misc.sh
#
# Purpose:      This is shell program which will be used to check the status
#               of applications registered with CRS.
#
# input:        1) mail to DBA account
#
# output:       1) log file for the process
#
# By:           Abhijit Gujare
# date:          07/02/07
##########################################################################


############################## for STAP API call using.
START_TIME=`date "+%F %T"`
C_ID=""
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


. /u00/app/admin/dbarea/.dbaprofile

MAILTO=cwopsdba@cisco.com

$CRS_HOME/bin/crsstat|grep -vi shareplex18018|grep -vi shareplex18019|grep -vi shareplex18022|grep -vi shareplex18021| grep OFFLINE > /tmp/chk_crs_proc.log
$CRS_HOME/bin/crsstat| grep -vi shareplex18018|grep -vi shareplex18019|grep -vi shareplex18022|grep -vi shareplex18021|grep UNKNOWN >> /tmp/chk_crs_proc.log

#if [[ -s /tmp/chk_crs_proc.log ]]; then
#  C_STATUS="warning"
#  C_MSG="found OFFLINE/UNKNOWN service"
#  mailx -s "CRS resource is offline" $MAILTO < /tmp/chk_crs_proc.log
#fi

if [[ -s /tmp/chk_crs_proc.log ]]; then
	C_STATUS="warning"
        C_MSG="found OFFLINE/UNKNOWN service"
        mailx -s "CRS resource is offline" $MAILTO < /tmp/chk_crs_proc.log
                    
        cat /tmp/chk_crs_proc.log |egrep  '\.db|\.svc'  > /tmp/chk_crs_proc_pd.log
        c_host=`hostname`
        _pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"
                    
        if [[ -s /tmp/chk_crs_proc_pd.log ]]; then
        	mesg_str=`echo "DB-Alert Critical  from Host  $c_host "`
                mailx -s "$mesg_str " ${_pager_duty}< /tmp/chk_crs_proc_pd.log
        fi
fi

##########################################################################
# call STAP API.
##########################################################################
call_stap

