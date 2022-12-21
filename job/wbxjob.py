class wbxjob:
    def __init__(self, jobid, templateid, host_name, jobname, job_type, job_level, commandstr, jobruntime, status, errormsg, next_run_time, last_run_time):
        self._jobid = jobid
        self._tempalteid = templateid
        self._host_name = host_name
        self._jobname = jobname
        self._job_type = job_type
        self._job_level = job_level
        self._commandstr = commandstr
        self._jobruntime = jobruntime
        self._status = status
        self._errormsg = errormsg
        self._next_run_time = next_run_time
        self._last_run_time = last_run_time

    def toJsonForUpdate(self):
        return {"jobname":self._jobname,"templateid":self._tempalteid,"job_type":self._job_type,"jobruntime":self._jobruntime,
                "status":self._status,"errormsg":self._errormsg,"host_name": self._host_name, "commandstr": self._commandstr}

    def toJsonForInsert(self):
        return {"templateid": self._tempalteid, "host_name": self._host_name, "jobname": self._jobname,
                "job_type": self._job_type, "commandstr": self._commandstr, "jobruntime": self._jobruntime,
                "status": self._status,"errormsg": self._errormsg}

    def getHostName(self):
        return self._host_name

    def getJobid(self):
        return self._jobid

    def setCommandstr(self,commandstr):
        self._commandstr = commandstr

    def getCommandstr(self):
        return self._commandstr

    def getJobRuntime(self):
        return self._jobruntime

    def setJobRuntime(self, jobruntime):
        self._jobruntime = jobruntime

    def getJobType(self):
        return self._job_type

    def getJobLevel(self):
        return self._job_level

    def setStatus(self, status):
        self._status = status

    def getStatus(self):
        return self._status

    def getNextRuntime(self):
        return self._next_run_time

    def setNextRuntime(self, nextruntime):
        self._next_run_time = nextruntime

    def getLastRuntime(self):
        return self._last_run_time

    def setLastRuntime(self, lastruntime):
        self._last_run_time = lastruntime

    def getJobName(self):
        return self._jobname

    def getErrormsg(self):
        return self._errormsg

    def setErrormsg(self,errormsg):
        self._errormsg = errormsg

    def getTemplateid(self):
        return self._tempalteid

    def getDBName(self):
        if self._job_level == "INSTANCE":
            db_name = self._commandstr.split()[1][0:-1].upper()
        elif self._job_level == "DATABASE":
            db_name = self._commandstr.split()[1]
        else:
            db_name = ""
        return db_name


