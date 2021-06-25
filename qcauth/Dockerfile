FROM ubuntu

RUN apt-get update -yqq && \
    apt-get install -yqq python3-pip && \
    pip3 install redis && \
    pip3 install tornado && \
    pip3 install bcrypt && \
    pip3 install -Iv pyjwt==1.7.1

COPY authentication_server.py /opt/qcloud/qcauth/authentication_server.py
COPY user_manager.py /opt/qcloud/qcauth/user_manager.py
COPY certs /opt/qcloud/qcauth/certs

ENTRYPOINT ["python3", "/opt/qcloud/qcauth/authentication_server.py", "/opt/qcloud/qcloud.cfg"]
