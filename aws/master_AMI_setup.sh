#! /bin/bash

#
#  Installs the necessary packages and builds the Docker containers for the
#  main qcloud/qchem AMI.  This AMI is used for both the head node and the
#  compute nodes of the cluster.
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
#      25 Gb volume on /dev/xvda1  mount on /
#      This could determine the scratch
#
#  This file can be downloaded within the launched instance with the command:
#
#    wget https://raw.githubusercontent.com/nutjunkie/qcloud/main/aws/master_AMI_setup.sh
#    chmod +x master_AMI_setup.sh
#
#    ./master_AMI_setup.sh
#    rm -fr ~/.aws ~/.ssh
#    rm master_AMI_setup.sh
#    sudo /usr/local/sbin/ami_cleanup.sh
#    sudo rm /etc/munge/munge.key 
#
#    !!!! need to add log rotation /etc/logrotate.conf
#
#/var/log/piped.log {
#   missingok
#   create 644 root root
#   size 100k
#   rotate 4
#}

#
#  Once the instance has been stopped, an AMI can be created, right click on the instance ID:
#     Images and templates -> Create image

pcluster_version="2.10.4"
flexnet_version="11.18.0"
prefix=/opt
docker_compose=/usr/local/bin/docker-compose


install_rpms()
{
   echo "Installing RPM dependencies"
   sudo yum -y install docker lapack-devel blas-devel amazon-efs-utils
}


install_docker_compose()
{
   if ! command -v $docker_compose &> /dev/null; then
      echo "Installing docker-compose"
      sudo curl -L "https://github.com/docker/compose/releases/download/1.28.6/docker-compose-$(uname -s)-$(uname -m)" -o $docker_compose
      sudo chmod a+x $docker_compose 
      sudo ln -s $docker_compose  /usr/bin/docker-compose
   else
      echo "Detected existing docker-compose installation, skipping."
   fi
}


install_qcloud()
{
   if [ ! -d $prefix/qcloud ]; then
      echo "Installing QCloud"
      cd && git clone https://github.com/nutjunkie/qcloud qcloud
      sudo mv qcloud $prefix
      sudo chmod a+x $prefix/qcloud/bin/* 
      cp $prefix/qcloud/aws/setup.sh $HOME

      sudo rm -fr $prefix/qcloud/.git
      sudo rm -fr $prefix/qcloud/aws
      sudo rm -fr $prefix/qcloud/client
      sudo rm -fr $prefix/qcloud/qcmon
      sudo rm -fr $prefix/qcloud/qclic
   else
      echo "Detected existing qcloud installation, skipping."
   fi
}


install_flexnet()
{
   shopt -s nullglob
   set -- $prefix/flexnet*/
   [ "$#" -gt 0 ] && echo "Found flexnet installation in $prefix" && return

   echo "Fetching flexnet"
   cd && aws s3 cp s3://qchem-private/flexnet-$flexnet_version.tgz .
   if [ -e flexnet-$flexnet_version.tgz ]; then
      echo "Installing flexnet $flexnet_version"
      sudo tar xfz  flexnet-$flexnet_version.tgz -C $prefix
      rm flexnet-$flexnet_version.tgz

      sudo chown -R ec2-user.ec2-user $prefix/flexnet-$flexnet_version
      cd /$prefix/flexnet-$flexnet_version/publisher
      sudo ./install_fnp.sh
      cd /$prefix/flexnet-$flexnet_version/services
      sudo cp FNPLicensingService.service /etc/systemd/system/
      sudo cp QChemLicensingService.service /etc/systemd/system/
      sudo systemctl enable /etc/systemd/system/FNPLicensingService.service
      sudo systemctl enable /etc/systemd/system/QChemLicensingService.service
      sudo ln -s $prefix/flexnet-$flexnet_version $prefix/flexnet
   else
	 echo "Failed to fetch flexnet.  Try 'aws configure' to set credentials"
	 exit 1
   fi
}


plumb_pipes()
{ 
   sudo mkdir -p /scratch
   sudo mkdir -p $prefix/qcloud/redis
   sudo systemctl enable $prefix/qcloud/services/piped.service
   sudo systemctl enable $prefix/qcloud/services/QCloud.service
}


build_containers()
{
   echo "Starting docker daemon"
   sudo systemctl enable docker
   sudo systemctl start docker
   cd $prefix/qcloud
   echo "Building qcloud service containers"
   sudo $docker_compose build
   sudo $docker_compose pull redis
   sudo $docker_compose pull rabbitmq
}


cleanup()
{
   echo "Removing AWS credentials and SSH keys"
   rm -fr ~/.aws ~/.ssh 
   echo "Removing logs"
   sudo /usr/local/sbin/ami_cleanup.sh
   echo "System ready for building AMI after shutdown"
}


#  Main program  #

pcfile="/opt/parallelcluster/.bootstrapped"
url="https://github.com/aws/aws-parallelcluster/blob/v$pcluster_version/amis.txt"

echo "Building QCloud AMI"

if [ -e $pcfile ]; then
   pcv=`cat $pcfile | cut -d'-' -f 4`
   echo "pcluster version: $pcv"
else
   echo "File not found: $pcfile"
   echo "Current instance was not launched using a parallel-cluster AMI"
   echo "Ensure base AMI is selected from the list at $url"
   echo "Exiting..."
   exit
fi

if [[ $pcv != $pcluster_version ]]; then
   echo "Required pcluster version:  $pcluster_version"
   echo "Ensure base AMI is selected from the list at $url"
   echo "Exiting..."
   exit
fi

aws configure
install_rpms
install_docker_compose
install_qcloud
install_flexnet
plumb_pipes
build_containers
cleanup

