#!/bin/ksh
#Script to check if ASM/Database instance is running or noton the backup server

ORACLE_SID=$1
MAILTO=$2@cisco.com


if [ $# != 2 ]; then
echo
echo "Usage: ASM_instance.sh ORACLE_SID MAILTO "
echo
exit 0
fi


check=`ps -ef | grep -i smon_$1|grep -v grep| wc -l`
check_listener=`ps -ef | grep -i inherit|grep -v grep| wc -l`

if [ $check_listener -eq 0 ]; then

mailx -s "Listener is not running DBA's please check and start the listener" $MAILTO < /dev/null

fi


if [ $check -eq 0 ]; then

mailx -s "$1 instance is not running DBA's please check" $MAILTO < /dev/null


fi

exit 0
