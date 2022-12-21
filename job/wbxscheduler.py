from pytz import utc
import logging

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.executors.pool import ThreadPoolExecutor

logger = logging.getLogger("wbxjobmanager")

class wbxscheduler:

    def __init__(self):
        self._scheduler = None

    def isrunning(self):
        if self._scheduler is not None:
            return self._scheduler.running
        else:
            return False

    def shutdown(self, wait = True):
        self._scheduler.shutdown(wait=wait)

    def initialize(self):
        self._scheduler = BackgroundScheduler({
            'apscheduler.executors.default': {
                'class': 'apscheduler.executors.pool:ThreadPoolExecutor',
                'max_workers': '10'
            },
            'apscheduler.job_defaults.coalesce': 'true',
            'apscheduler.job_defaults.max_instances': '1',
            'apscheduler.job_defaults.misfire_grace_time': '30'
        }, timezone=utc, daemon=False, logger=logger)

    def start(self):
        self._scheduler.start()

    def pause(self, jobid):
        jobobj = self.get_job(jobid)
        logger.info("Pause job %s" % jobobj.name)
        jobobj.pause()

    def resume(self, jobid):
        jobobj = self.get_job(jobid)
        logger.info("Resume job %s" % jobobj.name)
        jobobj.resume()

    def add_cron_job(self, func, jobid, executor='default', args = None, **kwargs):
        logger.info("add_cron_job: func=%s, executor=%s, args=%s" % (func,executor, args))
        return self._scheduler.add_job(func, id=jobid, trigger='cron', executor=executor, args=args, misfire_grace_time = None, **kwargs)

    def add_interval_job(self, func, jobid, seconds=60, executor='default'):
        logger.info("add_interval_job: func=%s, executor=%s, seconds=%s" % (func, executor, seconds))
        return self._scheduler.add_job(func, id=jobid, trigger='interval', executor=executor, seconds=seconds)

    def add_date_job(self, func, jobid, jobtime):
        return self._scheduler.add_job(func = func, id=jobid, next_run_time=jobtime)

    def remove_job(self, job_id):
        return self._scheduler.remove_job(job_id=job_id)

    def get_jobs(self):
        return self._scheduler.get_jobs()

    def get_job(self, jobid):
        return self._scheduler.get_job(job_id=jobid)

    def add_listener(self, callback, mask):
        self._scheduler.add_listener(callback=callback, mask = mask)

