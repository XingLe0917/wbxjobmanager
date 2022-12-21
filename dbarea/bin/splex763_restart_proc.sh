#!/bin/ksh
############################################################
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
############################################################

if [ $# != 1 ]; then
   echo
   echo "Usage: `basename $0` SPLEX_PORT_NUMBER"
   echo
   exit
fi

export SPLEX_BIN_DIR=/sjdbop/shareplex763/bin/
export SPLEX_PORT=$1
export HOSTNAME=`hostname`
export MAILTO=cwopsdba@cisco.com
#export MAILTO=cahua@cisco.com
export CONFIGF=${SPLEX_BIN_DIR}/WbxSplexAutoStartStoppedProcess.config
export TMPFILE0=/tmp/$$.txt.0
export TMPFILE1=/tmp/$$.txt.1
export TMPFILE2=/tmp/$$.txt.2
export TMPFILE3=/tmp/$$.txt.3
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

#
# Add module to check if splex is running (sp_cop)
#
RUNNING=`ps -ef |grep sp_cop |grep ${SPLEX_PORT} |wc -l`
if [ $RUNNING -lt 1 ]
then
   echo
   echo "Please verify sp_cop for port ${SPLEX_PORT} in $HOSTNAME" | $MAIL -s "Shareplex: sp_cop not running for ${SPLEX_PORT} in $HOSTNAME" $MAILTO
   echo "The shareplex for the port is NOT running!"
   exit 4
fi

AUTOSTARTFLAG=`awk -F: "/^${SPLEX_PORT}:/ {print \\$2; exit}" $CONFIGF 2>/dev/null`
# echo  ${SPLEX_PORT} $AUTOSTARTFLAG
if [ "$AUTOSTARTFLAG" != "Y" -a "$AUTOSTARTFLAG" != "y" ]
then
   exit
fi

#Find the processes having issues
echo "show" | ./sp_ctrl |grep -v "^sp_ctrl " |grep -v "^Process " |grep -v "^--------" |grep -v "^$" > $TMPFILE0

# cut -f1 -d" " $TMPFILE0  | uniq > $TMPFILE1
grep "Stopped - due to error" $TMPFILE0 |cut -f1 -d" " | uniq  > $TMPFILE1

# Handle the die processes
for die_proc in `cat $TMPFILE1`
do
   case $die_proc
   in
      MTPost)  DPROC="Post";;
      *)       DPROC=$die_proc;;
   esac
   cd $SPLEX_BIN_DIR
   echo "start $DPROC"
   echo "start $DPROC" | ./sp_ctrl
   sleep 6
   $MAIL -s "Shareplex: auto restart $DPROC for port ${SPLEX_PORT} in $HOSTNAME" $MAILTO < $TMPFILE0
done

# Handle the disk full
grep "Stopped - disk is full" $TMPFILE0 > $TMPFILE2
typeset -i linenum
linenum=`cat $TMPFILE2 |wc -l`
if [ $linenum -ge 1 ]
then
   echo "URGENT file system is FULL for $SPLEX_PORT in $HOSTNAME"
   $MAIL -s "Shareplex: URGENT file system is FULL for ${SPLEX_PORT} in $HOSTNAME" $MAILTO < $TMPFILE0
fi

# Handle the core dump
grep "Stopped - core dumped" $TMPFILE0 > $TMPFILE3
typeset -i linenum
linenum=`cat $TMPFILE3 |wc -l`
if [ $linenum -ge 1 ]
then
   echo "URGENT CORE DUMP for $SPLEX_PORT in $HOSTNAME"
   $MAIL -s "Shareplex: URGENT CORE DUMP for ${SPLEX_PORT} in $HOSTNAME" $MAILTO < $TMPFILE0
fi

#cat $TMPFILE0; echo "=*=*=*==*=*=*==*=*=*==*=*=*="
#cat $TMPFILE1; echo "=*=*=*==*=*=*==*=*=*==*=*=*="
#cat $TMPFILE2; echo "=*=*=*==*=*=*==*=*=*==*=*=*="
#cat $TMPFILE3; echo "=*=*=*==*=*=*==*=*=*==*=*=*="
/bin/rm $TMPFILE0 $TMPFILE1 $TMPFILE2 $TMPFILE3
exit 0

