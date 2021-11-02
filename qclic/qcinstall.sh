#!/bin/bash
#
#     Confidential property of Q-Chem, Inc.
#     Copyright (c) 1993 by Q-Chem, Inc. (unpublished)
#     All rights reserved.
#
#     The above copyright notice is intended as a precaution against
#     inadvertent publication and does not imply publication or any
#     waiver of confidentiality. The year included in the foregoing
#     notice is the year of creation. This software product contains
#     proprietary, confidential information and trade secrets of
#     Q-Chem, Inc. and its licensors. No use may be made of this
#     software except according to written agreement with Q-Chem, Inc.
#

if [ "x${DBGQCINSTALL}" == "xTRUE" ] ; then
set -x
fi

#     installer version must match update.list ###
installer_version=16

function trim_var 
{ 
    local string="$1" 
    echo "$string" | sed -e 's/^[ \t]*//' | sed -e 's/[ \t]*$//' 
} 

function array_print
{                                                                        
  local a=("${!1}")                                                      
  local i; for (( i=0 ; i<${#a[@]} ; i++ )) ; do echo $i "--"  "${a[i]}"; done          
}                                                                        

function isdigit    # Tests whether *entire string* is numerical.
{                   # In other words, tests for integer variable.
  [ $# -eq 1 ] || return 9;
  if [ "x$1" == "x" ] ; then return 9; fi
  case $1 in
    *[!0-9]*|"") return 9;;
              *) return 0;;
  esac
}

function ftp_get    #ftp_site dir file
{
   ftp -v -p -n $1 << EOF1
   user anonymous   anonymous@q-chem.com 
   cd  $2
   binary
   get $3 
   quit
EOF1
}

function ftp_get_qchem #dir file
{
   ftp -v -p -n ftp.q-chem.com << EOF2
   user anonymous@q-chem.com  anonymous
   cd  $1
   binary
   get $2 
   quit
EOF2
   chmod +x $2
}

function test_wget
{
    if [ "x${with_wget}" == "xcurl" ]; then
       ${with_wget} -f http://www.google.com >/dev/null 2>&1 
       if [ $? == 0  ] ; then  rm index.html >/dev/null 2>&1; return 0 ; fi
       ${with_wget} -f http://www.q-chem.com >/dev/null 2>&1 
       if [ $? == 0  ] ; then  rm index.html >/dev/null 2>&1; return 0 ; fi
       ${with_wget} -f http://www.yahoo.com >/dev/null 2>&1 
       if [ $? == 0  ] ; then  rm index.html >/dev/null 2>&1; return 0 ; fi
    else
       chmod a+x "${with_wget}" >/dev/null 2>&1
       ${with_wget} --timeout=11 http://www.google.com >/dev/null 2>&1 
       if [ $? == 0  ] ; then  rm index.html >/dev/null 2>&1; return 0 ; fi
       ${with_wget} --timeout=11 https://downloads.q-chem.com >/dev/null 2>&1 
       if [ $? == 0  ] ; then  rm index.html >/dev/null 2>&1; return 0 ; fi
       ${with_wget} --timeout=11 http://www.yahoo.com >/dev/null 2>&1 
       if [ $? == 0  ] ; then  rm index.html >/dev/null 2>&1; return 0 ; fi
    fi
    return 9
}

get_qcplatform()
{
        local ARCH=""
        local os="`uname -s 2>/dev/null`"
        local ht="`uname -m 2>/dev/null`"
        case "$os,$ht" in
        AIX*,* )                ARCH=IBM_SP ;;
        *HP*,ia64 )             ARCH=HP_UX ;;
        IRIX*,* )               ARCH=SGI ;;
        SunOS,sun4* )           ARCH=SUN_SUNOS ;;
        Linux,i[3456]86 )       ARCH=LINUX_Ix86 ;;
        Linux,x86_64 )          ARCH=LINUX_Ix86_64 ;;
        Darwin,i[3456]86 )      ARCH=MAC_Ix86 ;;
        Darwin,x86_64 )         ARCH=MAC_Ix86 ;;
        Darwin,arm64 )          ARCH=MAC_Ix86 ;;
        esac
        echo $ARCH
        if [ "x${ARCH}" == "x" ] ; then return 9; fi
        return 0
}

