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
#
#  Once the instance has been stopped, an AMI can be created, right click on the instance ID:
#     Images and templates -> Create image

pcluster_version="2.10.4"
flexnet_version="11.18.0"
qchem_version="540"
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
   else
      echo "Detected existing docker-compose installation, skipping."
   fi
}


install_qcloud()
{
   if [ ! -d $prefix/qcloud ]; then
      echo "Installing QCloud"
      cd && git clone https://github.com/nutjunkie/qcloud qcloud
      #cd && aws s3 cp --recursive s3://qchem-qcloud/qcloud  qcloud
      sudo mv qcloud $prefix
      sudo chmod a+x $prefix/qcloud/bin/* 

      sudo rm -fr $prefix/qcloud/.git
      sudo rm -fr $prefix/qcloud/aws
      sudo rm -fr $prefix/qcloud/client
   else
      echo "Detected existing qcloud installation, skipping."
   fi
}


install_qchem()
{
   qc="qchem_$qchem_version"

   shopt -s nullglob
   set -- $prefix/qchem*/
   [ "$#" -gt 0 ] && echo "Detected existing qchem installation in $prefix" && return

   echo "Fetching Q-Chem"
   cd && aws s3 cp s3://qchem-private/$qc.tgz .
   if [ -e $qc.tgz ]; then
      echo "Installing Q-Chem"
      sudo tar xfz  $qc.tgz -C $prefix
      sudo ln -s $prefix/$qc $prefix/qchem
      rm $qc.tgz
   else  
      echo "Failed to fetch qchem.  Try 'aws configure' to set credentials"
      exit 1
   fi
}

install_license()
{
   cp $prefix/qcloud/qclic/qcloud_install.sh $HOME

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
   sudo mkdir -p $prefix/qcloud/redis
   sudo systemctl enable docker
   sudo systemctl enable $prefix/qcloud/services/piped.service
   sudo systemctl enable $prefix/qcloud/services/QCloud.service
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
   echo ""
   echo "  sudo /usr/local/sbin/ami_cleanup.sh"
   echo "  rm -fr ~/.aws ~/.ssh master_AMI_setup.sh"
}


cleanup()
{
   echo "Removing AWS credentials and SSH keys"
   rm -fr ~/.aws ~/.ssh master_AMI_setup.sh
   echo "Removing logs"
   sudo /usr/local/sbin/ami_cleanup.sh
}


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
#install_qchem
install_qcloud
#install_flexnet
plumb_pipes
build_containers
#print_msg   
cleanup

