import os
import sys
import traceback
import json
import time
from apscheduler.events import EVENT_JOB_ERROR, EVENT_SCHEDULER_SHUTDOWN, EVENT_JOB_EXECUTED, EVENT_JOB_ADDED, EVENT_JOB_MISSED

from common.wbxexception import wbxDataException, wbxConnectionException
from job.wbxjob import wbxjob
from job.wbxdatabase import wbxdbmanager
from common.dbmetricconfig import DBMetricConfig
from common.wbxdbconnection import wbxdbconnection
import datetime
import subprocess

from job.wbxscheduler import wbxscheduler
import random
import logging
import multiprocessing
import time

logger = logging.getLogger("wbxjobmanager")

# JobManager status is monitored in updateJobManagerInstanceStatus function
# which is triggered by a Timer
commandjobList = []

class wbxJobManager:
    def __init__(self):
        self._schd = wbxscheduler()
        self._pool = multiprocessing.Pool(processes = 10)
        self._dbmanager = wbxdbmanager()
        self._jobdict = {}
        self.jobmanagerconfig = DBMetricConfig()
        self.host_name = self.jobmanagerconfig.getHostname()

    def start(self):
        self.updateJobManagerInstanceStatus()
        joblist = self.listJobInstances()
        if len(joblist) == 0:
            self.generateJobInstances()
            joblist = self.listJobInstances()
            if len(joblist) == 0:
                logger.info("WBXINFO: no job defined for this server. EXIT")
                sys.exit(0)

        # Start subprocess as jobHandler at first, then start APScheduler
        # self._pool.start()
        self._schd.initialize()
        self.addSchedulerJob()
        # monitorruntime = {"minute": "*/1"}
        # self._schd.add_cron_job(func=self.updateJobManagerInstanceStatus, jobid="updateJobManagerInstanceStatus",args=None, **monitorruntime)
        self.addListener()
        self._schd.start()
        self.resetJobNextRuntime()
        while True:
            try:
                time.sleep(60)
                status = self.updateJobManagerInstanceStatus()
                for x in commandjobList:
                    logger.info(x)
                if status == "SHUTDOWN":
                    logger.info("Shutdown completed")
                    break
            except Exception as e:
                logger.error("wbxjobmanager.start with error:", exc_info = e)

    def resetJobNextRuntime(self):
        logger.info("resetJobNextRuntime()")
        jobList = self.listJobInstances()
        dbconnection = wbxdbconnection()
        try:
            dbconnection.connect()
            dbconnection.startTransaction()
            for jobvo in jobList:
                schdjob = self._schd.get_job(jobvo.getCommandstr())
                if schdjob is None:
                    logger.info("The job does not exist in scheduler: %s" % jobvo.getCommandstr())
                else:
                    logger.info("reset job %s next_run_time as %s" % (jobvo.getCommandstr(), schdjob.next_run_time))
                    dbconnection.resetJobNextRuntime(jobvo.getJobid(), schdjob.next_run_time)
                # schdjob = self._schd.get_job(jobvo.getCommandstr())
                # jobvo.setNextRuntime(schdjob.next_run_time)
                # jobvo.setNextRuntime(schdjob.next_run_time)
                # dbconnection.startJobInstance(jobvo.getJobid(), jobvo.getNextRuntime())
            dbconnection.commit()
        except Exception as e:
            dbconnection.rollback()
            logger.error("resetJobNextRuntime ", exc_info=e)
        finally:
            dbconnection.close()

    # https://blog.csdn.net/ybdesire/article/details/82228840
    # According to APscheduler logic, each jobHandler is a seperate thread.
    def jobHandler(self, jobvo):
        logger.info("start job %s" % jobvo.getCommandstr())
        dbconnection = wbxdbconnection()
        try:
            schdjob = self._schd.get_job(jobvo.getCommandstr())
            jobvo.setNextRuntime(schdjob.next_run_time)
            jobvo.setLastRuntime(datetime.datetime.now())
            dbconnection.connect()
            dbconnection.startTransaction()
            dbconnection.startJobInstance(jobvo.getJobid(), jobvo.getNextRuntime())
            dbconnection.commit()
        except Exception as e:
            dbconnection.rollback()
            logger.error("listJobInstances Connection Error occurred ", exc_info=e)
        finally:
            dbconnection.close()

        try:
            self._pool.apply_async(func=processCronjob, args=(jobvo,), callback=cronjob_callback)
        except Exception as e:
            logger.error("Execute job %s failed" % jobvo.getCommandstr(), exc_info = e)


    def updateJobManagerInstanceStatus(self):
        logger.info("updateJobManagerInstanceStatus")
        hostname = self.jobmanagerconfig.getHostname()
        dbconnection = wbxdbconnection()
        status = "RUNNING"
        try:
            try:
                dbconnection.connect()
                dbconnection.startTransaction()
                res = dbconnection.getJobManagerInstance(hostname)
                if res is None:
                    status = "PENDING"
                    paramdict = {"host_name": hostname, "status": status, "opstatus": 0}
                    dbconnection.addJobManagerInstance(**paramdict)
                else:
                    status = res[0]
                    opstatus = res[1]
                    # shutdown
                    if status == "PRE_SHUTDOWN":
                        if self._schd.isrunning():
                            self._schd.shutdown()

                        status = "SHUTDOWN"
                        self._pool.close()
                        logger.info("pool closed")
                        self._pool.join()
                        logger.info("pool removed")
                        opstatus = 0
                    # add job template or add database, shareplex port
                    elif status == "PRE_INITIALIZE":
                        self.generateJobInstances()
                        self.addSchedulerJob()
                        status = "INITIALIZE"
                        opstatus = 0
                    # change job parameter or add new job on a server
                    elif status == "PRE_RELOAD":
                        self.addSchedulerJob()
                        status = "RELOAD"
                        opstatus = 0
                    else:
                        status = "RUNNING"

                    # self._pool.checkStatus()
                    # if status in ('RUNNING', 'PENDING','INITIALIZE','RELOAD'):
                    dbconnection.updateJobManagerInstanceStatus(hostname, opstatus,status)
                dbconnection.commit()
            except wbxDataException as e:
                dbconnection.rollback()
                logger.error("updateJobManagerInstanceStatus DataException occurred", exc_info=e)
            finally:
                dbconnection.close()
        except wbxConnectionException as e:
            logger.error("updateJobManagerInstanceStatus ConnectionException occurred", exc_info=e)
        except Exception as e:
            logger.error("updateJobManagerInstanceStatus Exception occurred", exc_info=e)
        return status
        # updateJobManagerInstanceStatus is called by a individual thread per 60 seconds


    def addSchedulerJob(self):
        jobvolist = self.listJobInstances()
        dbconnection = wbxdbconnection()
        commandstr = None
        try:
            dbconnection.connect()
            dbconnection.startTransaction()
            for jobvo in jobvolist:
                jobid = jobvo.getJobid()
                commandstr = jobvo.getCommandstr()
                # if commandstr == "/u00/app/admin/dbarea/bin/monitor_ha_service.sh":
                #     print(commandstr)
                job_type = jobvo.getJobType()
                job_level = jobvo.getJobLevel()
                status = jobvo.getStatus()
                try:
                    if status == "DELETED":
                        job = self._schd.get_job(jobid=commandstr)
                        if job is not None:
                            self._schd.remove_job(job_id=commandstr)
                            logger.info("Remove job %s, jobruntime=%s" % (commandstr, jobvo.getJobRuntime()))
                    # Failed job should also create job for it, because DBA may fix it and no need to reload
                    # elif status == "FAILED":
                    #     continue
                    elif status == "PAUSE":
                        jobobj = self._schd.get_job(commandstr)
                        if jobobj is not None:
                            jobobj.pause()
                            logger.info("pause job %s, jobruntime=%s" % (commandstr, jobvo.getJobRuntime()))
                    elif status == "RESUME":
                        jobobj = self._schd.get_job(commandstr)
                        if jobobj is not None:
                            jobobj.resume()
                            logger.info("resume job %s, jobruntime=%s" % (commandstr, jobvo.getJobRuntime()))
                        else:
                            jobruntime = json.loads(jobvo.getJobRuntime())
                            job = self._schd.add_cron_job(func=self.jobHandler, jobid=commandstr, args=[jobvo],
                                                          **jobruntime)
                            logger.info("resume job %s, jobruntime=%s" % (commandstr, jobvo.getJobRuntime()))
                    # If a job schedule is changed, then reschedule it
                    elif status == "RESCHEDULE":
                        jobobj = self._schd.get_job(commandstr)
                        if jobobj is not None:
                            self._schd.remove_job(commandstr)
                            logger.info("remove job %s, jobruntime=%s" % (commandstr, jobvo.getJobRuntime()))
                            #jobruntime = json.loads(jobvo.getJobRuntime())
                            #jobobj.reschedule(trigger=jobobj.trigger, **jobruntime)
                            #logger.info("reschedule job %s, jobruntime=%s" % (commandstr, jobvo.getJobRuntime()))

                        jobruntime = json.loads(jobvo.getJobRuntime())
                        job = self._schd.add_cron_job(func=self.jobHandler, jobid=commandstr, args=[jobvo],**jobruntime)
                        logger.info("add job %s, jobruntime=%s" % (commandstr, jobvo.getJobRuntime()))
                    else:
                        # Only load not existed job
                        jobobj = self._schd.get_job(commandstr)
                        if jobobj is None:
                            logger.info("add %s job %s with runtime %s" % (job_type, commandstr, jobvo.getJobRuntime()))

                            try:
                                jobruntime = json.loads(jobvo.getJobRuntime())
                            except ValueError as e:
                                dbconnection.updatejobinstancestatus(jobid, "FAILED",
                                                                "The jobruntime column value must be JSON format")
                                continue

                            for key, value in jobruntime.items():
                                if key not in (
                                "year", "month", "day", "week", "day_of_week", "hour", "minute", "second"):
                                    dbconnection.updatejobinstancestatus(jobid, "FAILED",
                                                                    "The cron job jobruntime column value can only include year/day/month/week/day_of_week/hourminute/second field")
                                    continue
                            job = self._schd.add_cron_job(func=self.jobHandler, jobid=commandstr, args=[jobvo],
                                                          **jobruntime)
                except Exception as e:
                    errormsg = "Error occurred when add the job jobid=%s %s %s" % (jobid, e, traceback.format_exc())
                    logger.error(errormsg)
                    dbconnection.updatejobinstancestatus(jobid, "FAILED", errormsg[-3900:])
            dbconnection.commit()
        except Exception as e:
            logger.error("addSchedulerJob(commandstr=%s) meet error:" % commandstr, exc_info = e)
            dbconnection.rollback()
        finally:
            dbconnection.close()

    '''
    About job runtime
    1. new job generation, it get jobruntime from crontab at first, if not, then get from jobtemplate
    2. For job re-generation, job no change if it already exist even it has different info with jobtemplate.
    3. If there is case that need to change all job runtime, just update the jobruntime with SQL, then update all jobinstance to reload jobs
    
    About job generation
    1. RAC level job only generated on first node of the RAC
    2. Shareplex port level jobs: generate a job for each shareplex port on the server
    3. DB level job only generated on first node of the RAC
    4. Server level job are generated for each server
    '''
    def generateJobInstances(self):
        logger.info("generateJobInstances started")
        # Get job execute time from current 'crontab -l' command
        cronjobdict = self.getCronJobList()
        for commandstr, jobruntime in cronjobdict.items():
            logger.info("commandstr=%s,jobruntime=%s" % (commandstr, jobruntime))

        hostname = self.jobmanagerconfig.getHostname()

        def getJobRuntime(jobinstparam):
            commandlist = jobinstparam["commandstr"].split()
            jobkeys = [commandlist[0]]
            if commandlist[0] == "/staging/datadomain/scripts/dbbackup_Full_s.sh":
                jobkeys.append("/staging/datadomain/scripts/dbbackup_Full.sh")
            elif commandlist[0] == "/staging/datadomain/scripts/dbbackup_Archivelog_s.sh":
                jobkeys.append("/staging/datadomain/scripts/dbbackup_Archivelog.sh")
            elif commandlist[0] == "/u00/app/admin/dbarea/bin/clean_log_trc_12c.sh":
                jobkeys.append("/u00/app/admin/dbarea/bin/clean_log_trc_11g.sh")
            elif commandlist[0] == "/u00/app/admin/dbarea/bin/roll_logs_12c.sh":
                jobkeys.append("/u00/app/admin/dbarea/bin/roll_logs_11g.sh")
            elif commandlist[0] == "/u00/app/admin/dbarea/bin/splex_restart_proc.sh":
                jobkeys.append("/u00/app/admin/dbarea/bin/splex9_restart_proc.sh")

            for jobkey in jobkeys:
                if jobkey in cronjobdict:
                    logger.info("commandstr=%s, templatetime=%s, cronjobtime=%s" % (jobinstparam["commandstr"], jobinstparam["jobruntime"], cronjobdict[jobkey]))
                    jobinstparam["jobruntime"] = cronjobdict[jobkey]
                    break
            else:
                logger.info("commandstr=%s does not get jobruntime from cronjob  with templatetime=%s " % (jobinstparam["commandstr"], jobinstparam["jobruntime"]))
        ###End getJobRunTime function

        dbconnetion = wbxdbconnection()
        try:
            dbconnetion.connect()
            dbconnetion.startTransaction()
            db_vendor = dbconnetion.getDBVendor(self.host_name)
            if db_vendor is None:
                raise wbxDataException("No database on this server %s based on DepotDB data" % hostname)

            # Part jobs only installed on first node of the cluster
            isfirstnode = False
            first_host_name = dbconnetion.getFirstNode(self.host_name)
            if hostname == first_host_name:
                isfirstnode = True
            dblist = dbconnetion.listDatabase(self.host_name)

            src_spportlist = dbconnetion.listSrcShareplexPorts(self.host_name)
            tgt_spportlist = dbconnetion.listTargetShareplexPorts(self.host_name)
            spportlist = src_spportlist[:]

            for tgtspport in tgt_spportlist:
                isexist = False
                for spport in spportlist:
                    if spport["port"] == tgtspport["port"]:
                        isexist = True
                if not isexist:
                    spportlist.append(tgtspport)

            templist = dbconnetion.listJobTemplate(db_vendor)
            for jobtemplate in templist:
                jobinstparam = {"host_name": hostname,
                                "templateid": jobtemplate["templateid"],
                                "jobname": jobtemplate["jobname"],
                                "job_type": jobtemplate["job_type"],
                                "job_level": jobtemplate["job_level"],
                                "jobruntime": jobtemplate["jobruntime"],
                                "status": jobtemplate["status"],
                                "errormsg": ""}

                if jobtemplate["job_level"] == "SHAREPLEXPORT":
                    for spport in spportlist:
                        if jobtemplate["appln_support_code"] is not None:
                            applncodelist = jobtemplate["appln_support_code"].split(',')
                            if spport["appln_support_code"] not in applncodelist:
                                continue
                        if jobtemplate["application_type"] is not None and jobtemplate["application_type"] != spport["application_type"]:
                            continue
                        if jobtemplate["db_type"] is not None and jobtemplate["db_type"] != spport["db_type"]:
                            continue

                        if jobtemplate["parameter"] is None or jobtemplate["parameter"] == "":
                            commandstr = jobtemplate["filename"]
                        else:
                            jobparameter = jobtemplate["parameter"].replace("<PORT>", "%s" % spport["port"])
                            commandstr = "%s %s" % (jobtemplate["filename"], jobparameter)

                        jobinstparam["commandstr"] = commandstr
                        getJobRuntime(jobinstparam)
                        dbconnetion.addjobinstance(jobinstparam)
                        logger.info("Generate job with jobname=%s, commandstr=%s" % (
                        jobinstparam["jobname"], jobinstparam["commandstr"]))
                elif jobtemplate["job_level"] == "SRC_SHAREPLEXPORT":
                    for spport in src_spportlist:
                        if jobtemplate["appln_support_code"] is not None:
                            applncodelist = jobtemplate["appln_support_code"].split(',')
                            if spport["appln_support_code"] not in applncodelist:
                                continue

                            # if jobtemplate["APPLN_SUPPORT_CODE"] is not None and jobtemplate["APPLN_SUPPORT_CODE"] != spport["APPLN_SUPPORT_CODE"]:
                            #     continue
                            if jobtemplate["application_type"] is not None and jobtemplate["application_type"] != \
                                    spport["application_type"]:
                                continue
                            if jobtemplate["db_type"] is not None and jobtemplate["db_type"] != spport["db_type"]:
                                continue

                            if jobtemplate["parameter"] is None or jobtemplate["parameter"] == "":
                                commandstr = jobtemplate["filename"]
                            else:
                                jobparameter = jobtemplate["parameter"].replace("<PORT>", "%s" % spport["port"])
                                commandstr = "%s %s" % (jobtemplate["filename"], jobparameter)

                            jobinstparam["commandstr"] = commandstr
                            getJobRuntime(jobinstparam)
                            dbconnetion.addjobinstance(jobinstparam)
                            logger.info("Generate job with jobname=%s, commandstr=%s" % (
                            jobinstparam["jobname"], jobinstparam["commandstr"]))
                elif jobtemplate["job_level"] == "INSTANCE":
                    for dbinst in dblist:
                        if jobtemplate["appln_support_code"] is not None:
                            applncodelist = jobtemplate["appln_support_code"].split(',')
                            if dbinst["appln_support_code"] not in applncodelist:
                                continue
                        if jobtemplate["application_type"] is not None and jobtemplate["application_type"] != dbinst["application_type"]:
                            continue
                        if jobtemplate["db_type"] is not None and jobtemplate["db_type"] != dbinst["db_type"]:
                            continue

                        if jobtemplate["parameter"] is None or jobtemplate["parameter"] == "":
                            commandstr = jobtemplate["filename"]
                        else:
                            jobparameter = jobtemplate["parameter"].replace("<INSTANCE_NAME>", dbinst["instance_name"])
                            commandstr = "%s %s" % (jobtemplate["filename"], jobparameter)

                        jobinstparam["commandstr"] = commandstr
                        getJobRuntime(jobinstparam)
                        dbconnetion.addjobinstance(jobinstparam)
                        logger.info("Generate job with jobname=%s, commandstr=%s" % (
                        jobinstparam["jobname"], jobinstparam["commandstr"]))
                elif jobtemplate["job_level"] == "SERVER":
                    if jobtemplate["parameter"] is None or jobtemplate["parameter"] == "":
                        commandstr = jobtemplate["filename"]
                    else:
                        commandstr = "%s %s" % (jobtemplate["filename"], jobtemplate["parameter"])
                    jobinstparam["commandstr"] = commandstr
                    getJobRuntime(jobinstparam)
                    dbconnetion.addjobinstance(jobinstparam)
                    logger.info("Generate job with jobname=%s, commandstr=%s" % (
                    jobinstparam["jobname"], jobinstparam["commandstr"]))
                elif jobtemplate["job_level"] == "DATABASE":
                    if isfirstnode:
                        for dbinst in dblist:
                            if jobtemplate["appln_support_code"] is not None:
                                applncodelist = jobtemplate["appln_support_code"].split(',')
                                if dbinst["appln_support_code"] not in applncodelist:
                                    continue

                            if jobtemplate["application_type"] is not None and jobtemplate["application_type"] != \
                                    dbinst["application_type"]:
                                continue
                            if jobtemplate["db_type"] is not None and jobtemplate["db_type"] != dbinst["db_type"]:
                                continue

                            if jobtemplate["parameter"] is None or jobtemplate["parameter"] == "":
                                commandstr = jobtemplate["filename"]
                            else:
                                jobparameter = jobtemplate["parameter"].replace("<DB_NAME>", dbinst["db_name"])
                                jobparameter = jobparameter.replace("<INSTANCE_NAME>", dbinst["instance_name"])
                                commandstr = "%s %s" % (jobtemplate["filename"], jobparameter)

                            jobinstparam["commandstr"] = commandstr
                            getJobRuntime(jobinstparam)
                            dbconnetion.addjobinstance(jobinstparam)
                            logger.info("Generate job with jobname=%s, commandstr=%s" % (
                            jobinstparam["jobname"], jobinstparam["commandstr"]))
                elif jobtemplate["job_level"] == "RAC":
                    isrequired = False
                    if isfirstnode:
                        if jobtemplate["appln_support_code"] is not None:
                            for dbinst in dblist:
                                applncodelist = jobtemplate["appln_support_code"].split(',')
                                if dbinst["appln_support_code"] not in applncodelist:
                                    continue
                                else:
                                    isrequired = True
                        else:
                            isrequired = True

                        if isrequired:
                            if jobtemplate["parameter"] is not None:
                                commandstr = "%s %s" % (jobtemplate["filename"], jobtemplate["parameter"])
                            else:
                                commandstr = jobtemplate["filename"]
                            jobinstparam["commandstr"] = commandstr
                            getJobRuntime(jobinstparam)
                            dbconnetion.addjobinstance(jobinstparam)
                            logger.info("Generate job with jobname=%s, commandstr=%s" % (
                                jobinstparam["jobname"], jobinstparam["commandstr"]))

            dbconnetion.commit()
        except Exception as e:
            dbconnetion.rollback()
            logger.error("GenerateJobInstance met error", exc_info = e)
            raise e
        finally:
            dbconnetion.close()

    def listJobInstances(self):
        jobvolist = []
        dbconnection = wbxdbconnection()
        try:
            dbconnection.connect()
            dbconnection.startTransaction()
            rowlist = dbconnection.listJobInstances(self.host_name)
            for row in rowlist:
                jobvolist.append(
                    wbxjob(row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10],row[11]))
            dbconnection.commit()
        except Exception as e:
            dbconnection.rollback()
            logger.error("listJobInstances Connection Error occurred ", exc_info = e)
        finally:
            dbconnection.close()
        return jobvolist

    def getCronJobList(self):
        jobdict = {}
        itemdefs = {0: "minute", 1: "hour", 2: "day", 3: "month", 4: "day_of_week"}
        lines = os.popen('crontab -l').readlines()
        for line in lines:
            stripline = line.strip()
            if stripline != "" and stripline.find('#') == -1:
                jobitems = line.split()
                logger.info("Cronjob: %s" % line)
                runtimedict = {}
                for itemind, itemname in itemdefs.items():
                    itemvalue = jobitems[itemind]
                    if itemvalue != "*":
                        if itemname == "day_of_week" and itemvalue.replace(",", "").replace(" ", "").isdigit():
                            itemvallist = itemvalue.split(",")
                            sitemvallist = [str((int(itemval) + 6) % 7) for itemval in itemvallist]
                            itemvalue = ",".join(sitemvallist)
                        elif itemvalue.isdigit():
                            itemvalue = int(itemvalue)
                        runtimedict[itemname] = itemvalue
                commandstr = jobitems[5]
                # If a job is configured mutiple times, then it get the first job's run time
                if commandstr not in jobdict:
                    jobdict[commandstr] = json.dumps(runtimedict)
        return jobdict

    # This method only generate job instance from job template
    # After this function executed, all jobs can be PENDING or DELETED, previous status will be covered

    def listenerHandler(self,event):
        if event.code == EVENT_JOB_ERROR:
            logger.error("listenerHandler: Error occurred when executing job %s" % event.job_id)
        elif event.code == EVENT_JOB_EXECUTED:
            logger.info("listenerHandler: job executed with jobid=%s" % event.job_id)
        elif event.code == EVENT_JOB_ADDED:
            logger.info("listenerHandler: job added with jobid=%s" % event.job_id)
        elif event.code == EVENT_JOB_MISSED:
            logger.error(event)
            logger.info("listenerHandler: job missed with jobid=%s" % event.job_id)
        elif event.code == EVENT_SCHEDULER_SHUTDOWN:
            logger.info("listenerHandler: shutdown scheduler")

    def addListener(self):
        logger.info("addListener for EVENT_JOB_ERROR | EVENT_SCHEDULER_SHUTDOWN | EVENT_JOB_EXECUTED | EVENT_JOB_ADDED | EVENT_JOB_MISSED")
        self._schd.add_listener(self.listenerHandler,EVENT_JOB_ERROR | EVENT_SCHEDULER_SHUTDOWN | EVENT_JOB_EXECUTED | EVENT_JOB_ADDED | EVENT_JOB_MISSED)

