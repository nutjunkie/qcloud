#! /bin/bash

#
#  Installs the necessary packages for creating the qcloud configuration
#  AMI.  This AMI can be deleted once the cluster has been configured.
#
#  The base AMI should be the alinux2 image from the appropriate region in the
#  following list: 
#
#    https://github.com/aws/aws-parallelcluster/blob/v2.10.4/amis.txt
#      alinux2:
#        ap-southeast-2: ami-0aed9829b5a29d091
#        us-east-1: ami-043bed31bde73d741
#        us-west-1: ami-0f1328eb1e03d7fb2
#
#  The image can be built on a t2.micro instance with default resources.
#
#  This file can be downloaded to the launched instance with the command:
#
#    wget https://raw.githubusercontent.com/nutjunkie/qcloud/main/aws/config_AMI_setup.sh
#    chmod +x config_AMI_setup.sh
#
#    ./config_AMI_setup.sh
#    rm -fr  ~/.ssh
#    rm config_AMI_setup.sh
#    EDIT the qcloud_setup.py script to add the appropriate QCloud AMI and AWS region
#    sudo /usr/local/sbin/ami_cleanup.sh
#
#  Once the instance has been stopped, an AMI can be created, right click on the instance ID:
#     Images and templates -> Create image

pcluster_version="2.10.4"

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
      #sudo apt-get -y update && \
      sudo apt-get -y install curl unzip  python3 python3-pip
   elif command -v yum &>/dev/null; then
      #sudo yum -y update && \
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
      if [[ $pc == $pcluster_version ]]; then return 0; fi
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

cd && curl https://raw.githubusercontent.com/nutjunkie/qcloud/main/aws/qcloud_setup.py -o qcloud_setup.py
chmod a+x qcloud_setup.py

echo ""
echo "Now run the qcloud_setup.py script to configure an AWS access key:"
echo "./qcloud_setup.py --keygen"
echo ""
echo "If you have already performed this step, you can configure a cluster with:"
echo "./qcloud_setup.py --setup"

