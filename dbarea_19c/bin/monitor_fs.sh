#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
#
#  MODIFIED     (MM/DD/YY)
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/12/2017 - Add the STAP API calling.
#   ZHIWLIU        13/6/2021  - Add inode
#
##########################################################################

START_TIME=`date "+%F %T"`
C_ID=""
C_STATUS="success"
C_MSG=""


MAILLIST=cwopsdba@cisco.com
_check_fname=/tmp/chk_fs_monitor.log
#status=`ps -ef | grep  monitor_fs.sh | grep -v grep  | wc -l |awk '{ print $1 }'`
_chk_pid=$$
status=`ps -ef | grep monitor_fs.sh | grep -v grep | grep -v $_chk_pid |wc -l |awk '{ print $1 }'`
echo "status " $status
if [ $status -gt 2 ]; then
        echo " Team " > ${_check_fname}
        echo " " >> ${_check_fname}
        echo " Script  monitor_fs.sh  is already  running  " >>${_check_fname}
        echo "   "  >> ${_check_fname}
        echo "   "  >> ${_check_fname}
        ps -ef | grep  monitor_fs.sh | grep -v grep  >> ${_check_fname}
        echo "   "  >> ${_check_fname}
        echo "   "  >> ${_check_fname}
        echo " Please check df -k command , if it is hung please contact storage/soc to Fix it  " >> ${_check_fname}
        echo "   "  >> ${_check_fname}
        echo "Thanks,   "  >> ${_check_fname}
        echo "DBA Team   "  >> ${_check_fname}
        mailx -s "Script monitor_fs.sh is aleady running  on `hostname`  " $MAILLIST < ${_check_fname}
        exit 1;
fi

############################## END.


export _DF=`echo /tmp/df_$$.txt`
export _TMP_EMAIL=`echo /tmp/tmp_email_$$.txt`
export _EMAIL=`echo /tmp/email_$$.txt`
export _THRESHOLD=90

cat /dev/null > ${_DF}

# get the unix file system mount point information
df -H | grep '%' | grep -vE 'Filesystem|tmpfs' | grep -v "^ " | awk '{ print $4 " " $5 " " $6 }' > ${_DF}

# get the shared (NFS) mount point information and append it to the file
df -H | grep '%' | grep -vE 'Filesystem|tmpfs' | grep "^ " | awk '{ print $3 " " $4 " " $5 }'    >> ${_DF}

#cat ${_DF}

cat /dev/null > ${_TMP_EMAIL}
cat /dev/null > ${_EMAIL}
_MAIL_SUB=

while read output
do
#echo $output
  usep=$(echo $output | awk '{ print $2}' | cut -d'%' -f1  )
  partition=$(echo $output | awk '{ print $3 }' )
  avail=`echo $output |awk '{print $1}'`
#echo "usep = ${usep}"
#echo "partition = ${partition}"
  if [ $usep -ge ${_THRESHOLD} ]; then
       echo "`date`:$(hostname):$partition ($usep%): Available ($avail)" >> ${_TMP_EMAIL}
        if [ $partition = "/sjrac_rman_vol" -o $partition = "/sjcon_rman_vol" -o $partition = "/sjracrpt_rman_vol" ]; then
echo "" >> ${_TMP_EMAIL}
echo "Deleting backup files older than 2 days" >> ${_TMP_EMAIL}
echo "" >> ${_TMP_EMAIL}
/opt/emc/scripts/clean.sh
echo "Deleted old backup files" >> ${_TMP_EMAIL}
echo "" >> ${_TMP_EMAIL}
fi
       _MAIL_SUB=`echo "${_MAIL_SUB} $partition ($usep%): Available ($avail)"`
  fi
done < ${_DF}

