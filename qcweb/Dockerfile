FROM ubuntu

RUN apt-get update -yqq && \
    apt-get install -yqq python3-pip && \
    apt-get install -yqq vim && \
    pip3 install redis && \
    pip3 install kombu && \
    pip3 install tornado

COPY web_server.py /usr/local/qcloud/qcweb/web_server.py
COPY job_manager.py /usr/local/qcloud/qcweb/job_manager.py
COPY local_queue.py /usr/local/qcloud/qcweb/local_queue.py
COPY certs /usr/local/qcloud/qcweb/certs

RUN mkfifo /tmp/egress.pipe  && \
    mkfifo /tmp/ingress.pipe

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN  chmod a+x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
