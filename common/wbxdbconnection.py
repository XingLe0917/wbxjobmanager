import logging
import traceback
import  cx_Oracle
from cx_Oracle import DatabaseError, DataError
from common.dbmetricconfig import DBMetricConfig
from threading import Lock, current_thread
from common.singleton import Singleton
from sqlalchemy import create_engine
from sqlalchemy.pool import NullPool
from sqlalchemy.orm import Session, sessionmaker
import threading
from common.wbxexception import wbxDataException, wbxConnectionException
from common.wbxutil import wbxutil

logger = logging.getLogger("wbxjobmanager")

# create one pool for all instances, max 3 connections. if exceed 3 instances, will block more connections
# This class should not cover up exception, it can only wrap exception and throw out again
# Because cx_Oracle does not split Connection error and SQL error, so we should do it
class wbxdbconnection(object):
    _lock = Lock()
    _engine = None
    # If maxconnections is not set, then connection will be built as required
    # maxcached only guarantee the Idle connections, means if there are 10 connections,but maxcached is 2, then 8 connection will be stopped

    def __init__(self):
        self.threadlocal = threading.local()
        self.threadlocal.isTransactionStart = False
        self.session = None

    def connect(self):
        with self._lock:
            if wbxdbconnection._engine is None:
                # username, pwd, connectionurl = "depot","depot","(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=10.252.8.105)(PORT=1701))(ADDRESS=(PROTOCOL=TCP)(HOST=10.252.8.106)(PORT=1701))(ADDRESS=(PROTOCOL=TCP)(HOST=10.252.8.107)(PORT=1701))(LOAD_BALANCE=yes)(FAILOVER=on)(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=auditdbha.webex.com)(FAILOVER_MODE=(TYPE=SELECT)(METHOD=BASIC)(RETRIES=3)(DELAY=5))))"
                username, pwd, connectionurl = DBMetricConfig().getDepotDBConnectionurl()
                wbxdbconnection._engine = create_engine('oracle+cx_oracle://%s:%s@%s' % (username, pwd, connectionurl), pool_recycle=600,
                               pool_size=5, max_overflow=0, echo=False)
            if self.session is None:
                sessionclz = sessionmaker(bind=wbxdbconnection._engine , expire_on_commit=True)
                self.session = sessionclz()
                self.verifyConnection()


    def getDBVendor(self, host_name):
        SQL = ''' SELECT distinct di.db_vendor FROM instance_info ii, database_info di 
                  WHERE ii.host_name=:host_name 
                  AND di.db_type in ('PROD','BTS_PROD') 
                  AND ii.db_name=di.db_name 
                  AND ii.trim_host=di.trim_host '''
        row = self.session.execute(SQL, {"host_name": host_name}).fetchone()
        if row is not None:
            return row[0]
        return None

    def getFirstNode(self, host_name):
        SQL = ''' select min(host_name) keep (dense_rank first order by host_name) from host_info
                  where (nvl(scan_name,'NULL'),trim_host) 
                       in ( select nvl(scan_name,'NULL'),trim_host from host_info where host_name=:host_name) '''
        row = self.session.execute(SQL, {"host_name": host_name}).fetchone()
        if row is not None:
            return row[0]
        return None

    def listDatabase(self, host_name):
        SQL = ''' SELECT di.db_name,ii.instance_name,di.appln_support_code, di.db_type, di.application_type
                  FROM instance_info ii, database_info di 
                  WHERE ii.host_name=:host_name 
                  AND di.db_type in ('PROD','BTS_PROD') 
                  AND ii.db_name=di.db_name 
                  AND ii.trim_host=di.trim_host '''
        rows = self.session.execute(SQL, {"host_name": host_name}).fetchall()
        return [dict(row) for row in rows]

    def listSrcShareplexPorts(self, host_name):
        SQL = ''' SELECT  distinct SI.PORT,DI.APPLN_SUPPORT_CODE, DI.DB_TYPE, DI.APPLICATION_TYPE 
                  FROM shareplex_info si, instance_info ii, database_info di 
                  WHERE si.src_host=:host_name 
                  AND di.db_type in ('PROD','BTS_PROD') 
                  AND si.src_host=ii.host_name 
                  AND si.src_db=ii.db_name 
                  AND ii.db_name=di.db_name 
                  AND ii.trim_host=di.trim_host '''
        rows = self.session.execute(SQL, {"host_name": host_name}).fetchall()
        return [dict(row) for row in rows]

    def listTargetShareplexPorts(self, host_name):
        SQL = ''' SELECT  distinct SI.PORT,DI.APPLN_SUPPORT_CODE, DI.DB_TYPE, DI.APPLICATION_TYPE 
                  FROM shareplex_info si, instance_info ii, database_info di 
                  WHERE si.tgt_host=:host_name 
                  AND di.db_type in ('PROD','BTS_PROD') 
                  AND si.tgt_host=ii.host_name 
                  AND si.tgt_db=ii.db_name 
                  AND ii.db_name=di.db_name 
                  AND ii.trim_host=di.trim_host '''
        rows = self.session.execute(SQL, {"host_name": host_name}).fetchall()
        return [dict(row) for row in rows]

    def getJobManagerInstance(self, host_name):
        SQL = "SELECT status,opstatus FROM wbxjobmanagerinstance WHERE host_name=:host_name"
        row = self.session.execute(SQL, {"host_name": host_name}).fetchone()
        return row

    def listJobTemplate(self, db_vendor):
        SQL = ''' SELECT templateid, jobname, job_level,appln_support_code,application_type,db_type,db_names,job_type,
                         filename,parameter,jobruntime,decode(status,'VALID','PENDING','DELETED') as status,description 
                  FROM wbxjobtemplate WHERE db_vendor=:db_vendor  AND osversion='RHEL7' '''
        rows = self.session.execute(SQL, {"db_vendor": db_vendor}).fetchall()
        return [dict(row) for row in rows]

    def addJobManagerInstance(self, **kwargs):
        SQL = "INSERT INTO wbxjobmanagerinstance(host_name, status, opstatus, lastupdatetime) VALUES(:host_name, :status, :opstatus, sysdate)"
        self.session.execute(SQL, kwargs)

    def updateJobManagerInstanceStatus(self, host_name, opstatus, status):
        SQL = "UPDATE wbxjobmanagerinstance SET status=case when :status='RUNNING' and opstatus=1 then status else :status end, opstatus=case when :status = 'RUNNING' and opstatus=1 then opstatus else :opstatus end, lastupdatetime=sysdate WHERE host_name=:host_name"
        self.session.execute(SQL, {"host_name":host_name,"opstatus":opstatus,"status":status})

    def listJobInstances(self, host_name):
        SQL = "SELECT jobid, templateid, host_name, jobname, job_type, job_level, commandstr, jobruntime, status, errormsg,last_run_time, next_run_time FROM wbxjobinstance WHERE host_name=:host_name"
        paramdict = {"host_name": host_name}
        joblist =self.session.execute(SQL,  paramdict).fetchall()
        return joblist

    def resetJobNextRuntime(self, jobid, next_run_time):
        SQL = "UPDATE wbxjobinstance SET next_run_time=:next_run_time WHERE jobid=:jobid and status != 'PENDING'"
        paramdict = {"jobid": jobid, "next_run_time": next_run_time}
        self.session.execute(SQL, paramdict)

    def startJobInstance(self, jobid, next_run_time):
        SQL = "UPDATE wbxjobinstance SET status='RUNNING', last_run_time=:last_run_time, next_run_time=:next_run_time WHERE jobid=:jobid"
        paramdict = {"jobid": jobid, "last_run_time": wbxutil.getcurrenttime(), "next_run_time":next_run_time}
        self.session.execute(SQL, paramdict)

    def addjobinstance(self, jobparam):
        SQL = "SELECT jobid, templateid, host_name, jobname, commandstr, jobruntime, status, errormsg FROM wbxjobinstance WHERE host_name=:host_name AND commandstr=:commandstr"
        paramdict = {"host_name": jobparam["host_name"], "commandstr": jobparam["commandstr"]}
        row = self.session.execute(SQL, paramdict).fetchone()
        if row is None:
            insertSQL = "INSERT INTO wbxjobinstance(jobid, templateid, host_name, jobname, job_type, job_level, commandstr, jobruntime, status,errormsg) VALUES(SYS_GUID(), :templateid, :host_name, :jobname, :job_type, :job_level, :commandstr, :jobruntime, :status, :errormsg)"
            self.session.execute(insertSQL, jobparam)

    def updatejobinstancestatus(self,jobid, status, errormsg):
        SQL = ''' UPDATE wbxjobinstance SET status=:status, errormsg=:errormsg  WHERE jobid=:jobid and status not in ('PAUSE','DELETED') '''
        paramdict = {"status": status, "jobid": jobid, "errormsg": errormsg}
        self.session.execute(SQL, paramdict)

    def startTransaction(self):
        with self._lock:
            if self.threadlocal.isTransactionStart:
                raise wbxConnectionException("Already has another running transaction")
            self.threadlocal.isTransactionStart = True

    def commit(self):
        try:
            self.session.commit()
        except Exception as e:
            self.session = None
            self._engine = None

    def rollback(self):
        try:
            self.session.rollback()
        except Exception as e:
            self.session = None
            self._engine = None

    def close(self):
        try:
            self.session.close()
        except Exception as e:
            self.session = None
            self._engine = None

    def verifyConnection(self):
        SQL = "SELECT 1 FROM dual"
        self.session.execute(SQL)


