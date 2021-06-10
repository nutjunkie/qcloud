import logging, paramiko, re

class RQConnPBS():
    """Remote queue connector --
    Implementation for remotely executed processes via PBS"""

    def __init__(self, hostname, port, username, maxjobs, jobconfig):
        self.pbs_ssh_hostname = hostname
        self.pbs_ssh_port = port
        self.pbs_username = username
        self.pbs_submitted = []
        self.pbs_queue = []
        self.maxjobs = maxjobs
        self.jobconfig = jobconfig
        time_limit = self.jobconfig["walltime"]
        time_limit_hrs = int(time_limit / 3600)
        time_limit_min = int(time_limit / 60)
        time_limit_sec = time_limit - time_limit_min * 60
        time_limit_min = time_limit_min - time_limit_hrs * 60
        self.jobconfig["walltime"] = "{0}:{1}:{2}".format(time_limit_hrs,
                time_limit_min, time_limit_sec)

        self.regex_qsub = re.compile(r"^(?P<jobid>\d+)\.[\w\.]+\s+")
        self.regex_qstat = re.compile(r"^(?P<jobid>\d+)\.[\w\.]+\s+(?P<username>\w+)\s+(?P<queue>\w+)\s+(?P<jobname>\S+)\s+(?P<sessid>\S+)\s+(?P<nds>\S+)\s+(?P<tsk>\S+)\s+(?P<memory>\S+)\s+(?P<time>\S+)\s+(?P<status>\w)\s+")

        self.log = logging.Logger(__name__)
        self.log.setLevel(logging.DEBUG)
        self.log.addHandler(logging.StreamHandler())

        self.ssh_client = None
        self.reset_connection_if_needed()

    def reset_connection_if_needed(self):
        need_reset = False
        if self.ssh_client is None:
            need_reset = True
        elif not self.ssh_client.get_transport().is_active():
            need_reset = True
        if need_reset:
            self.log.info("Establishing SSH connection to remote server %s@%s:%s" % (self.pbs_username, self.pbs_ssh_hostname, self.pbs_ssh_port))
            try:
                self.ssh_client = paramiko.SSHClient()
                self.ssh_client.load_system_host_keys()
                self.ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                self.ssh_client.connect(self.pbs_ssh_hostname, self.pbs_ssh_port, username=self.pbs_username, key_filename="/home/epif/.ssh/id_rsa_workshop")
                self.log.info("SSH connection to remote server %s@%s:%s established" % (self.pbs_username, self.pbs_ssh_hostname, self.pbs_ssh_port))
            except:
                self.log.error("SSH connection to remote server %s@%s:%s FAILED" % (self.pbs_username, self.pbs_ssh_hostname, self.pbs_ssh_port))
                self.ssh_client = None

    def init(self, jobs):
        """Sets the initial state of submitted jobs
           (e.g. from persistent storage)"""
        for job in jobs:
            self.pbs_submitted.append(job["pid"])

    def update(self):
        """Updates the internal record of the state of the queue"""
        self.reset_connection_if_needed()
        if self.ssh_client is None:
            self.log.debug("Unable to establish SSH connection to remote server")
            return
        try:
            (stdin, stdout, stderr) = self.ssh_client.exec_command(
                    "qstat -u %s" % self.pbs_username)
            self.pbs_queue = []
            pbs_pids = []
            for line in stdout:
                m = self.regex_qstat.match(line)
                if m is not None:
                    d = m.groupdict()
                    pid = d["jobid"]
                    status = d["status"]
                    if pid in self.pbs_submitted:
                        self.pbs_queue.append({ "pid":pid, "status":status})
                        pbs_pids.append(pid)
            self.pbs_submitted = [pid for pid in self.pbs_submitted if pid in pbs_pids]
            self.log.debug("Update retrieved %d jobs" % len(self.pbs_queue))
            self.log.debug("%s" % str(self.pbs_queue))
        except:
            self.ssh_client = None
            self.log.debug("Failure to update PBS queue state")

    def get_job_status(self, job):
        """Returns the status of a job

        job -- Job object
        """
        for proc in self.pbs_queue:
            if job["pid"] != proc["pid"]:
                continue
            return { "Q":"QUEUED", "R":"RUNNING", "E":"RUNNING",
                    "C":"DONE" }.get(proc["status"], "UNKNOWN")
        return None

    def can_submit(self):
        return len(self.pbs_queue) < self.maxjobs

    def submit_job(self, jobid, workdir):
        self.reset_connection_if_needed()
        if self.ssh_client is None:
            self.log.debug("Unable to establish SSH connection to remote server")
            return

        remotedir = "qchemserv/%s" % jobid
        pbs_queue = self.jobconfig["queue"]
        pbs_property = self.jobconfig["property"]
        pbs_walltime = self.jobconfig["walltime"]
        try:
            sftp = self.ssh_client.open_sftp()
            sftp.mkdir(remotedir)
            sftp.chdir(remotedir)
            with sftp.open("%s.pbs" % jobid, "w") as f:
                f.write("#PBS -N aimm_%s\n" % jobid)
                f.write("#PBS -V\n")
                f.write("#PBS -q %s\n" % pbs_queue)
