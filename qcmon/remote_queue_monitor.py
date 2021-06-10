import os
import sys
import json
import time
import logging
import configparser

from job_manager  import JobManager
from local_queue  import LocalQueue
from rqconn_local import RQConnLocal
from rqconn_pbs   import RQConnPBS



class RemoteQueueMonitor():
    """Monitors a remote queue for job status changes"""

    def __init__(self, db, jobmgr, qid, local_queue, remote_queue_conn,
            update_period):
        """Creates a queue monitor

        db -- Database connection
        jobmgr -- Job manager
        qid -- Queue ID
        local_queue -- Local queue client
        remote_queue_conn -- Remote queue connector
        update_period -- Time period for getting remote updates (in sec)
        """
        self.db = db
        self.jobmgr = jobmgr
        self.qid = qid
        self.local_queue = local_queue
        self.remote_queue_conn = remote_queue_conn
        self.update_period = update_period

    def run(self):
        """Starts the monitoring loop"""
        logging.info("Remote queue monitor started")
        self.__init_remote_queue()
        while True:
            #  1. Update the status of the remote queue
            self.remote_queue_conn.update()

            #  2. Read list of running jobs from the database
            jobs_submitted = self.db.lrange("remotequeue:%s:submitted" % self.qid, 0, -1)
            jobs_running = self.db.lrange("remotequeue:%s:running" % self.qid, 0, -1)
            jobs_in_queue = jobs_submitted + jobs_running
            for jobid in jobs_in_queue:
                job = json.loads(self.db.get("remote:%s" % jobid))
                job_status = self.remote_queue_conn.get_job_status(job)
                logging.debug("Request job status from rqconn: %s -- %s" % (jobid, str(job_status)))
                if job_status is None:
                    #  Job not in remote queue (completed)
                    #  Possible state changes:
                    #  RUNNING -> DONE
                    #  SUBMITTED -> DONE
                    output_files = self.remote_queue_conn.transfer_output_files(job)
                    logging.debug("Transfer output files for job: %s -- %s" % (jobid, str(output_files)))
                    if output_files is not None:
                        if jobid in jobs_submitted:
                            self.db.lrem("remotequeue:%s:submitted" % self.qid, 0, jobid)
                        if jobid in jobs_running:
                            self.db.lrem("remotequeue:%s:running" % self.qid, 0, jobid)
                        self.db.delete("remote:%s" % jobid)
                        self.local_queue.emit_job_completed(jobid)
                elif job_status == "RUNNING":
                    #  Job is running remotely
                    #  Possible state changes:
                    #  SUBMITTED -> RUNNING
                    if jobid in jobs_submitted:
                        self.db.lrem("remotequeue:%s:submitted" % self.qid, 0, jobid)
                        self.db.rpush("remotequeue:%s:running" % self.qid, jobid)
                        self.local_queue.emit_job_started(jobid)

            #  3. Start new jobs
            while self.remote_queue_conn.can_submit():
                jobid = self.local_queue.pop_new()
                if jobid is None: break
                local_workdir = self.jobmgr.get_job_workdir(jobid)
                logging.debug("Submit job to rqconn: %s" % jobid)
                job = self.remote_queue_conn.submit_job(jobid, local_workdir)
                if job is not None:
                    self.db.set("remote:%s" % jobid, json.dumps(job))
                    self.db.rpush("remotequeue:%s:submitted" % self.qid, jobid)
                    self.local_queue.emit_job_submitted(jobid)
                else:
                    logging.info("Submit job to rqconn: %s -- FAILURE" % jobid)
                    self.local_queue.emit_job_error(jobid,
                            "Remote submission failed")

            #  4. Delay and repeat
            time.sleep(self.update_period)

    def __init_remote_queue(self):
        jobs_submitted = self.db.lrange("remotequeue:%s:submitted" % self.qid, 0, -1)
        jobs_running = self.db.lrange("remotequeue:%s:running" % self.qid, 0, -1)
        jobs_in_queue = jobs_submitted + jobs_running
        jobs = []
        for jobid in jobs_in_queue:
            job = self.db.get("remote:%s" % jobid)
            if job is not None:
               jobs.append(json.loads(job))
        self.remote_queue_conn.init(jobs)



if __name__ == "__main__":

   logging.basicConfig(filename="aimm_remote_queue.log", level=logging.DEBUG)

   config_file = sys.argv[1]
   if not os.path.isfile(config_file):
      logging.warn("Configuration file not found: '{0}'", config_file)
      sys.exit(1)

   logging.info("Reading configuration file: '{0}'".format(config_file))
   config = configparser.ConfigParser()
   config.read(config_file)

   rq_conn_id   = sys.argv[2]
   jobs_path    = config.get("aimm", "qc")
   rq_conn_type = config.get(rq_conn_id, "type")

   jobmgr = JobManager(config)
   local_queue = LocalQueue(jobmgr.db, jobmgr.kombu)

   update_period = float(config.get(rq_conn_id, "update_period"))
   if rq_conn_type == "local":
      queue_size = int(config.get(rq_conn_id, "queue_size"))
      time_limit = int(config.get(rq_conn_id, "time_limit"))
      mem_limit = int(config.get(rq_conn_id, "mem_limit"))
      rq_conn = RQConnLocal(jobs_path, queue_size, time_limit, mem_limit)
   elif rq_conn_type == "pbs":
      hostname = config.get(rq_conn_id, "host")
      port = int(config.get(rq_conn_id, "port"))
      username = config.get(rq_conn_id, "username")
      pbs = { }
      pbs["queue"] = config.get(rq_conn_id, "pbs_queue")
      pbs["property"] = config.get(rq_conn_id, "pbs_property")
      pbs["walltime"] = int(config.get(rq_conn_id, "time_limit"))
      queue_size = int(config.get(rq_conn_id, "queue_size"))
      mem_limit = int(config.get(rq_conn_id, "mem_limit"))
      rq_conn = RQConnPBS(hostname, port, username, queue_size, pbs)

   mon = RemoteQueueMonitor(jobmgr.db, jobmgr, rq_conn_id, local_queue, rq_conn, update_period)

   try:
       mon.run()
   except KeyboardInterrupt:
       pass
   finally:
       jobmgr.close_connection()
