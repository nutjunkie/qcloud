FROM ubuntu

RUN apt-get update -yqq && \
    apt-get install -yqq python3-pip && \
    pip3 install redis && \
    pip3 install kombu && \
    pip3 install pika && \
    pip3 install paramiko

COPY queue_monitor.py        /opt/qcloud/qcqmon/queue_monitor.py
COPY local_queue_monitor_kombu.py  /opt/qcloud/qcqmon/local_queue_monitor.py
COPY job_manager.py          /opt/qcloud/qcqmon/job_manager.py  
COPY local_queue.py          /opt/qcloud/qcqmon/local_queue.py
COPY remote_queue_monitor.py /opt/qcloud/qcqmon/remote_queue_monitor.py 
COPY rqconn_local.py         /opt/qcloud/qcqmon/rqconn_local.py         
COPY rqconn_pbs.py           /opt/qcloud/qcqmon/rqconn_pbs.py
COPY qchem_sim               /opt/qcloud/qchem

ENTRYPOINT ["python3", "/opt/qcloud/qcqmon/queue_monitor.py", "/opt/qcloud/qcloud.cfg"]