#--------------------------------------
#
# 1.  utility functions
#
#--------------------------------------

function test_internet_connection
{
    ping -W5 -c3 8.8.8.8  >/dev/null 2>&1 
    if [ $? == 0 ] ; then  return 0 ; fi
    sleep 1
    ping -W5 -c3 4.2.2.1  >/dev/null 2>&1 
    if [ $? == 0 ] ; then  return 0 ; fi
    return 9
}

function setup_wget
{
  local curdir=`pwd`
  local plat=$(get_qcplatform)
  local stat
  for i in 1; do
    if [ "x${with_wget}" != "x" ] ; then
    test_wget
    stat=$?
    if [ $stat == 0 ]; then break; fi
    fi

    with_wget=$(which wget 2>/dev/null)
    test_wget
    stat=$?
    if [ $stat == 0 ]; then break; fi
     
    with_wget='curl'
    test_wget
    stat=$?
    if [ $stat == 0 ]; then break; fi

    with_wget=${curdir}/wget_${plat}
    if [   -e "${with_wget}" ]; then
    test_wget
    stat=$?
    if [ $stat == 0 ]; then break; fi  
    fi

    with_wget=${QC}/bin/wget_${plat}
    if [   -e "${with_wget}" ]; then
    test_wget
    stat=$?
    if [ $stat == 0 ]; then break; fi  
    fi

    with_wget=${curdir}/bin/wget_${plat}
    test_wget
    stat=$?
    if [ $stat == 0 ]; then break; fi

    with_wget=${curdir}/wget_${plat}
    get_file_from_installdir "wget_${plat}"
    chmod +x ${with_wget} >/dev/null 2>&1
    test_wget
    stat=$?
    if [ $stat == 0 ]; then break; fi

    with_wget=${curdir}/wget_${plat}
    ftp_get_qchem download/utils wget_${plat}  >/dev/null 2>&1
    chmod +x ${with_wget} >/dev/null 2>& 1
    test_wget
    stat=$?
    if [ $stat == 0 ]; then break; fi  
    if [ $stat != 0 ]; then 
       curl -sf https://downloads.q-chem.com/utils/wget_${plat} -o wget_${plat} 
       stat=$?
       if [ $stat != 0 ]; then break; fi
       chmod +x  wget_${plat} 
       test_wget
       stat=$?
       if [ $stat == 0 ]; then echo "  wget is ${with_wget}" ; fi
       if [ $stat == 0 ]; then break; fi
    fi
    
    with_wget=${curdir}/wget_${plat}
    printf " configuring utilities ... may take 1 - 2 minutes, please wait. \n"
       ftp_get ftp.gnu.org gnu/wget wget-1.9.tar.g >/dev/null 2>&1
       gunzip wget-1.9.tar.gz >/dev/null 2>&1
       tar xvf wget-1.9.tar >/dev/null 2>&1
       cd wget-1.9 >/dev/null 2>&1
       ./configure >/dev/null 2>&1; 
       make >/dev/null 2>&1; 
       cp -f src/wget ${with_wget}>/dev/null 2>&1
       cd $curdir
    test_wget
    stat=$?
    if [ $stat == 0 ]; then break; fi  

  done
  if [ $stat != 0 ]; then with_wget=""; fi
#  if [ $stat != 0 ]; then 
#    echo "Failed to setup wget, which is required for Q-Chem installation/update" 
#    echo "Please download wget_${plat} here "
#    echo "http://www.q-chem.com/download/exes_latest/wget_${plat}"
#    echo "and rerun the installation using command "
#    echo "qcinstall --with-wget=/path_to_your_wget"
#  fi
  return $stat
}

