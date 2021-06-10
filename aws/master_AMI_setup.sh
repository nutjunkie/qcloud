#! /bin/bash

#
#  Installs the necessary packages and builds the Docker containers for
#  the main qcloud/qchem AMI.  This AMI is used for the head node and 
#  the compute nodes of the cluster.
#

prefix=/usr/local
egress=/tmp/egress.pipe
ingress=/tmp/ingress.pipe


install_docker_compose()
{
   if ! command -v /usr/local/bin/docker-compose &> /dev/null; then
      echo "Installing docker-compose"
      sudo curl -L "https://github.com/docker/compose/releases/download/1.28.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      sudo chmod a+x /usr/local/bin/docker-compose 
   fi
}


install_qcloud()
{
   if [ ! -d /usr/local/qcloud ]; then
      echo "Installing QCloud"
      cd && aws s3 cp --recursive s3://qchem-qcloud/qcloud  qcloud
      sudo mv qcloud $prefix
      sudo chmod a+x $prefix/qcloud/bin/* 
   fi
}


install_qchem()
{
   if [ ! -d /usr/local/qchem ]; then
      echo "Fetching Q-Chem"
      cd && aws s3 cp s3://qchem-qcloud/qchem.tgz .
      echo "Installing Q-Chem"
      sudo tar xvfz  qchem.tgz -C $prefix
      rm qchem.tgz
   fi
}


install_rpms()
{
   echo "Installing RPM dependencies"
   sudo yum -y install docker lapack-devel blas-devel
}


plumb()
{
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
