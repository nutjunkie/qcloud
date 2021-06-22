#! /bin/bash

#
#  Installs the necessary packages for creating the config AMI.
#
#   - Launch a t2.micro instance with the appropriate alinux2 AMI,
#     e.g.  ami-0186908e2fdeea8f3
#     The default settings should suffice.
#   - Copy this script to the running instance and run it
#   - Create a new AMI
#

pcluster_version="2.10.3"

install_aws_cli() 
{
   uname=$(uname)
   aws_pkg="awscli-exe-linux-x86_64.zip"

   echo "Installing AWS CLI for $uname"

   mkdir -p /tmp/qcloud_install && cd /tmp/qcloud_install
   if [ ! -e $aws_pkg ]; then
      curl "https://awscli.amazonaws.com/$aws_pkg" -o $aws_pkg
   fi
   unzip $aws_pkg && sudo ./aws/install
}


install_aws_parallelcluster()
{
   if ! command -v pip3 &> /dev/null; then
      echo "ERROR: pip3 command not found"
      return 1
   fi

   echo "Installing aws-parallelcluster"
   sudo pip3 install -Iv aws-parallelcluster==$pcluster_version --upgrade
}


install_packages()
{
   if command -v apt &>/dev/null; then
      sudo apt-get -y update && \
      sudo apt-get -y install curl unzip  python3 python3-pip
   elif command -v yum &>/dev/null; then
      sudo yum -y update && \
      sudo yum -y install curl unzip  python3 python3-pip
   fi
}


verify_aws_cli() 
{
   if command -v aws &> /dev/null; then
      aws=$(aws --version)
      if [[ $aws == *"aws-cli/2"* ]]; then return 0; fi
   fi

   install_aws_cli
}


verify_aws_parallelcluster() 
{
   if command -v pcluster  &> /dev/null; then
      pc=$(pcluster version)
      if [[ $pc == 2* ]]; then return 0; fi
   fi

   install_aws_parallelcluster
}


install_remi()
{
   sudo pip3 install remi
}


install_packages 
verify_aws_cli 
verify_aws_parallelcluster 
#install_remi

aws configure
aws s3 cp s3://qchem-qcloud/qcloud/aws/qcloud_setup.py .
chmod a+x qcloud_setup.py