function get_file_from_installdir
{
   local ifile=$1; 
   if [ "x$ifile" == "x" ]; then return 7; fi
   if [ "x${with_installdir}" != "x" ] ; then
      local ifiletmp=""
      if [ -e ${with_installdir}/${ifile} ] ; then ifiletmp="${with_installdir}/${ifile}" ; fi
      if [ -e ${with_installdir}/bin/${ifile} ] ; then ifiletmp="${with_installdir}/bin/${ifile}" ; fi
      if [ -e ${with_installdir}/exes/${ifile} ] ; then ifiletmp="${with_installdir}/exes/${ifile}" ; fi
      if [ -e ${with_installdir}/tarfiles/${ifile} ] ; then ifiletmp="${with_installdir}/tarfiles/${ifile}" ; fi
      if [ -e ${with_installdir}/.update/${ifile} ] ; then ifiletmp="${with_installdir}/.update/${ifile}" ; fi
      if [ "x${ifiletmp}" != "x" ] ; then
         cp -f ${ifiletmp} ${ifile}
         return 0
      fi 
      ifiletmp=$(find "${with_installdir}" -name "${ifile}" 2>/dev/null | head -n 1)
      if [ "x${ifiletmp}" != "x" ] ; then
         cp -f ${ifiletmp} ${ifile}
         return 0
      fi
   fi
   return 7
}

function get_remote_install_file
{
#set -x
   local ifile=$1; 
   #
   if [ "x$ifile" == "x" ]; then
      echo "Failed in $0 : empty argument" 
      return 7
   fi
   #rm -f ./${ifile} >/dev/null 2>&1
   local dirx=$(pwd -P)
   if [ ! -w $dirx ] ; then
      echo "Failed in $0 : current directory $dirx write permission error" 
      return 6
   fi

   # test if running from installation package
   get_file_from_installdir ${ifile}
   if [ $? == 0 ]; then return 0 ; fi

   local target_dir=qcinstall
   if [ "x${with_target}" != "x" ] ; then
      target_dir="${with_target}/.update"
      #echo " getting update files from target directory ${target_dir}"
   fi 
   local iret=5
   local iixx; for iixx in 1 2 3 ; do
          if [ "x${iixx}" == "x2" ]; then
             echo " The installer is experiencing issues downloading Q-Chem files. Please wait."
          fi
          rm -f ${ifile}.tmp 2>/dev/null
          statxx=-1
          if [ "x${with_wget}" == "xcurl" ]; then
             ${with_wget} -sf --connect-timeout 15 https://downloads.q-chem.com/${target_dir}/${ifile} -o ${ifile} 2>/dev/null
             if [ $? == 0 ]; then
                iret=0
                break
             fi
          else
             ${with_wget} -O ${ifile}.tmp -T 15 -t 1 https://downloads.q-chem.com/${target_dir}/${ifile} > /dev/null 2>&1
             if [ $? == 0 ]; then
                #ls -l .
                mv -f ${ifile}.tmp  ${ifile}
                iret=0
                break
             fi
          fi
   done
#set +x
   return ${iret}
   #if [ -e ./${ifile} ] ; then return 0; else return 9 ; fi
}

function get_remote_install_script
{
   get_remote_install_file "$1"
   if [ $? != 0 ]; then return 9; fi
   chmod 700 ./"$1"
   return 0
}

function err_exit 
{
   local msg="$1"
   echo "$msg"
   exit 9
}

welc_install_msg()
{
echo
echo
cat << END_OF_WELC_INSTALL
      ...... Welcome to Q-Chem installation ......
    
The installation of Q-Chem requires some information about your order
and your computing environment. Please read it before you continue the installation. 
Press "x" or Ctrl-C to exit installation, press <Enter> to continue.
END_OF_WELC_INSTALL

while [ true ] ; do
   read tmp_in_welc
   if [ x"$tmp_in_welc" = "xx" ]; then
        exit 0;
   fi
   if [ x"$tmp_in_welc" = x ]; then
        break;
   fi
done
}

print_welcome_msg() {
clear
echo
echo " $(tput bold)******************************************************************"
echo " *                                                                *"
echo " *                Welcome to Q-Chem Installation                  *"
echo " *                                                                *"
echo " ******************************************************************$(tput sgr0)"
echo
}

print_welcome_online() {
echo " This is the online installation package for Q-Chem."
echo " Internet access is required to download the distribution."
echo
}

