FROM ubuntu

RUN apt-get update -yqq && \
    apt-get install -yqq python3-pip && \
    pip3 install redis && \
    pip3 install kombu && \
    pip3 install pika && \
    pip3 install paramiko

COPY queue_monitor.py        /usr/local/qcloud/qcqmon/queue_monitor.py
COPY local_queue_monitor_kombu.py  /usr/local/qcloud/qcqmon/local_queue_monitor.py
COPY job_manager.py          /usr/local/qcloud/qcqmon/job_manager.py  
COPY local_queue.py          /usr/local/qcloud/qcqmon/local_queue.py
COPY remote_queue_monitor.py /usr/local/qcloud/qcqmon/remote_queue_monitor.py 
COPY rqconn_local.py         /usr/local/qcloud/qcqmon/rqconn_local.py         
COPY rqconn_pbs.py           /usr/local/qcloud/qcqmon/rqconn_pbs.py
COPY qchem_sim               /usr/local/qcloud/qchem

ENTRYPOINT ["python3", "/usr/local/qcloud/qcqmon/queue_monitor.py", "/usr/local/qcloud/qcloud.cfg"]
