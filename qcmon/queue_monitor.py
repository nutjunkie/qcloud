import os
import sys
import subprocess
import configparser


path = os.path.abspath(__file__)
dir  = os.path.dirname(path)
os.chdir(dir)

cwd = os.getcwd()
print("Working directory  = %s" % cwd)
print("Python interpreter = %s" % sys.executable)

config_file = sys.argv[1]
if not os.path.isfile(config_file):
    print("Could not find a config file at '{0}'", config_file)
    sys.exit(1)

config = configparser.ConfigParser()
config.read(config_file)

connections = config.get("aimm", "rq_conn").split(",")

proc_local_queue = subprocess.Popen(
        [ sys.executable, "local_queue_monitor.py", config_file ])

proc_remote_queue = [ ]
for rq in connections:
    rq1 = rq.strip()
    proc_remote_queue.append(subprocess.Popen(
        [ sys.executable, "remote_queue_monitor.py", config_file, rq1 ]))

proc_local_queue.wait()
for proc in proc_remote_queue:
    proc.wait()
