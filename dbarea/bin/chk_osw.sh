#!/bin/ksh

ORACLE_BASE=/u00/app/oracle
export ORACLE_BASE
ORACLE_HOME=/u00/app/oracle/product/11.2.0/db
export ORACLE_HOME
PATH=$ORACLE_HOME/bin:$PATH
export PATH
ORACLE_SID=$1
export ORACLE_SID

ret=`ps -ef |grep OSWatcher.sh |grep -v grep |wc -l`
if [ $ret -eq 0 ]
then
#  cd /opt/osw
  cd /var/crash/osw
  /var/crash/osw/startOSW.sh 60 168 gzip  >>/tmp/OSWatcherstatus
  mailx -s "OSWatcher Not Running,Restarted" cwopsdba@cisco.com,unix-sa@cisco.com</tmp/OSWatcherstatus
fi

