#!/bin/bash
##########################################################################
# clean_log_trc_11g_db.sh
#
# Purpose:      This is shell program will be used to delete trace
#               and audit files for all Databses
#
# input:        1) Destination  of the Direcotry for all databases
#               3) how many days old data to keep
#               4) mail to DBA account
#
#
#
# By:          Annapurna  DV
# date:          01-Mar-2011
#
##########################################################################


if [ $# != 3 ]; then
  echo
  echo "Usage: `basename $0` diagnostic_dest DAYS MAILTO"
  echo "                 diagnostic_dest: The value of the parameter diagnostic_dest used in the RDBMS DB"
  echo "                 DAYS           : the days to keep the files "
  echo "                 MAILTO         : the DL without cisco.com (e.g. cwopsdba)"
  echo
  exit 0
fi

export DIAG_DST=$1
export DEST_DIR=${DIAG_DST}/diag/rdbms
export DAYS="+"$2
export MAILTO=$3@cisco.com
export FIRST=YES
HOSTNAME=`uname -n`

echo "$DEST_DIR"
/usr/bin/find ${DEST_DIR}/*/*/alert/ -name "*.trc" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${DEST_DIR}/*/*/alert/ -name "*.aud" -mtime $DAYS -exec rm -rf {} \;

/usr/bin/find ${DEST_DIR}/*/*/cdump/ -name "cdmp*" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${DEST_DIR}/*/*/trace/ -name "*.aud" -mtime $DAYS -exec rm -rf {} \;
/usr/bin/find ${DEST_DIR}/*/*/trace/ -name "*.trc" -mtime $DAYS -exec rm -rf {} \;

/usr/bin/find ${DEST_DIR}/*/*/trace/ -name "alert*.old.*"  -mtime  +30 -exec rm {} \;

