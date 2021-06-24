#!/bin/bash

#
# This is the post-launch script configured to run by qcloud_setup.py
#

prefix=/usr/local
logfile=/tmp/node.log

. "/etc/parallelcluster/cfnconfig"

case "${cfn_node_type}" in
    MasterServer)
        echo "I am the head node" >> $logfile
        #echo "Launching piped" >> $logfile
        #sudo nohup $prefix/qcloud/bin/piped &
        #echo "piped launched" >> $logfile
        #echo "Launching docker daemon" >> $logfile
        #sudo mkdir /tmp/qcloud
        #sudo systemctl start docker
        #echo "Launching qcloud services" >> $logfile
        #cd $prefix/qcloud && sudo /usr/local/bin/docker-compose  up -d >> $logfile
    ;;
    ComputeFleet)
        echo "I am a compute node" >> $logfile
    ;;
    *)
        echo "Unhandled node type: ${cfn_node_type}" >> $logfile
    ;;
esac
