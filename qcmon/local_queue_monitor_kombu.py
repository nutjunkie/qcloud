import sys
import time
import kombu
import logging
import socket
import configparser

from job_manager import JobManager

 
class LocalQueueMonitor():
    def __init__(self, jobman):
        self.jobmgr = jobman
        self.db     = jobman.db
        self.conn   = jobman.kombu
        self.exch   = kombu.Exchange("aimm.jobqueue", type="direct", durable=False)

        routing_keys = ("job_created", 
                        "job_submitted",
                        "job_started", 
                        "job_completed", 
                        "job_terminate_requested", 
                        "job_error")

        self.queues = [ ]
        for key in routing_keys:
            #logging.info("Local monitor binding queue '{0}' to '{1}'", key, exchange.name)
            queue = kombu.Queue(key, self.exch, routing_key=key, durable=True)
            queue.maybe_bind(self.conn)
            queue.declare()
            self.queues.append(queue)


    def on_message(self, body, message):
        handlers = {
                "job_created":self.on_job_created,
                "job_submitted":self.on_job_submitted,
                "job_started":self.on_job_started,
                "job_completed":self.on_job_completed,
                "job_terminate_requested":self.on_job_terminate_requested,
                "job_error":self.on_job_error }
        print("body type = %s" % type(body))
        print("body ", body)
        key = message.delivery_info["routing_key"]
        if key in handlers:
           handlers[key](body)
        message.ack()


    def on_job_created(self, msg):
        jobid = msg["jobid"]
        self.db.rpush("localqueue:new", jobid)
        self.jobmgr.update_job_status(jobid, "QUEUED")


    def on_job_submitted(self, msg):
        jobid = msg["jobid"]
        self.db.lrem("localqueue:new", 0, jobid)
        self.db.rpush("localqueue:submitted", jobid)
        self.jobmgr.update_job_status(jobid, "QUEUED")


    def on_job_started(self, msg):
        jobid = msg["jobid"]
        self.db.lrem("localqueue:submitted", 0, jobid)
        self.db.rpush("localqueue:running", jobid)
        self.jobmgr.update_job_status(jobid, "RUNNING")


    def on_job_completed(self, msg):
        jobid = msg["jobid"]
        self.db.lrem("localqueue:running", 0, jobid)
        self.jobmgr.update_job_files(jobid)
        job = self.jobmgr.get_job(jobid)
        if "output" in job.files:
            self.jobmgr.update_job_status(jobid, "DONE")
        else:
            self.jobmgr.update_job_status_error(jobid, "Missing output file")


    def on_job_terminate_requested(self, msg):
        jobid = msg["jobid"]
        nremoved = self.db.lrem("localqueue:new", 0, jobid)
        if nremoved > 0:
            self.jobmgr.update_job_status(jobid, "DELETED")
            return
        pass


    def on_job_error(self, msg):
        jobid = msg["jobid"]
        error = msg["error"]
        self.db.lrem("localqueue:new", 0, jobid)
        self.db.lrem("localqueue:submitted", 0, jobid)
        self.db.lrem("localqueue:running", 0, jobid)
        self.jobmgr.update_job_status_error(jobid, error)


    def run(self):
        not_done = True
        time_to_wait = 0.1 

        consumer = kombu.Consumer(self.conn, self.queues, auto_declare=True,
           callbacks=[self.on_message], accept=["json"])
        logging.info("LocalQueueMonitor listening on exhange %s" % self.exch.name)

        while not_done:
           not_done = True
           try:
              consumer.consume()
              self.conn.drain_events(
                 timeout=time_to_wait)
              success = True

           except socket.timeout as t:
              self.conn.heartbeat_check()
              time.sleep(1)


if __name__ == "__main__":

   logging.basicConfig(level=logging.INFO,
      format='%(asctime)s - %(levelname)-8s - %(message)s',
      datefmt='%d/%m/%Y %Hh%Mm%Ss')
   console = logging.StreamHandler(sys.stderr)

   logging.info("Reading configuration file: '{0}'".format(sys.argv[1]))
   config = configparser.ConfigParser()
   config.read(sys.argv[1])

   jobman  = JobManager(config)
   monitor = LocalQueueMonitor(jobman)

   try:
       monitor.run()
   except KeyboardInterrupt:
       pass
   finally:
       jobman.close_connection()
