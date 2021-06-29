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
#
#  The image can be built on a t2.micro instance with default resources.
#
#  This file can be downloaded within the launched instance with the command:
#
#    wget https://raw.githubusercontent.com/nutjunkie/qcloud/main/aws/master_AMI_setup.sh
#    chmod +x master_AMI_setup.sh
#

pcluster_version="2.10.4"
prefix=/opt
shared=/shared 
docker_compose=/usr/local/bin/docker-compose


install_rpms()
{
   echo "Installing RPM dependencies"
   sudo yum -y install docker lapack-devel blas-devel
}


install_docker_compose()
{
   echo "Installing docker-compose"
   if ! command -v $docker_compose &> /dev/null; then
      echo "Installing docker-compose"
      sudo curl -L "https://github.com/docker/compose/releases/download/1.28.6/docker-compose-$(uname -s)-$(uname -m)" -o $docker_compose
      sudo chmod a+x $docker_compose 
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
   #sudo mkdir -p $volume 
   #sudo chmod 777 $volume

   sudo mkdir -p $shared/qcloud
   sudo chown ec2-user.ec2-user $shared/qcloud
   sudo chmod 775 $shared/qcloud

   sudo mkdir -p $prefix/qcloud/redis
   #sudo chown ec2-user.ec2-user $prefix/qcloud/redis
   #sudo chmod a+w $prefix/qcloud/redis

   echo "@reboot $prefix/qcloud/bin/piped" > crontab.txt
   echo "@reboot systemctl start docker" >> crontab.txt
   echo "@reboot cd $prefix/qcloud && sudo $docker_compose up -d" >> crontab.txt
   sudo crontab crontab.txt
   rm crontab.txt
}


build_containers()
{
   echo "Starting docker daemon"
   sudo systemctl start docker
   cd $prefix/qcloud
   echo "Building qcloud service containers"
   sudo $docker_compose build
   sudo $docker_compose pull redis
   sudo $docker_compose pull rabbitmq
}


print_msg()
{
   echo ""
   echo "Build packages complete."
   echo "Run the following commands before shutting down this instance and creating an AMI:"
   echo "  sudo /usr/local/sbin/ami_cleanup.sh"
   echo "  rm master_AMI_setup.sh"
   echo "  rm -fr ~/.aws ~/.ssh"
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
