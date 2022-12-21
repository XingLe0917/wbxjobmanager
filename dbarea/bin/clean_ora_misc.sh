#!/bin/ksh
##########################################################################
# clean_ora_misc.sh
#
# Purpose:      This is shell program will be used to delete trace
#               and audit files for asm instance,the primary database and . 
#
# input:        1) destination asm instance directory
#               2) destination primary database directory
#               3) how many date old data to keep
#               4) mail to DBA account
#
# output:       1) log file for the process
#
# By:           Abhijit Gujare 
# date:          06/06/07
#
##########################################################################

if [ $# != 4 ]; then
echo
echo "Usage: clean_ora_misc.sh DEST_ASM_DIR DEST_DB_DIR DAYS MAILTO"
echo
exit 0
fi

. /u00/app/admin/dbarea/.dbaprofile      
export DEST_ASM_DIR=$1
export DEST_DB_DIR=$2
export DAYS="+"$3
export MAILTO=$4@cisco.com
export FIRST=YES
HOSTNAME=`uname -n`

# clear any files older than $DAYS
/usr/bin/find $DEST_ASM_DIR/bdump/ -name "*.trc" -mtime $DAYS -exec rm {} \;
/usr/bin/find $DEST_ASM_DIR/cdump/ -name "*.trc" -mtime $DAYS -exec rm {} \;
/usr/bin/find $DEST_ASM_DIR/bdump/ -name "cdmp*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find $DEST_ASM_DIR/udump/ -name "*.trc" -mtime $DAYS -exec rm {} \;
/usr/bin/find $DEST_ASM_DIR/adump/ -name "*.aud" -mtime $DAYS -exec rm {} \;
/usr/bin/find $DEST_DB_DIR/bdump/ -name "*.trc" -mtime $DAYS -exec rm {} \;
/usr/bin/find $DEST_DB_DIR/cdump/ -name "*.trc" -mtime $DAYS -exec rm {} \;
/usr/bin/find $DEST_DB_DIR/udump/ -name "*.trc" -mtime $DAYS -exec rm {} \;
/usr/bin/find $DEST_DB_DIR/adump/ -name "*.aud" -mtime $DAYS -exec rm {} \;

