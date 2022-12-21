#!/bin/sh

##########################################################################
#
#  NOTE
#    1. Add step to call STAP API to send out the script running status.
#    2. Change to get "emctl" from "ps", instead of hard-coding.
# 
#  MODIFIED     (MM/DD/YY)
#    Edwin         03/20/2018 - Change the replace method to get EMCTL.
#    Edwin         02/28/2018 - Change to call STAP API with Python.
#    Edwin         10/11/2017 - Add the STAP API calling.
# 
##########################################################################

############################## for STAP API call using.
START_TIME=`date "+%F %T"`
C_ID=""
C_STATUS="success"
C_MSG=""


## agent the grid agent status.
TMP=`ps -aef | grep agent | grep emwd.pl | grep -v grep | awk {'print $9'}`
CMD_EMCTL=""

if [ "X${TMP}" = "X" ] 
then
  # agent not run. we need make sure that the default agent command is there.
  if [ -s "/u00/app/oracle/product/agent12c/core/12.1.0.5.0/bin/emctl" ] 
  then 
    CMD_EMCTL="/u00/app/oracle/product/agent12c/core/12.1.0.5.0/bin/emctl"
  fi

  if [ -s "/u00/app/oracle/product/11.2.0/agent11g/core/12.1.0.5.0/bin/emctl" ] 
  then 
    CMD_EMCTL="/u00/app/oracle/product/11.2.0/agent11g/core/12.1.0.5.0/bin/emctl"
  fi

  if [ -s "/u00/app/oracle/product/agent_13c1/agent_13.4.0.0.0/bin/emctl" ]
  then
    CMD_EMCTL="/u00/app/oracle/product/agent_13c1/agent_13.4.0.0.0/bin/emctl"
  fi
  
  if [ -s "/u00/app/oracle/product/agent13c1/agent_13.4.0.0.0/bin/emctl" ]
  then
    CMD_EMCTL="/u00/app/oracle/product/agent13c1/agent_13.4.0.0.0/bin/emctl"
  fi
  

  if [ "X${CMD_EMCTL}" = "X" ] 
  then 
    # the default emctl is not there.
    C_STATUS="fail"
    C_MSG="the default location of emctl not exist."
    echo "==== Not found the emctl at the default location."
  fi
else
  # check the emctl command and get status.
  CMD_EMCTL=${TMP/%emwd.pl/emctl}
fi

# run the agent status checking.
if [ "X${CMD_EMCTL}" != "X" ] 
then
  ret=`${CMD_EMCTL} status agent | grep -wc "Agent is Running and Ready"`

  if [ ${ret} -lt 1 ] 
  then
    C_STATUS="warning"
    C_MSG="start the grid agent."
    ${CMD_EMCTL} start agent > /tmp/gridagentstatus
    mailx -s " Grid Control Agent Not Running,Restarted" cwopsdba@cisco.com < /tmp/gridagentstatus
  fi
fi



