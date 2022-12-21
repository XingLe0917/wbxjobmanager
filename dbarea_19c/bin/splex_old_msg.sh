#!/bin/sh
##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
#
#  MODIFIED     (MM/DD/YY)
#    Edwin         03/01/2018 - Use "ps" to get the BIN dir for port.
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/12/2017 - Add the STAP API calling.
#
##########################################################################
#
#  splex_restart_proc.sh.sh
#
#     This script is used to re-start stopped shareplex
#     process due to error
#     Also if disk full for VARDIR, send out email.
#
#     input:
#      1)   shareplex port number
#     output:
#      1)   [optional] log file in standard log directory
#
#  2006/12/08 By Tony OUYANG: Created.
#  2006/12/09 By Tony OUYANG: Add function - if disk full for VARDIR,
#              send out email.
#  2006/12/11 By Tony OUYANG: Add function - only run if FLAG is set.
#  2009/03/19 By Britto Susaimanickam: Added CORE DUMP logic.
#
##########################################################################
source /staging/gates/bash_common.sh
. /home/oracle/.bash_profile

export MAILTO=cwopsdba@cisco.com
_pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"
_check_fname=/tmp/chk_splex_$$.log
_script_name=splex_old_msg.sh
status=`ps -ef| grep $_script_name| grep -v grep | wc -l`
echo $status
if [ $status -gt 2 ]; then
echo "Team " >${_check_fname}
echo "   " >>${_check_fname}
echo " Script $_script_name is already running. Below is the process details" >>${_check_fname}
echo "  " >>${_check_fname}
ps -ef | grep $_script_name | grep -v grep  >> ${_check_fname}
echo "   " >>${_check_fname}
echo "    " >>${_check_fname}
echo "sp_ctrl slow or hung for the ports on the `hostname`" >> ${_check_fname}
echo " Please check df -k command , if it is hung please contact storage/soc to Fix it " >> ${_check_fname}
echo "  " >> ${_check_fname}
echo "Thanks, " >>  ${_check_fname}
echo "DBA Team" >> ${_check_fname}
mailx -s "Script $_script_name is already running on `hostname`" $MAILTO < ${_check_fname}
exit 1;
fi


############################## END.



export SPLEX_BIN_DIR=""
export HOSTNAME=`hostname -s`

FILTEREDSPLIST=$(getspmonitorblacklist "${HOSTNAME}")
############################################################################################################
### New method to get the BIN_DIR for the running port avoid the hard code in the script.
############################################################################################################

for SPLEX_PORT in `ps -ef|grep sp_cop|grep -v grep | grep -v 20001 | grep -v 20002 |awk '{print $NF}'|tr -d u|sed -e 's/-//'`
do
    if [ ! -z "${FILTEREDSPLIST}" ]; then
        if [ `echo ${FILTEREDSPLIST} | grep -iwc ${SPLEX_PORT}` -gt 0 ]; then
            continue
        fi
    fi
BIN_RUN=`ps -eaf | grep sp_cop | grep -v grep | grep ${SPLEX_PORT} | awk {'print $8'}`
SPLEX_BIN_DIR=${BIN_RUN/%\/.app-modules\/sp_cop/\/bin}

if [ -z ${SPLEX_BIN_DIR} ]
then
   echo
   echo "Can not find the shareplex dir for the pointed port using ps!"
   echo "Can not find the shareplex dir for the pointed port ${SPLEX_PORT} in $HOSTNAME" | $MAIL -s "Shareplex: directory not exists for ${SPLEX_PORT} in $HOSTNAME" $MAILTO
   exit 1
fi

export CONFIGF=${SPLEX_BIN_DIR}/WbxSplexAutoStartStoppedProcess.config
export TMPFILE0=/tmp/$$.txt.0
export TMPFILE1=/tmp/$$.txt.1
export TMPFILE2=/tmp/$$.txt.2
export TMPFILE3=/tmp/$$.txt.3
export TMPFILE4=/tmp/$$.txt.4
export TMPFILE5=/tmp/$$.txt.5

#
# For SunOS, Mail should be /usr/bin/mailx
# export MAIL=/usr/bin/mailx
#
export MAIL=/bin/mail

#
# Add module to check if the port is all numeric
#

if [ ! -d $SPLEX_BIN_DIR ]
then
   echo
   echo "The shareplex dir does NOT exist!"
   echo "The shareplex directory ${SPLEX_BIN_DIR} does not exists for ${SPLEX_PORT} in $HOSTNAME" | $MAIL -s "Shareplex: directory not exists for ${SPLEX_PORT} in $HOSTNAME" $MAILTO
   exit 1
fi
cd $SPLEX_BIN_DIR

if [ ! -f .profile_u${SPLEX_PORT} ]
then
   echo
   echo "The shareplex profile for the port does NOT exist!"
   exit 2
fi

. ${SPLEX_BIN_DIR}/.profile_u${SPLEX_PORT}

if [ ! -f ${CONFIGF} ]
then
   echo
   echo "The shareplex Auto Restart Porcess Config file does NOT exist!"
   exit 3
fi

##checking the old messages greater than 1440 Min
#=======================================
#=======================================

export TMPFILE4=/tmp/$$.txt.4
export TMPFILE5=/tmp/$$.txt.5
#_pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"


echo "qstatus" | ./sp_ctrl |grep -v "^sp_ctrl " |grep -v "^--------" |grep -v "^$" > $TMPFILE4

_chk_num=`cat $TMPFILE4|grep "Number of messages"|awk '{print $6}'|awk '$1 >= 1440'|wc -l`

if [ $_chk_num -gt 0 ];
then
#sed -i '1 i\Please check Queues with AGE greater than 300Min for number of messages \n \n \n \n \n' $TMPFILE4

echo "Please check Queues with Age greater than 1440 Min for number of messages" > $TMPFILE5
echo "==========================================================================" >>$TMPFILE5
echo "                            ">>$TMPFILE5
echo "                            ">>$TMPFILE5
for _no_msgs in `cat $TMPFILE4|grep "Number of messages"|awk '$6>=1440 {print $6}'`
do
  cat $TMPFILE4|grep -B1 -A1 $_no_msgs >> $TMPFILE5
  echo "      ">>$TMPFILE5
done

echo "Note: for any queue if Age greater than 300 min in number of messages, it means its having OLD messages which need to be cleaned up using QVIEW commands." >>$TMPFILE5
echo "Basic steps for trouble shooting http://dba.corp.webex.com/dba_reports/sp_trouble_shoot.htm" >>$TMPFILE5

mailx -s "Shareplex Queue having Old Messages For $SPLEX_PORT " $MAILTO  <$TMPFILE5
mesg_str=`echo "DB-Alert Critical $HOSTNAME port  $SPLEX_PORT having Old messages "`
mailx -s "$mesg_str " ${_pager_duty}< $TMPFILE5
fi

done
