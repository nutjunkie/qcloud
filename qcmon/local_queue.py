import json
import kombu
 
class LocalQueue():
    def __init__(self, db, qconn):
        self.db = db
        self.qchan = qconn.channel()
        self.qxchg = kombu.Exchange("aimm.jobqueue", type="direct",
                channel=self.qchan, durable=False)
        self.qprod = kombu.Producer(self.qchan, self.qxchg)

    def emit_job_created(self, jobid):
        self.__send_message(jobid, "job_created")

    def emit_job_submitted(self, jobid):
        self.__send_message(jobid, "job_submitted")

    def emit_job_started(self, jobid):
        self.__send_message(jobid, "job_started")

    def emit_job_completed(self, jobid):
        self.__send_message(jobid, "job_completed")

    def emit_job_terminate_requested(self, jobid):
        self.__send_message(jobid, "job_terminate_requested")

    def emit_job_error(self, jobid, error_message):
        self.__send_message(jobid, "job_error", { "error":error_message })

    def pop_new(self):
        return self.db.lpop("localqueue:new")

    def __send_message(self, jobid, routing_key, extras = { }):
        doc = { "jobid":jobid }
        doc.update(extras)
        msg = json.dumps(doc)
        self.qprod.publish(msg, routing_key, content_type="application/json",
                content_encoding="utf-8")
