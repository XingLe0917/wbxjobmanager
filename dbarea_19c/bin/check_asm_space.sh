#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
# 
#  MODIFIED     (MM/DD/YY)
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/14/2017 - Rename the file to "check_asm_space.sh".
#    Edwin         10/14/2017 - Move the SQL file content into script.
#    Edwin         10/12/2017 - Add the STAP API calling.
# 
##########################################################################
#
#    gener_run_asm.sh
#
#     This script is used to run general sql on all scripts
#
#     08/06/07 By Canny Hua
#
##########################################################################

############################## for STAP API call using.
START_TIME=`date "+%F %T"`
C_ID=""
C_STATUS="success"
C_MSG=""


. /home/oracle/.bash_profile
ASM_SID="`ps -ef | grep asm_smon | grep -v grep | grep ASM | awk '{print $8}' | cut -d'_' -f3`"
export ORACLE_SID=$ASM_SID
export ORACLE_HOME=$ORA_CRS_HOME
MAILLIST="cwopsdba@cisco.com"
rm -rf /tmp/check_asm_space.lst

sqlplus -s / as sysdba << EOF
spool /tmp/check_asm_space.lst
set echo off
set verify off
column "% LEFT_PER" format 99.99; 
select name,TOTAL_MB,FREE_MB, FREE_MB*100/TOTAL_MB "% LEFT_PER" from v\$asm_diskgroup where FREE_MB/TOTAL_MB <0.1;
spool off
EOF

mflag=`grep '[1-9]' /tmp/check_asm_space.lst`
if [ "X$mflag" = 'X' ]
then
  mflag=0
else
  mflag=2
fi

if  [ $mflag -ge "1" ]
then
  C_STATUS="warning"
  C_MSG="the ASM storage alarm."
  
  mailx -s "ALERT- the ASM storage alarm " $MAILLIST < /tmp/check_asm_space.lst

fi