function check_updatedir 
{
   local updateDir="$1"
   if [ ! -e "$updateDir" ] ; then  mkdir -p $updateDir ; fi
   if [ ! -w "$updateDir" ] ; then
      ls -l "$updateDir"
      err_exit "failed in $0 : ${updateDir} not exist or permission error"
   fi
   return 0
}



check_qc_path()
{
   ##dir must begin with "/" end without "/" & without any blank
   local qcdir=$1
   local xcnt1 xcnt2
   let xcnt1=`echo "$qcdir" | grep -c -e "^\/"`
   let xcnt2=`echo "$qcdir" | grep -c -e " "`
   if [ $xcnt1 -eq 0 ]; then
     echo "   -- path format error: absolute path required -- "
     return 8
   fi
   if [ $xcnt2 -ne 0 ]; then
     echo "   -- path format error: no blank/space allowed -- "
     return 9
   fi
   return 0
}

check_qcdir_new()
{
   local qcdir=$1
   # if exist must be write permission, empty, or empty & confirm
   if [ -e "$qcdir" ] ; then
      if [ ! -w "$qcdir" ] ; then
         echo " Failed to pass new QC dir test: $qcdir write permission error" 
         return 9
      fi
      # if not empty ask whether to overwrite
      local dirlist=`ls -A "$qcdir"`
      if [ "x${dirlist}"  != "x" ]; then
         echo
         echo " The Directory: $qcdir is not empty."
         echo " Do you want to install Q-Chem in this location? " 
         local yon; local leftover
         while [ true ]; do
            printf " Press <Enter> or 'y' to confirm, 'n' to reselect, 'x' to exit\n\n > "
            read  yon leftover
            if [ "x$yon" == "xx" ] || [ "x$yon" == "xn" ] || [ "x$yon" == "xy" ] || [ "x$yon" == "x" ] ; then 
               break
            fi
         done
         if [ "x$yon" == "xn" ]; then return 9; fi
         if [ "x$yon" == "xx" ]; then exit 9; fi
      fi
   fi
   # if not exist, test 'mkdir -p'
   if [ ! -e "$qcdir" ] ; then
      mkdir -p "$qcdir" 2>/dev/null
      if [ $? != 0 ]; then 
         echo "  Failed to pass new QC dir test: could not make new dir $qcdir"
         return 9
      fi
   fi 
   return 0 
}

function select_qcdir_new
{
  local IDDEFAULT=0
  if [ -e '/usr/local/qchem' ]; then
     dirlist=`ls -A /usr/local/qchem`
     if [ "x$dirlist" = "x" -a -w /usr/local -a -w /usr/local/qchem ]; then
        IDDEFAULT=1
     fi
  else
     if [ -w /usr/local ]; then IDDEFAULT=1; fi
  fi
   
  local qcdir
  while [ true ]; do
     echo
     if [ $IDDEFAULT = 1 ]; then
        echo " Please specify the path of the new Q-Chem directory,"
        echo " type 'x' to exit program, <Enter> to use (/usr/local/qchem)"
     else
        echo " Please specify the path of the new Q-Chem installation directory,"
        echo " or type 'x' to exit" 
     fi
     printf "\n > " 
     read qcdir leftover
     #
     if [ "x$qcdir" == "xx" ] ; then exit 9; fi
     if [ "x$qcdir" == "x" ] ; then continue; fi
     let xcnt1=`echo "$qcdir" | grep -c -e "^\/"`
     if [ $xcnt1 -eq 0 ]; then
        echo "   -- path format error: absolute path required -- "
        continue; 
     fi
     let xcnt2=`echo "$qcdir" | grep -c -e " "`
     if [ $xcnt2 -ne 0 ]; then
        echo "   -- path format error: no blank/space allowed -- "
        continue; 
     fi
     #
     qcdir=`echo "$qcdir" | sed 's/\/$//'`   #remove ending '/'
     check_qcdir_new "$qcdir"
     if [ $? == 0 ]; then QC="$qcdir"; break; fi
  done
}

function is_qcdir
{
   local qcdir="$1"
   if [ ! -e "$qcdir/exe" ] || [ ! -e "$qcdir/version.txt" ] || [ ! -e "$qcdir/bin" ] ; then
         return 9
   fi
   if [ ! -w "$qcdir" ] ; then
         return 8
   fi
   return 0 
}

