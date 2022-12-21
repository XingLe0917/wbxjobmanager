import logging
import logging.config
import sys
import os

# from osmetric.FileMonitor import OSWDataMonitor
from common.dbmetricconfig import DBMetricConfig
from job.wbxjobmanager import wbxJobManager
from common.wbxdbconnection import wbxdbconnection
# from biz.wbxdblogger import updateJobManagerInstanceStatus,generateJobInstances, listJobInstances, addSchedulerJob, addListener

logger = None
jobcnt = 0

def init():
    global logger
    jobmanagerconfig = DBMetricConfig()
    logconfigfile = jobmanagerconfig.getLoggerConfigFile()
    logging.config.fileConfig(logconfigfile)
    logger = logging.getLogger("wbxjobmanager")
    logger.info("start process main with pid=%s" % os.getpid())

def verifyDBConnection():
    dbconnection = wbxdbconnection()
    try:
        dbconnection.connect()
        dbconnection.startTransaction()
        dbconnection.verifyConnection()
        dbconnection.commit()
        logger.info("verify depotdb connection info successfully")
    except Exception as e:
        logger.error("verify depotdb connection info failed", exc_info = e)
        dbconnection.rollback()
    finally:
        dbconnection.close()

def start():
    jobmanager = wbxJobManager()
    jobmanager.start()

if __name__ == "__main__":
    init()
    verifyDBConnection()
    start()
