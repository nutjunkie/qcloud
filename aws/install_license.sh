#! /bin/bash

#  Installs the Q-Chem license file to the required locations
#  and restarts necessary services

prefix=/opt

if [ "$#" -eq 1 ] && [ -f $1 ]; then
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
   echo ""
   echo "If you do not have license file, send the output from the"
   echo "following command to license@q-chem.com: "
   echo ""
   echo "/opt/flexnet/bin/lmutil lmhostid -ptype AMZN -eip"

   exit 1
fi