function select_qcdir_update
{
  local qcdir
  while [ true ]; do
     echo
     echo " Please specify the path of the Q-Chem directory to be updated"
     printf " > " 
     read qcdir leftover
     #
     if [ "x$qcdir" == "xx" ] ; then exit 9; fi
     if [ "x$qcdir" == "x" ] ; then continue; fi
     let xcnt1=`echo "$qcdir" | grep -c -e "^\/"`
     if [ $xcnt1 -eq 0 ]; then
        echo "   -- path format error: absolute path required -- "
        continue; 
     fi
     let xcnt2=`echo "$qcdir" | grep -c -e " "`
     if [ $xcnt2 -ne 0 ]; then
        echo "   -- path format error: no blank/space allowed -- "
        continue; 
     fi
     #
     is_qcdir "$qcdir"
     if [ $? == 9 ]; then 
     echo "   selected directory does not have correct Q-Chem structure"; continue ; fi
     if [ $? == 8 ]; then 
     echo "   selected directory does not have write permission"; continue ; fi
     if [ $? == 0 ]; then QC="$qcdir"; break; fi
  done
}

function select_qcdir
{
   with_update=0
   while [ true ]; do
      yon=""
      echo " Would you like to upgrade your current Q-Chem or install a new one?"
      printf " Type 'u' to upgrade, 'n' for new installation, 'x' to exit > "
      read yon leftover
      if [ "x$yon" == "xu" ] || [ "x$yon" == "xn" ] || [ "x$yon" == "xx" ]; then break; fi
   done
   if [ "$yon" == 'x' ] ; then 
      err_exit 
   fi
   if [ "$yon" == 'n' ] ; then
      with_update=0
      select_qcdir_new
   fi
   if [ "$yon" == 'u' ] ; then 
      with_update=1
      select_qcdir_update
   fi
   #echo "Q-Chem will be installed in directory $QC"
}

function print_usage
{
cat << END_OF_PRINT_USAGE

Usage of $1

- standard interactive installation/upgrade

  $1

- update the to the latest distribution
   
  $1 --update
     
- only print out update information, do not update

  $1 --update --check

- rerun license data collection

  $1 --update-license
     
- print this message
  
  $1 --help 

END_OF_PRINT_USAGE
}

#
#  start of program
#
installdir=$(dirname $0)
installer_dir=$(cd ${installdir} >/dev/null 2>&1; pwd -P)
installer_name=$(basename $0)
installer=${installer_dir}/${installer_name}
echo " Install dir is ${installdir}"
echo " Installer is ${installer}"
with_installdir=""
if [ -e ${installer_dir}/.install.qc ] ; then
  with_installdir="${installer_dir}"
fi
export with_installdir

with_target=""
with_update=0
with_update_check=0
while [ $# -gt 0 ] 
do
    case $1 in
    -h | --help )
       print_usage $0
       exit 0
       ;;
     --check | -check )
       with_update_check=1
       ;;
    -u | --update | -update )
       with_update=1
       ;;
    --update-license | -update-license | --update-lic | -update-lic ) 
       with_update=2
       ;;
    --with-wget=* )
       with_wget="$1"
       with_wget=${with_wget/--with-wget=/}
       ;;
    --with-target=* )
       with_target="$1"
       with_target=${with_target/--with-target=/}
       ;;
    *)
       echo "invalid flag $1 "
       exit 9
       ;;
    esac
    shift
done

if [ "x${with_update}" != "x0" ] && [ "x${with_target}" != "x" ]; then
   print_usage $0
   echo
   echo " ERROR: Flags --update and --with-target cannot be used together."
   exit 9
fi

#--------------------------------------
#     QC directory     
#--------------------------------------

if [ "x${with_update}" == "x0" ] ; then
   print_welcome_msg
   if [ "x${with_installdir}" == "x" ] ; then
      print_welcome_online
   fi
   #select_qcdir
   select_qcdir_new
fi

