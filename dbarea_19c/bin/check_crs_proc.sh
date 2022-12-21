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

MAILTO=cwopsdba@cisco.com

crsstat | grep -v proxy_advm |grep -v acfs| grep OFFLINE > /tmp/chk_crs_proc.log
crsstat | grep -v proxy_advm |grep -v acfs |grep UNKNOWN >> /tmp/chk_crs_proc.log

if [[ -s /tmp/chk_crs_proc.log ]]; then
  C_STATUS="warning"
  C_MSG="found OFFLINE/UNKNOWN service"
  mailx -s "CRS resource is offline" $MAILTO < /tmp/chk_crs_proc.log

  cat /tmp/chk_crs_proc.log |egrep  '\.db|\.svc'  > /tmp/chk_crs_proc_pd.log
  c_host=`hostname`
  _pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"

  if [[ -s /tmp/chk_crs_proc_pd.log ]]; then
      mesg_str=`echo "DB-Alert Critical  from Host  $c_host at $START_TIME"`
      mailx -s "$mesg_str " ${_pager_duty}< /tmp/chk_crs_proc_pd.log
  fi
fi