#                f.write("#PBS -l nodes=1:%s:ppn=1\n" % pbs_property)
                f.write("#PBS -l nodes=1:ppn=1\n")
                f.write("#PBS -l walltime=%s\n" % pbs_walltime)
                f.write("\n")
                f.write("cd $PBS_O_WORKDIR\n")
                f.write("setenv QC /home/qcsoftware/qchem_latest\n")
                f.write("setenv QCSCRATCH /scratch/%s\n" % self.pbs_username)
                f.write("setenv QCAUX /home/qcsoftware/qcaux_latest\n")
                f.write("source $QC/bin/qchem.setup\n")
                f.write("qchem input output\n")
            sftp.put("%s/input" % workdir, "input")
            sftp.close()
            (stdin, stdout, stderr) = self.ssh_client.exec_command(
                    "cd %s; qsub %s.pbs" % (remotedir, jobid))
            qsub_output = stdout.readlines()
            qsub_stderr = stderr.readlines()
            self.log.debug("PBS qsub output:\n%s" % str(qsub_output))
            self.log.debug("PBS qsub error:\n%s" % str(qsub_stderr))
            if len(qsub_output) > 0:
                m = self.regex_qsub.match(qsub_output[0])
            if m is not None:
                d = m.groupdict()
                pid = d["jobid"]
                self.log.info("Submit job to PBS: %s -> %s" % (jobid, pid))
                proc_desc = { "jobid":jobid, "pid":pid, "status":"QUEUED",
                        "localwd":workdir, "remotewd":remotedir }
                self.pbs_submitted.append(pid)
                self.update()
            else:
                self.log.error("Failed to submit job to PBS: %s" % jobid)
                return None
            return proc_desc
        except:
            self.ssh_client = None
            return None

    def terminate_job(self, job):
        pass

    def transfer_input_files(self, job):
        """Transfers input files to remote host

        job -- Job object
        """
        pass

    def transfer_output_files(self, job):
        """Transfers output files from remote host

        job -- Job object
        """
        self.reset_connection_if_needed()
        if self.ssh_client is None:
            self.log.debug("Unable to establish SSH connection to remote server")
            return

        jobid = job["jobid"]
        remotedir = job["remotewd"]
        localdir = job["localwd"]
        self.log.info("Transfer output files for job %s" % jobid)
        try:
            sftp = self.ssh_client.open_sftp()
            sftp.chdir(remotedir)
            filelist = sftp.listdir()
            self.log.debug("Remote directory: %s" % remotedir)
            self.log.debug("Remote file listing: %s" % str(filelist))
            transferred_files = []
            for filename in filelist:
                if filename == "input":
                    continue
                if filename == "%s.pbs" % jobid:
                    continue
                if filename.startswith("aimm_%s" % jobid):
                    continue
                self.log.debug("SFTP copy %s -> %s/%s" %
                        (filename, localdir, filename))
                sftp.get("%s" % filename, "%s/%s" % (localdir, filename))
                transferred_files.append(filename)
            sftp.close()
            return transferred_files
        except:
            self.ssh_client = None
            return None