## Do not add logger output in this function
def processCronjob(jobvo):
    commandstr = jobvo.getCommandstr()
    try:
        filename = commandstr.split()[0]
        jobvo.setStatus("SUCCEED")
        jobvo.setErrormsg("")

        if not os.path.isfile(filename):
            jobvo.setStatus("FAILED")
            jobvo.setErrormsg('The shell file %s does not exist on current server' % filename)
        else:
            jobvo.setStatus("SUCCEED")
            jobvo.setErrormsg("")
            p = subprocess.Popen(args=[commandstr], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 bufsize=-1)
            output, error = p.communicate()
            if p.returncode == 0:
                jobvo.setStatus("SUCCEED")
                jobvo.setErrormsg("")
            else:
                msg = "Job %s failed with returncode=%s output message %s" % (p.returncode, commandstr, output)
                if error:
                    msg = "%s %s" % (msg, error)
                jobvo.setStatus("FAILED")
                jobvo.setErrormsg(msg[-3990:])

    except Exception as e:
        msg = "Job %s failed with Exception msg: %s" % (commandstr, traceback.format_exc())
        # logger.error(msg, exc_info = e)
        jobvo.setStatus("FAILED")
        jobvo.setErrormsg(msg[-3990:])
    return jobvo

    # try:
    #     if connect is None:
    #         connect = cx_Oracle.connect(connectionurl)
    #     cursor = connect.cursor()
    #     SQL = ''' UPDATE wbxjobinstance SET status=:status, errormsg=:errormsg  WHERE jobid=:jobid and status not in ('PAUSE','DELETED') '''
    #     paramdict = {"status": jobvo.getStatus(), "jobid": jobvo.getJobid(), "errormsg": jobvo.getErrormsg()}
    #     cursor.execute(SQL, paramdict)
    #     connect.commit()
    # except Exception as e:
    #     if connect is not None:
    #         connect.rollback()
    #     logger.error("end job failed with jobid=%s" % jobvo.getCommandstr(), exc_info=e)
    # finally:
    #     if connect is not None:
    #         connect.close()
    # logger.info("job executed completed comamdnstr=%s, status=%s" % (jobvo.getCommandstr(), jobvo.getStatus()))
    # return jobvo

def cronjob_callback(jobvo):
    logger.info("job executed completed comamdnstr=%s, status=%s" % (jobvo.getCommandstr(), jobvo.getStatus()))
    dbconnection = wbxdbconnection()
    try:
        dbconnection.connect()
        dbconnection.startTransaction()
        dbconnection.updatejobinstancestatus(jobvo.getJobid(), jobvo.getStatus(), jobvo.getErrormsg())
        dbconnection.commit()
    except Exception as e:
        dbconnection.rollback()
        logger.error("listJobInstances Connection Error occurred ", exc_info=e)
    finally:
        dbconnection.close()
