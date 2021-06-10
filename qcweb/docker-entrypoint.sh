#!/bin/bash
set -e

if [ "$1" = "qcweb" ]
then
    echo "---> Starting qcloud tornado web server ..."
    /usr/bin/python3 /usr/local/qcloud/qcweb/web_server.py /usr/local/qcloud/qcloud.cfg
fi

exec "$@"
