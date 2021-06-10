import os
import subprocess

class RQConnLocal():
    """Remote queue connector --
    Implementation for locally executed processes"""

    def __init__(self, exepath, maxjobs, time_limit, mem_limit):
        self.proc_running = []
        self.exepath = exepath
        self.maxjobs = maxjobs
        self.env = os.environ.copy()
        self.env["QCHEMSERV_TIME_LIMIT"] = str(time_limit)
        self.env["QCHEMSERV_MEM_LIMIT"] = str(mem_limit * 1024)

    def init(self, jobs):
        """Sets the initial state of submitted jobs
           (e.g. from persistent storage)"""
        pass

    def update(self):
        """Updates the internal record of the state of the queue"""
        for proc in self.proc_running:
            proc.poll();
            if proc.returncode is not None:
                self.proc_running.remove(proc)

    def get_job_status(self, job):
        """Returns the status of a job

        job -- Job object
        """
        for proc in self.proc_running:
            if job["pid"] != proc.pid:
                continue
            else:
                return "RUNNING"
        return None

    def can_submit(self):
        return len(self.proc_running) < self.maxjobs

    def submit_job(self, job, workdir):
        exe = "%s/runqchem" % self.exepath
        proc = subprocess.Popen([exe, "input", "output"],
            cwd=workdir, env=self.env)
        proc_desc = { "pid":proc.pid, "status":"RUNNING", "cwd":workdir }
        self.proc_running.append(proc)
        return proc_desc

    def terminate_job(self, job):
        pass

    def transfer_input_files(self, job):
        """Transfers input files to remote host

        job -- Job object
        """
        return []

    def transfer_output_files(self, job):
        """Transfers output files from remote host

        job -- Job object
        """
        return []

