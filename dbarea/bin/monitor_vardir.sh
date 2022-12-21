#!/bin/sh

##########################################################################
#
#  NOTE
#    Add step to call STAP API to send out the script running status.
# 
#  MODIFIED     (MM/DD/YY)
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/12/2017 - Add the STAP API calling.
# 
##########################################################################

############################## for STAP API call using.
START_TIME=`date "+%F %T"`
C_ID="$1"
C_STATUS="success"
C_MSG=""

call_stap() {
  END_TIME=`date "+%F %T"`
  
  C_DATA="{\"host\": \"${HOSTNAME}\", \"name\": \"$0\", \"start_time\": \"${START_TIME}\", \"end_time\": \"${END_TIME}\", \"status\": \"${C_STATUS}\", \"msg\": \"${C_MSG}\", \"id\": \"${C_ID}\"}"
  C_OUT=`/u00/app/admin/dbarea/bin/call_stap_api.py "${C_DATA}"`
  
  if [ ${C_OUT} = '{"result":"OKOKOK"}' ]
  then
    echo "==== call STAP API success."
  else
    echo "==== call STAP API fail."
  fi
}
############################## END.

# get the shareplex product directory of all the running ports.

_host_name="`hostname | cut -d'.' -f1`"

_1BY=1
_1KB=$((${_1BY}*1024))
_1MB=$((${_1KB}*1024))
_1GB=$((${_1MB}*1024))

#_THRESHOLD_SIZE=${_1GB}          # 1.0GB; value in Bytes
#_THRESHOLD_SIZE=$((${_1GB}*2))    # 2.0GB; value in Bytes
_THRESHOLD_SIZE=$((${_1GB}*12))    # 12.0GB; value in Bytes
#_THRESHOLD_SIZE=$((${_1GB}/2))   # 0.5GB; value in Bytes

_THRESHOLD_SIZE_DISPLAY=`echo ${_THRESHOLD_SIZE} | awk '{split( "B K M G" , v ); s=1; while( $1>1024 ){ $1/=1024; s++ } print int($1)""v[s]}'`

TMPFILE0=/tmp/vardir_00
TMPFILE1=/tmp/vardir_01
TMPFILE2=/tmp/vardir_02
TMPFILE3=/tmp/vardir_03
TMPFILE4=/tmp/vardir_04
TMPFILE5=/tmp/vardir_05

EMAIL_FILE=/tmp/email_vardir.txt

EMAIL_ALIAS=cwopsdba@cisco.com
#EMAIL_ALIAS=bsusaima@cisco.com

cat /dev/null > ${TMPFILE0}
cat /dev/null > ${TMPFILE1}
cat /dev/null > ${TMPFILE2}
cat /dev/null > ${TMPFILE3}
cat /dev/null > ${TMPFILE4}
cat /dev/null > ${TMPFILE5}
cat /dev/null > ${EMAIL_FILE}

_os=`uname -s`
case ${_os} in
  "SunOS")
      /usr/ucb/ps wwxa | grep sp_ | grep -v grep | grep -v sp_ctrl | grep -v splex_action | grep -v sp_mport | awk '{print $6$7" "$5}' | grep "^-" | awk -F'/' '{for(i=1;i<=NF-2;i++){printf("%s/", $i);} print "\n"; }' | grep -v '^$' | cut -d'-' -f2 | cut -c2- > ${TMPFILE0}
      /usr/ucb/ps wwxa | grep sp_ | grep -v grep | grep -v sp_ctrl | grep -v splex_action | grep sp_mport | awk '{print $8$9" "$5}' | grep "^-" | awk -F'/' '{for(i=1;i<=NF-2;i++){printf("%s/", $i);} print "\n"; }' | grep -v '^$' | cut -d'-' -f2 | cut -c2-   >> ${TMPFILE0}
      ;;
  "Linux")
      ps -ef | grep sp_ | grep -v grep | grep -v sp_ctrl | grep -v splex_action | grep -v sp_mport | awk '{print $9$10" "$8}' | grep "^-" | awk -F'/' '{for(i=1;i<=NF-2;i++){printf("%s/", $i);} print "\n"; }' | grep -v '^$' | awk -F'-u' '{for(i=2;i<=NF;i++) print $i}'  > ${TMPFILE0}
      ps -ef | grep sp_ | grep -v grep | grep -v sp_ctrl | grep -v splex_action | grep sp_mport | awk '{print $11" "$8}' | grep "^-" | awk -F'/' '{for(i=1;i<=NF-2;i++){printf("%s/", $i);} print "\n"; }' | grep -v '^$' | awk -F'-u' '{for(i=2;i<=NF;i++) print $i}'      >> ${TMPFILE0}
