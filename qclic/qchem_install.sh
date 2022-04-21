#! /bin/bash

#  Installs the required software for QCloud services

shared=/efs

qc=$shared/qchem
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
   mkdir -p $qc/config
   mkdir -p $qcscratch

   config="$qc/config/shellvar.txt"
   echo "QC          $qc"              >  $config
   echo "QCPLATFORM  LINUX_Ix86_64"    >> $config
   echo "QCAUX       $qc/qcaux"        >> $config
   echo "QCSCRATCH   $qcscratch"       >> $config
   echo "QCLOCALSCR  $qclocalscratch"  >> $config
   echo "QCRSH       ssh"              >> $config
   echo "QCMPI       seq"              >> $config

   pref="$qc/config/preferences"
   qcmem=$(get_memory)
   echo "\$rem"                >  $pref
   echo " MEM_TOTAL  $qcmem "  >> $pref
   echo "\$end"                >> $pref
}


enable_services()
{
   sudo systemctl enable $prefix/qcloud/services/QCloud.service
}


install_license()
{
   host=`hostname`
   sed -i -r "1s/^([^ ]+) [^ ]+/\1 $host/" $1

   sudo mkdir -p $qc/qcaux/licenses
   sudo cp $1 $qc/qcaux/licenses/qchem.lic
   sudo mkdir -p /opt/flexnet/licenses
   sudo cp $1 /opt/flexnet/licenses/qchem_aws.lic
   sudo systemctl restart QChemLicensingService.service
   echo "License installed"
   echo "Starting QCloud services"
   sudo systemctl restart QCloud.service
}


get_flex_id()
{
   eip=$(/opt/flexnet/bin/lmutil lmhostid -ptype AMZN -eip )
   eip=$(echo $eip | awk '{print $NF}')
   echo $eip
}


export qcloud_dir=/opt/qcloud
export qcloud_qc=$qc
export qcloud_qcscratch=$qcscratch
export qcloud_flexid=$(get_flex_id)
export qcloud_qclocalscratch=$qclocalscratch

if [ "$#" -eq 1 ]; then
    install_license $1
else
    qcloud_setup
    qchem_setup
    enable_services
    /opt/qcloud/qclic/qcinstall.sh
fi
