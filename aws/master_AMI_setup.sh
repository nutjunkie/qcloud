#! /bin/bash

#
#  Installs the necessary packages and builds the Docker containers for
#  the main qcloud/qchem AMI.  This AMI is used for both the head node 
#  and the compute nodes of the cluster.
#
#  The base AMI should be the alinux2 image from the appropriate region 
#  in the following list: 
#
#     https://github.com/aws/aws-parallelcluster/blob/v2.10.4/amis.txt
#
#  The image can be built on a t2.micro instance with default resources.
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
   if [ ! -d /usr/local/qcloud ]; then
      cd && aws s3 cp --recursive s3://qchem-qcloud/qcloud  qcloud
      sudo mv qcloud $prefix
      sudo chmod a+x $prefix/qcloud/bin/* 
   else
      echo "Detected existing qcloud installation, skipping."
   fi
}


install_qchem()
{
   echo "Installing Q-Chem"
   if [ ! -d /usr/local/qchem ]; then
      echo "Fetching Q-Chem"
      cd && aws s3 cp s3://qchem-private/qchem.tgz .
      sudo tar xvfz  qchem.tgz -C $prefix
      rm qchem.tgz
   else
      echo "Detected existing qchem installation, skipping."
   fi
}


plumb()
{
   echo "Creating pipes"
   mkfifo $egress
   mkfifo $ingress
}


build_containers()
{
   echo "Starting docker daemon"
   sudo systemctl start docker
   cd $prefix/qcloud
   echo "Building qcloud service containers"
   sudo /usr/local/bin/docker-compose build
}


echo "Building QCloud master AMI"
pcv=`pcluster version`

echo "Installed pcluster version: $pcv"
if [[ $pcv != $pcluster_version ]]; then
   url="https://github.com/aws/aws-parallelcluster/blob/v$pcluster_version/amis.txt"
   echo "Required pcluster version:  $pcluster_version"
   echo "Ensure base AMI is selected from the list at $url"
   echo "Exiting..."
   exit
fi

install_rpms
install_docker_compose
install_qcloud
install_qchem
plumb
build_containers
   
echo ""
echo "Build packages complete, run the following before shutting down this"
echo "instance and creating an AMI:"
echo "  sudo /usr/local/sbin/ami_cleanup.sh"
