############################################################
#
#    gener_run_asm_fra.sh
#
#     This script is used to run general sql on all scripts
#
#     08/06/07 By Canny Hua
#
############################################################
. /home/oracle/.asm_profile
help_msg()
{
more <<EOF
Usage:  gener_run.sh xxx (this xxx.sql need under /u00/app/admin/dbarea/sql)
EOF
}

####################################################################
#Main
####################################################################
ARGV=$1
echo $ARGV
MAILLIST="cwopsdba@cisco.com"
#MAILLIST="canny.hua@cisco.com"
rm -rf $ADMIN_HOME/log/$ARGV.lst

if [ "x$ARGV" = "x" ]
then
  help_msg
  exit 0;
else
  if [ ! -f $ADMIN_HOME/sql/$ARGV.sql ]
  then
    help_msg
    exit 0;
  fi
fi

sqlplus -s sys/sysnotallow as sysdba << EOF
@$ADMIN_HOME/sql/$ARGV.sql
spool off;
EOF

mflag=`grep '[1-9]' $ADMIN_HOME/log/$ARGV.lst`
if [ "X$mflag" = 'X' ]
then
  mflag=0
else
  mflag=2
fi

if  [ $mflag -ge "1" ]
then
  mailx -s "ALERT- Archive destination alarm!!-  $HOSTNAME " $MAILLIST < $ADMIN_HOME/log/$ARGV.lst
fi