if [ "x${with_update}" == "x1" ] || [ "x${with_update}" == "x2" ]; then
   if [ "x${QC}" == "x" ]; then
      qctmp=$(dirname "$0")
      qctmp=$(cd $qctmp >/dev/null 2>&1 ; pwd -P )
      is_qcdir "$qctmp"
      if [ $? == 0 ] ; then
         QC="$qctmp" 
      else
         select_qcdir_update
      fi
   fi
   if [ "x${QC}" == "x" ]; then
      err_exit  " Environment varaible QC is not specified properly for upgrade."
   fi
fi

if [ "x${with_update}" == "x0" ] ; then
   echo 
   echo " Q-Chem will be installed in $QC"
   echo
else
   echo 
   echo " Q-Chem will be updated in $QC"
   echo
fi

#--------------------------------------------------
#     Prepare .update directory .. wget script list
#--------------------------------------------------

with_updatedir=$QC/.update
check_updatedir ${with_updatedir}
if [ $? != 0 ]; then
   err_exit "  Failed in check_updatedir: update directory ${updateDir} permission error" 
fi

curdir=`pwd`

cd ${with_updatedir}

#--------------------------------------------------------
#     Determine target based on current version if update
#--------------------------------------------------------

if [ "x${with_update}" == "x1" ] || [ "x${with_update}" == "x2" ]; then
   if [ -f $QC/version.txt ]; then
     c_ver=$(cat $QC/version.txt)
     c_tgt=`echo $c_ver  | awk -F"." '{for(i=1;i<=2;i++){if (i<=NF) printf $i; else printf "0"} }'`
     with_target="qc${c_tgt}"
   fi
fi

if [ "x${with_installdir}" == "x" ] ; then
   if [ "x${with_wget}" != "xnointernet" ] ; then
     setup_wget
     if [ $? != 0 ]; then
       echo " The online installer failed to download the Q-Chem distribution."
       echo " Please visit https://downloads.q-chem.com/ to obtain"
       echo " the offline installation package."
       err_exit ""
     fi
   fi
fi

istat=0
get_remote_install_file   update.list
istat=$?
if [ $istat == 0 ]; then 
   installer_version_new=`grep -i installer_version update.list | awk -F";" '{print $2}'`
   installer_version_new=$(trim_var ${installer_version_new})
   isdigit ${installer_version_new}
   istat=$?
   if [ $istat != 0 ] ; then
      echo " installer_version_new is ${installer_version_new} "
      emsg="Error: liveupdate list not valid, failed to pass verification."
   fi
else
   emsg="Error obtaining live update list"
fi
if [ $istat != 0 ] ; then
      echo
      echo " ** $emsg"
      echo
      echo " Failure getting live update list (error ${istat})."
      echo " Please check your internet connection and try again at a later time,"
      echo " or contact support@q-chem.com if this problem persists."
      echo
      exit 9
fi
if [[ ${installer_version} -lt  ${installer_version_new} ]] ; then
     get_remote_install_script ${installer_name}
     cp -f ${installer_name} ${installer}
     if [ $? != 0 ] ;  then
         echo "  Failed to update installer ${installer} "
         echo "  from version ${installer_version} to version ${installer_version_new}. "
         echo "  Please check directory $(dirname ${installer}) write permission " 
         echo
         exit 7
     fi
     echo
     echo "  The installer ${installer} has been upgraded " 
     echo "  from version ${installer_version} to version ${installer_version_new}. "
     echo "  Please rerun Q-Chem installation/updating" 
     echo
     exit 8
fi

installer_scripts=`grep installer_scripts update.list | awk -F";" '{print $2}'`
for iscript in ${installer_scripts} ; do
   #echo ${iscript}
   get_remote_install_script ${iscript}
   if [ $? != 0 ]; then
      #cp $curdir/liveupdate.sh $updatedir
      echo "  Failed to obtain live update program ... "
      echo "  Please run the program at a later time" 
      exit 9
   fi
done


#-------------------------------------- 
# 
#     Invoke live update procedure
#
#-------------------------------------- 
export QC
export with_wget
export with_update
export with_updatedir
export with_update_check

. ${with_updatedir}/liveupdate.sh | tee ${QC}/install.log

cd $QC
exit 0
