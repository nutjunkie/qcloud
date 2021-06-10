import sys
import json
#import kombu
import pika
import logging
import configparser
from job_manager import JobManager

 
class LocalQueueMonitor():
    #def __init__(self, jobman):
    def __init__(self, jobman, config):
        self.jobmgr = jobman
        self.db     = jobman.db


        #self.qchan  = jobman.kombu.channel()
        amqp_host = config.get("queue", "host")
        amqp_port = int(config.get("queue", "port"))
        self.qconn = pika.BlockingConnection(
                pika.ConnectionParameters(host=amqp_host, port=amqp_port))
        self.qchan  = self.qconn.channel();



        self.qchan.exchange_declare(exchange="aimm.jobqueue", exchange_type="direct")

        self.queue_name = self.qchan.queue_declare(queue="", exclusive=True).method.queue
        self.qchan.queue_bind(exchange="aimm.jobqueue", queue=self.queue_name,
                routing_key="job_created")
        self.qchan.queue_bind(exchange="aimm.jobqueue", queue=self.queue_name,
                routing_key="job_submitted")
        self.qchan.queue_bind(exchange="aimm.jobqueue", queue=self.queue_name,
                routing_key="job_started")
        self.qchan.queue_bind(exchange="aimm.jobqueue", queue=self.queue_name,
                routing_key="job_completed")
        self.qchan.queue_bind(exchange="aimm.jobqueue", queue=self.queue_name,
                routing_key="job_terminate_requested")
        self.qchan.queue_bind(exchange="aimm.jobqueue", queue=self.queue_name,
                routing_key="job_error")

    def on_message(self, ch, method, properties, body):
        handlers = {
                "job_created":self.on_job_created,
                "job_submitted":self.on_job_submitted,
                "job_started":self.on_job_started,
                "job_completed":self.on_job_completed,
                "job_terminate_requested":self.on_job_terminate_requested,
                "job_error":self.on_job_error }
        print("Message Body:", body)
        if method.routing_key in handlers:
            handlers[method.routing_key](json.loads(body))
        ch.basic_ack(delivery_tag=method.delivery_tag)

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
        self.qchan.basic_consume(on_message_callback=self.on_message, queue=self.queue_name)
        self.qchan.start_consuming()


if __name__ == "__main__":

   logging.basicConfig(level=logging.INFO,
      format='%(asctime)s - %(levelname)-8s - %(message)s',
      datefmt='%d/%m/%Y %Hh%Mm%Ss')
   console = logging.StreamHandler(sys.stderr)

   logging.info("Reading configuration file: '{0}'".format(sys.argv[1]))
   config = configparser.ConfigParser()
   config.read(sys.argv[1])

   jobman  = JobManager(config)
   monitor = LocalQueueMonitor(jobman, config)

   try:
       monitor.run()
   except KeyboardInterrupt:
       pass
   finally:
       jobman.close_connection()
