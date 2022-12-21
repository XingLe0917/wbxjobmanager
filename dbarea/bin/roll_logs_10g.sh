#!/bin/ksh
# Functionality: To trim alert-log and listener-log
#
HOSTNAME=`uname -n`

export HOSTNAME

echo "start time `date`" > /tmp/trim_logs.lst

exec 3< /u00/app/admin/dbarea/bin/instances #open oratab as file-descriptor 3

while read -r -u3 LINE

do

case $LINE in

\#*) ;; #Ignore comments in oratab

*)

ORACLE_DB=$(print $LINE | awk -F: '{print $1}' -)

ORACLE_HOME=$(print $LINE | awk -F: '{print $2}' -)

ALERTLOG=/u00/app/oracle/admin/$ORACLE_DB/bdump/alert_$ORACLE_DB.log

tail -1000 $ALERTLOG > /tmp/$ORACLE_DB_tmp.log

# if necessary, archive $ALERTLOG, prior to overwriting

cp /u00/app/oracle/admin/$ORACLE_DB/bdump/alert_$ORACLE_DB.log /u00/app/oracle/admin/$ORACLE_DB/bdump/alert_$ORACLE_DB.log.old.`date +%Y%m%d%H%M`

cp /tmp/$ORACLE_DB_tmp.log $ALERTLOG

rm /tmp/$ORACLE_DB_tmp.log

;;

esac

done

LISTENERLOG=$ORACLE_HOME/network/log/listener.log

if [[ -f $LISTENERLOG ]]; then

tail -1000 $LISTENERLOG > /tmp/listener.log

# archive $LISTENERLOG if necessary, prior to being overwritten

cp /tmp/listener.log $LISTENERLOG

rm /tmp/listener.log

fi

#Trim CSSD log in  /u00/app/oracle/product/10.2.0/crs/log/<hostname>/cssd/ocssd.log 

CSSDLOG=/u00/app/oracle/product/10.2.0/crs/log/$HOSTNAME/cssd/ocssd.log

if [[ -f $CSSDLOG ]]; then

tail -1000 $CSSDLOG > /tmp/ocssd.log

cp /tmp/ocssd.log $CSSDLOG

rm /tmp/ocssd.log

fi

#Trim EVMD log in  /u00/app/oracle/product/10.2.0/crs/log/<hostname>/evmd/evmdOUT.log 

EVMDLOG=/u00/app/oracle/product/10.2.0/crs/log/$HOSTNAME/evmd/evmdOUT.log

if [[ -f $EVMDLOG ]]; then

tail -1000 $EVMDLOG > /tmp/evmdOUT.log

cp /tmp/evmdOUT.log $EVMDLOG

rm /tmp/evmdOUT.log

fi
