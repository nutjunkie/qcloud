import os
import re
import json
import uuid
import redis
import kombu
import logging
import subprocess

from local_queue import LocalQueue

slurm_path="/opt/slurm/bin/"
# These are the slurm user and group on the host machine
slurm_user=1000
slurm_group=1000


class ComputationalJob():
    def __init__(self, jobid, slurmid, status, files):
        self.jobid   = jobid
        self.slurmid = slurmid
        self.status  = status
        self.files   = files

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
        match = re.match('\$slurm([\s\S]+?)\$end([\s\S]+)',job_input)

        if (bool(match)):
           slurm_input = match.group(1).lstrip().rstrip()
           #qchem_input = match.group(2).lstrip().rstrip()
           job = self.create_job_slurm(slurm_input, job_input)
        else:
           job = self.create_job(job_input)
           self.queue.emit_job_created(job.jobid)

        print(job)

        return job



    def create_job(self, job_input):
        jobid = uuid.uuid1().hex
        job_workdir = self.get_job_workdir(jobid)
        os.mkdir(job_workdir)

        finput = open("%s/input" % job_workdir, "w")
        finput.write(job_input)
        finput.close()
        job = ComputationalJob(jobid, -1, "NEW", [])
        self.db.set("job:%s" % jobid, json.dumps(job.__dict__))
        return job


    def create_job_slurm(self, slurm_input, qchem_input):
        jobid = uuid.uuid1().hex
        jobdir = self.get_job_workdir(jobid)
        os.mkdir(jobdir)
        os.chown(jobdir, slurm_user, slurm_group)

        match = re.search('--job-name[\s=]+(\S+)',slurm_input)
        if (bool(match)):
           (base,ext) = os.path.splitext(match.group(1))
           if (not (ext == ".inp" or ext == ".in" or ext == ".qcin")):
              base = match.group(1)
           batch_fname  = base + ".bat"
           input_fname  = base + ".inp"
           output_fname = base + ".out"
        else:
           batch_fname  = "batch"
           input_fname  = "input"
           output_fname = "output"

        fname  = "%s/%s" % (jobdir, batch_fname)
        fh = open(fname, "w")
        fh.write("#!/bin/bash\n")
        fh.write(slurm_input) 
        fh.write("\n")
        fh.write("#SBATCH --chdir={0}\n".format(jobdir))
        fh.write("\n")
        fh.write("export QC=/opt/qchem\n")
        fh.write("export QCAUX=/opt/qcaux\n")
        fh.write("export QCSCRATCH=/tmp/scratch\n")
        fh.write("$QC/bin/qchem {0} {1}\n".format(input_fname,output_fname))
        fh.close()

        fname  = "%s/%s" % (jobdir, input_fname)
        fh = open(fname, "w")
        fh.write(qchem_input)
        fh.close()

        cmd = '%s/sbatch %s/%s' % (slurm_path,jobdir,batch_fname)
        output = subprocess.getoutput(cmd)
        match  = re.match("Submitted batch job (\d+)", output)
        slurmid = -1
        if (bool(match)):
           slurmid = match.group(1)
        else:
           logging.error("Failed to determine SLURM jobid from output %s" % output)

        job = ComputationalJob(jobid, slurmid, "QUEUED", [])
        self.db.set("job:%s" % jobid, json.dumps(job.__dict__))
        return job


    def delete_job(self, jobid):
        #self.queue.emit_job_termination_requested(jobid)
        job = self.get_job(jobid)
        slurmid = job.slurmid
        if (int(slurmid) > 0):
           cmd = '%s/scancel %s' % (slurm_path,slurmid)
           output = subprocess.getoutput(cmd)
           #logging.info("scancel returned: %s" % output)
           self.update_job_status(jobid, "DELETED")
            


    def get_job(self, jobid):
        job = self.db.get("job:%s" % jobid)
        if (job is None):
           return ComputationalJob(jobid, -1, "DNE", [])
        else:
           doc = json.loads(job)
           job = ComputationalJob(jobid, doc["slurmid"], doc["status"], doc["files"])
           self.update_job(job)
           return job


    # valid status: QUEUED, RUNNING, DONE, ERROR, DELETED, INVALID

    def update_job(self, job):
        if (int(job.slurmid) > 0):
           if (job.status == "QUEUED" or job.status == "RUNNING"):
              cmd = '%s/squeue -h --job %s' % (slurm_path,job.slurmid)
              output = subprocess.getoutput(cmd)
              #logging.info("squeue returned: %s" % output)
              tokens = output.lstrip().rstrip().split()

              if (len(tokens) > 4):
                 token = tokens[4]
                 if (token == "R" or token == "CG"):
                    job.status = "RUNNING"
                 else:
                    job.status = "QUEUED"
              else:
                 job.status = "DONE"

              self.update_job_status(job.jobid,job.status)
              if (job.status == "DONE"):
                 self.update_job_files(job.jobid)
        
              

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
