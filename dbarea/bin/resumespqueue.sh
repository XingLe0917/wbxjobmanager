#!/bin/bash

# @(#)resumereplication.sh       15.00 Nov. 2016
# Created by Jing Xu  Email: jingx@cisco.com

case $1 in
pause)
echo "for port 18018 paused at `date +%Y%m%d%H%M%S`">>/u00/app/admin/dbarea/bin/resumespqueue.log
. /sjdbop/shareplex863/bin/.profile_u18018
/sjdbop/shareplex863/bin/sp_ctrl << EOF

port 18018

stop export queue OP_SYS_HITRANS1

stop export queue OP_SYS_HITRANS2

stop export queue OP_SYS_HITRANS3

stop export queue OP_SYS_HITRANS4

stop export queue OP_SYS_HITRANS5

stop export queue OP_SYS_HITRANS6

stop export queue OP_SYS_HITRANS7

stop export queue OP_SYS_HITRANS8

stop export queue OP_SYS_HITRANS9

stop export queue OP_SYS_HITRANS0

quit

EOF

echo "for port 18022 paused at `date +%Y%m%d%H%M%S`">>/u00/app/admin/dbarea/bin/resumespqueue.log
. /sjdbop/shareplex863/bin/.profile_u18022
/sjdbop/shareplex863/bin/sp_ctrl << EOF

port 18022

stop export queue op_Nevtlog_user

quit

EOF

;;

start)
echo "for port 18018 started at `date +%Y%m%d%H%M%S`">>/u00/app/admin/dbarea/bin/resumespqueue.log
. /sjdbop/shareplex863/bin/.profile_u18018
echo 'start export' | /sjdbop/shareplex863/bin/sp_ctrl  >>/u00/app/admin/dbarea/bin/resumespqueue.log 2>&1

echo "for port 18022 started at `date +%Y%m%d%H%M%S`">>/u00/app/admin/dbarea/bin/resumespqueue.log
. /sjdbop/shareplex863/bin/.profile_u18022
echo 'start export' | /sjdbop/shareplex863/bin/sp_ctrl  >>/u00/app/admin/dbarea/bin/resumespqueue.log 2>&1

;;

*) 
 echo "  Not support"
 exit 1

;;

esac
