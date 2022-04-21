#! /bin/bash

#  Setup script for installing the Q-Chem license and QCloud services.

qc=/qchem
shared=/efs

qcscratch=$shared/scratch
qclocalscratch=/tmp


qcloud_setup()
{
   mkdir -p $shared/jobs
   sudo /opt/qcloud/bin/slurm_resources
   /opt/qcloud/config/config.py
}


get_memory()
{
   echo 8000
}


qchem_setup()
{
   sudo mkdir -p  $qc/config
   sudo mkdir -p  $qcscratch
   sudo chmod 777 $qcscratch

   config="/tmp/shellvar.txt"
   echo "QC          $qc"              >  $config
   echo "QCPLATFORM  LINUX_Ix86_64"    >> $config
   echo "QCAUX       $qc/qcaux"        >> $config
   echo "QCSCRATCH   $qcscratch"       >> $config
   echo "QCLOCALSCR  $qclocalscratch"  >> $config
   echo "QCRSH       ssh"              >> $config
   echo "QCMPI       seq"              >> $config

   sudo mv $config $qc/config/

   pref="/tmp/preferences"
   qcmem=$(get_memory)
   sudo echo "\$rem"                >  $pref
   sudo echo " MEM_TOTAL  $qcmem "  >> $pref
   sudo echo "\$end"                >> $pref

   sudo mv $pref $qc/config/
}


enable_services()
{
   echo "Starting QCloud services"
   if [ ! -f /etc/systemd/system/QCloud.service ]; then
      sudo systemctl enable /opt/qcloud/services/QCloud.service
   fi
   sudo systemctl restart QCloud.service
}


install_license()
{
   if [ ! -f $1 ]; then
      echo "Could not find license file: $1"
      return 1
   fi

   echo "Installing Q-Chem license file: $1"
   host=`hostname`
   sed -i -r "1s/^([^ ]+) [^ ]+/\1 $host/" $1

   sudo mkdir -p $qc/qcaux/licenses
   sudo cp $1 $qc/qcaux/license/qchem.lic
   sudo mkdir -p /opt/flexnet/licenses
   sudo cp $1 /opt/flexnet/licenses/qchem_aws.lic
   sudo systemctl restart QChemLicensingService.service
   echo "License installed"
}


get_flex_id()
{
   eip=$(/opt/flexnet/bin/lmutil lmhostid -ptype AMZN -eip )
   eip=$(echo $eip | awk '{print $NF}')
   echo $eip
}


usage()
{
   echo "Usage: $0                - generate license information"
   echo "       $0 <license_file> - install Q-Chem license" 
}


if [ "$#" -eq 0 ]; then
   echo "Generating license information."
   echo "Please email the following information along with"
   echo "your Q-Chem order number to office@q-chem.com:"
   echo ""
   get_flex_id
elif [ "$#" -eq 1 ]; then
    install_license $1 && \
    qchem_setup && \
    enable_services && \
    qcloud_setup 
else
   echo "Invalid number of arguments"
   usage
fi
