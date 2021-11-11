#! /bin/bash

#  Installs the required software for QCloud services

shared=/efs

qc=$shared/qchem
qcscratch=$shared/scratch
qclocalscratch=/scratch


qcloud_setup()
{
   sudo mkdir -p $shared/jobs
   sudo /opt/qcloud/bin/slurm_resources
}


get_memory()
{
   echo 8000
}


qchem_setup()
{
   sudo mkdir -p $qc/config
   sudo mkdir -p $qcscratch

   config="$qc/config/shellvar.txt"
   echo "QC          /efs/qchem"       >  $config
   echo "QCPLATFORM  LINUX_Ix86_64"    >> $config
   echo "QCAUX       /efs/qchem/qcaux" >> $config
   echo "QCSCRATCH   /efs/scratch"     >> $config
   echo "QCLOCALSCR  /scratch"         >> $config
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
   sudo mkdir -p $prefix/qchem/qcaux/licenses
   sudo cp $1 $prefix/qchem/qcaux/licenses/qchem.lic
   sudo mkdir -p $prefix/flexnet/licenses
   sudo cp $1 $prefix/flexnet/licenses/qchem_aws.lic
   sudo systemctl restart QChemLicensingService.service
   echo "Licnse installed"
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

qcloud_setup
qchem_setup
enable_services
/opt/qcloud/qclic/qcinstall.sh