esac

# get the unique product directory
cat ${TMPFILE0} | awk '{print $2}' | sort -u > ${TMPFILE1}

# get all the shareplex vardir mount point
if [ -s ${TMPFILE1} ]; then

  cat ${TMPFILE1} | while read _prod_dir
  do
    # get all the shareplex vardir's mount point
    grep SP_SYS_VARDIR ${_prod_dir}/bin/.profile_u* | awk -F':' '{print $2}' | grep -v "^export" | awk -F';' '{print$1}' | awk -F'=' '{print $2}' | awk -F'/' '{for(i=1;i<=NF-1;i++){printf("%s/", $i);} print "\n"; }' | grep -v '^$' >> ${TMPFILE2}
  done

  # get the unique shareplex vardir mount point
  cat ${TMPFILE2} | sort -u > ${TMPFILE3}

  # find the size of the vardir
  cat ${TMPFILE3} | while read _mnt_point
  do
    du -sh ${_mnt_point}/vardir* 2> /dev/null | grep -v "tar" >> ${TMPFILE4}
    #du -sk ${_mnt_point}/vardir* 2> /dev/null | grep -v "tar" >> ${TMPFILE4}
  done

  # check for vardir size > the threshold_size
#  cat ${TMPFILE4} | awk -v t=${_THRESHOLD_SIZE} '{
#    _bytes=$1*1024;
#    if( _bytes > t) {
#      printf("%s%5f%s\n", $2" (", $1/1024/1024, " GB)" );
#    }
#  }' > ${TMPFILE5}

  cat ${TMPFILE4} | awk -v t=${_THRESHOLD_SIZE} '{
    split( "K M G" , v );
    s=$1;
    l=length(s);
    l_c=substr(s, l, 1);
    #print s" "l" "l_c;
    val=s;
    if ( strtonum(l_c) != l_c ) {
      # last char is a alphabet
      if ( l_c == v[1] ) {
        #print "is NOT numeric: "l_c;
        val*=1024 ;
      } else {
        if ( l_c == v[2] ) {
          #print "is NOT numeric: "l_c;
          val*=1024*1024 ;
        } else {
          if ( l_c == v[3] ) {
            #print "is NOT numeric: "l_c;
            val*=1024*1024*1024 ;
          }
        }
      }
    }
    #print "val="val ;
    if ( val > t ) {
      print $2" ("s")";
    }
  }' > ${TMPFILE5}

  # send the email
  if [ -s "${TMPFILE5}" ]; then
    echo "Hi, " >> ${EMAIL_FILE}
    echo "" >> ${EMAIL_FILE}
    echo "The below vardir(s) size on ${_host_name} are greater than ${_THRESHOLD_SIZE_DISPLAY}. Please veriy." >> ${EMAIL_FILE}
    echo "" >> ${EMAIL_FILE}
    cat "${TMPFILE5}" >> ${EMAIL_FILE}
    echo "" >> ${EMAIL_FILE}
    echo "~DBA Team." >> ${EMAIL_FILE}

    cat ${EMAIL_FILE}
    mailx -s "Urgent!! Vardir size on ${_host_name} is greater than ${_THRESHOLD_SIZE_DISPLAY}." ${EMAIL_ALIAS} < ${EMAIL_FILE}

    C_STATUS="warning"
    C_MSG="Vardir size is greater than ${_THRESHOLD_SIZE_DISPLAY}."

  fi
#else
#  echo "${_msg_static}::::::NO SPLEX RUNNING"
fi

##########################################################################
# call STAP API.
##########################################################################
call_stap


