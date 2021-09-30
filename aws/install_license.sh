#! /bin/bash
  
#  Installs the Q-Chem license file to the required locations
#  and restarts necessary services

prefix=/opt

if [ -f $1 ]; then
   sudo mkdir -p $prefix/qchem/qcaux/licenses
   sudo cp $1 $prefix/qchem/qcaux/licenses/qchem.lic
   sudo mkdir -p $prefix/flexnet/licenses
   sudo cp $1 $prefix/flexnet/licenses/qchem_aws.lic

   sudo systemctl restart QChemLicensingService.service
   echo "Licnse installed"
   echo "Starting QCloud services"
   sudo systemctl restart QCloud.service
   sudo /opt/qcloud/bin/slurm_resources
else
   echo "Usage: $0 <license_file>"
   exit 1
fi
