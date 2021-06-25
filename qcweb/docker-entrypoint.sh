#!/bin/bash
set -e

if [ "$1" = "qcweb" ]
then
    echo "---> Starting qcloud tornado web server ..."
    /usr/bin/python3 /opt/qcloud/qcweb/web_server.py /opt/qcloud/qcloud.cfg
fi

exec "$@"
