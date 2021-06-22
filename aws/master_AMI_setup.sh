#! /bin/bash

#
#  Installs the necessary packages and builds the Docker containers for the
#  main qcloud/qchem AMI.  This AMI is used for both the head node and the
#  compute nodes of the cluster.
#
#  The base AMI should be the alinux2 image from the appropriate region in the
#  following list: 
#
#     https://github.com/aws/aws-parallelcluster/blob/v2.10.4/amis.txt
#
#  The image can be built on a t2.micro instance with default resources.
#
#  This file can be downloaded with the command:
#
#    wget  https://raw.githubusercontent.com/nutjunkie/qcloud/main/aws/master_AMI_setup.sh
#

pcluster_version="2.10.4"

prefix=/usr/local
egress=/tmp/egress.pipe
ingress=/tmp/ingress.pipe


install_rpms()
{
   echo "Installing RPM dependencies"
   sudo yum -y install docker lapack-devel blas-devel
}


install_docker_compose()
{
   echo "Installing docker-compose"
   if ! command -v /usr/local/bin/docker-compose &> /dev/null; then
      echo "Installing docker-compose"
      sudo curl -L "https://github.com/docker/compose/releases/download/1.28.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      sudo chmod a+x /usr/local/bin/docker-compose 
   else
      echo "Detected existing docker-compose installation, skipping."
   fi
}


install_qcloud()
{
   echo "Installing QCloud"
   if [ ! -d $prefix/qcloud ]; then
      cd && git clone https://github.com/nutjunkie/qcloud qcloud
      #cd && aws s3 cp --recursive s3://qchem-qcloud/qcloud  qcloud
      sudo mv qcloud $prefix
      sudo chmod a+x $prefix/qcloud/bin/* 
   else
      echo "Detected existing qcloud installation, skipping."
   fi
}


install_qchem()
{
   if [ ! -d $prefix/qchem ]; then
      echo "Fetching Q-Chem"
      cd && aws s3 cp s3://qchem-private/qchem.tgz .
      if [ -e qchem.tgz ]; then
         echo "Installing Q-Chem"
         sudo tar xvfz  qchem.tgz -C $prefix
         rm qchem.tgz
      else
	 echo "Failed to fetch qchem.  Try 'aws configure' to set credentials"
	 exit 1;
      fi
   else
      echo "Detected existing qchem installation, skipping."
   fi
}


plumb_pipes()
{
   echo "Creating pipes"
   if [ ! -p $egress ]; then
      mkfifo $egress
   fi
   if [ ! -p $ingress ]; then
      mkfifo $ingress
   fi
}


build_containers()
{
   echo "Starting docker daemon"
   sudo systemctl start docker
   cd $prefix/qcloud
   echo "Building qcloud service containers"
   sudo /usr/local/bin/docker-compose build
   sudo /usr/local/bin/docker-compose pull redis
   sudo /usr/local/bin/docker-compose pull rabbitmq
}


print_msg()
{
   echo ""
   echo "Build packages complete."
   echo "Run the following before shutting down this instance and creating an AMI:"
   echo "  sudo /usr/local/sbin/ami_cleanup.sh"
}


pcfile="/opt/parallelcluster/.bootstrapped"
url="https://github.com/aws/aws-parallelcluster/blob/v$pcluster_version/amis.txt"

echo "Building QCloud AMI"

if [ -e $pcfile ]; then
   pcv=`cat $pcfile | cut -d'-' -f 4`
   echo "Installed pcluster version: $pcv"
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

install_rpms
install_docker_compose
install_qchem
install_qcloud
plumb_pipes
build_containers
print_msg   