# send an email if the temp_email file has a size greater than 0 bytes.
if [ -s ${_TMP_EMAIL} ]
then
  #cat ${_TMP_EMAIL}
  cat /dev/null > ${_EMAIL}
  echo "Hi," >> ${_EMAIL}
  echo ""  >> ${_EMAIL}
  echo "The below file system(s) are running out of space. Please investigate."  >> ${_EMAIL}
  echo ""  >> ${_EMAIL}
  cat ${_TMP_EMAIL} >> ${_EMAIL}
  echo ""  >> ${_EMAIL}
  echo "Thanks,"  >> ${_EMAIL}
  echo "DBA Team"  >> ${_EMAIL}
  echo ""  >> ${_EMAIL}

  cat ${_EMAIL}

  if [ `cat ${_TMP_EMAIL} |wc -l` -gt 0 ] ; then
     mail -s "Urgent: Almost out of disk space on $(hostname). ${_MAIL_SUB} " cwopsdba@cisco.com < ${_EMAIL}
    _file_chk_cnt=`cat ${_TMP_EMAIL} |grep -v /staging |grep -v /image_ |grep -v /retain_ |grep -v /sg_rman_backup_new |grep -v /db_backup |grep -v /rman_|grep -v /util_ |grep -v /arch_|grep -v /util_ | wc -l`
   if [ $_file_chk_cnt -gt 0 ];
   then
    _pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"
    mesg_str="DB-Alert Critical  Almost out of disk space on $(hostname). ${_MAIL_SUB}"
   mailx -s "$mesg_str " ${_pager_duty}< ${_EMAIL}
   fi
  fi

  C_STATUS="warning"
  C_MSG="Almost out of disk space."

fi
echo "checking inode usage "
### checking Inode
export _DF_INODE=`echo /tmp/df_inode_$$.txt`
export _DF_EMAIL_TMP=`echo /tmp/tmp_email_inode_$$.txt`
export _DF_EMAIL=`echo /tmp/email_inode_$$.txt`
export _THERESHHOLD_INODE=90

df -Hi | grep '%' | grep -vE 'Filesystem|tmpfs' | grep -v "^ " | awk '{ print $4 " " $5 " " $6 }' > ${_DF_INODE}
df -Hi | grep '%' | grep -vE 'Filesystem|tmpfs' | grep "^ " | awk '{ print $3 " " $4 " " $5 }'    >> ${_DF_INODE}
cat ${_DF_INODE} |awk -v _chk_no=$_THERESHHOLD_INODE '{if ((substr($2,1,length($2)-1)+0)>_chk_no) print $3"\t" $1 "\t" $2 }'  >$_DF_EMAIL

if [ -s ${_DF_EMAIL} ]
then
  cat /dev/null > ${_DF_EMAIL_TMP}
  echo "Hi," >> ${_DF_EMAIL_TMP}
  echo ""  >> ${_DF_EMAIL_TMP}
  echo "The below file system(s) are running out of inode Please investigate."  >> ${_DF_EMAIL_TMP}
  echo ""  >> ${_DF_EMAIL_TMP}
  cat ${_DF_EMAIL} >> ${_DF_EMAIL_TMP}
  echo ""  >> ${_DF_EMAIL_TMP}
  echo "Thanks,"  >> ${_DF_EMAIL_TMP}
  echo "DBA Team"  >> ${_DF_EMAIL_TMP}
  echo ""  >> ${_DF_EMAIL_TMP}
  if [ `cat ${_DF_EMAIL} |wc -l` -gt 0 ] ; then
 echo "sending email "
     mail -s "Urgent: File system running almost out of Inode  on $(hostname)" cwopsdba@cisco.com < ${_DF_EMAIL_TMP}
    _ifile_chk_cnt=`cat ${_DF_EMAIL_TMP} |grep -v /staging |grep -v /image_ |grep -v /retain_ |grep -v /sg_rman_backup_new |grep -v /db_backup |grep -v /rman_| wc -l`
   if [ $_ifile_chk_cnt -gt 0 ];
   then
    _pager_duty="ceo-database-impacthigh@ciscospark.pagerduty.com"
    mesg_str="DB-Alert Critical  Almost out of inode  on $(hostname) "
     mailx -s "$mesg_str " ${_pager_duty}< ${_DF_EMAIL_TMP}
   fi
  fi
  C_STATUS="warning"
  C_MSG="Almost out of disk space."
fi


rm -rf ${_DF}

rm -rf ${_TMP_EMAIL}

rm -rf ${_EMAIL}

rm -rf  ${_DF_EMAIL_TMP}
rm -rf ${_DF_EMAIL}