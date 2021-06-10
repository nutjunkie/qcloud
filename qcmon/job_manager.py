import os
import json
import uuid
import redis
import kombu
import logging

from local_queue import LocalQueue


class ComputationalJob():
    def __init__(self, jobid, status, files):
        self.jobid  = jobid
        self.status = status
        self.files  = files

    def is_valid(self):
        return self.status != "DNE"



class JobManager():
    def __init__(self, config):
        redis_host = config.get("redis", "host")
        redis_port = config.get("redis", "port")
        self.db = redis.StrictRedis(host=redis_host, port=redis_port, db=0,
           charset="utf-8", decode_responses=True)

        queue_host = config.get("queue", "host")
        queue_port = config.get("queue", "port")
        logging.info("Attempting connection to RabbitMQ host: {0}:{1}".format(queue_host, queue_port))
        self.kombu = kombu.Connection(hostname=queue_host, port=queue_port)
        self.kombu.ensure_connection(max_retries=5)

        self.workdir = config.get("queue", "workdir")
        self.queue = LocalQueue(self.db, self.kombu)

    def close_connection(self):
        self.kombu.close()

    def submit_job(self, job_input):
        id = self.create_job(job_input)
        self.queue.emit_job_created(id.jobid)
        return id

    def delete_job(self, jobid):
        self.queue.emit_job_termination_requested(jobid)

    def create_job(self, job_input):
        jobid = uuid.uuid1().hex
        job_workdir = self.get_job_workdir(jobid)
        os.mkdir(job_workdir)
        finput = open("%s/input" % job_workdir, "w")
        finput.write(job_input)
        finput.close()
        job = ComputationalJob(jobid, "NEW", [])
        self.db.set("job:%s" % jobid, json.dumps(job.__dict__))
        return job

    def get_job(self, jobid):
        job = self.db.get("job:%s" % jobid)
        if (job is None):
           return ComputationalJob(jobid, "DNE", [])
        else:
           doc = json.loads(job)
           return ComputationalJob(jobid, doc["status"], doc["files"])

    def get_job_file(self, jobid, fname):
        fpath = "%s/%s" % (self.get_job_workdir(jobid), fname)
        if not os.path.isfile(fpath): return None
        return file(fpath)

    def get_job_filepath(self, jobid, fname):
        fpath = "%s/%s" % (self.get_job_workdir(jobid), fname)
        if not os.path.isfile(fpath): return None
        return fpath

    def get_job_workdir(self, jobid):
        return "%s/%s" % (self.workdir, jobid)

    def update_job_status(self, jobid, status):
        self.__update_job_descriptor(jobid, [("status", status)])

    def update_job_status_error(self, jobid, msg):
        self.__update_job_descriptor(jobid,
                [("status", "ERROR"), ("error", msg)])

    def update_job_files(self, jobid):
        files = os.listdir(self.get_job_workdir(jobid))
        self.__update_job_descriptor(jobid, [("files", files)])

    def __update_job_descriptor(self, jobid, nvpairs):
        jobkey = "job:%s" % jobid
        with self.db.pipeline() as p:
            while 1:
                try:
                    p.watch(jobkey)
                    doc = json.loads(p.get(jobkey))
                    for nvpair in nvpairs:
                        doc[nvpair[0]] = nvpair[1]
                    p.multi()
                    p.set(jobkey, json.dumps(doc))
                    p.execute()
                    break
                except WatchError:
                    continue
