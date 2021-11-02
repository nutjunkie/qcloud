
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
#     Author: Zhengting Gan (2012-09)
#


function isdigit    # Tests whether *entire string* is numerical.
{             # In other words, tests for integer variable.
  [ $# -eq 1 ] || return 9;
  if [ "x$1" == "x" ] ; then return 9; fi
  case $1 in
    *[!0-9]*|"") return 9;;
              *) return 0;;
  esac
}

function tolower
{
  echo "$1" | awk '{print tolower($0)}'
}

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

function wget_from_installdir                                                                                                         
{                                                                                                                                         
   local ifile="$1";                                                                                                                        
   if [ "x$ifile" == "x" ]; then return 7; fi 
   if [ "x${with_installdir}" != "x" ] ; then
      local ifiletmp=$(find "${with_installdir}" -name "${ifile}" 2>/dev/null | head -n 1) 
      if [ "x${ifiletmp}" != "x" ] ; then
         if [ -e "${ifiletmp}" ] ; then
           cp -f ${ifiletmp} ${ifile}
           return 0
         fi
      fi
   fi
   return 7
}  

function wget_url 
{
   #for  ifile in gcfg_util.sh gcfg_compiler.sh gcfg_mpi.sh gcfg_libs.sh makefile make.lib make.qcopt ; do
   local url=$1;
   local ifile=$(basename "$url")
   if [ "x$ifile" == "x" ]; then
      echo "Failed in $0 : empty argument" 
      return 9
   fi
   local curdir=$(pwd 2>/dev/null)
   if [ ! -w "${curdir}" ] ; then
      echo "Failed in $0 : directory permission error" 
      return 9
   fi

   # -- for downloaded whole installer package
   wget_from_installdir "${ifile}"
   if [ $? == 0 ] ; then
      echo "$2"
      return 0
   fi

   #
   local iixx; for iixx in 1 2 3 ; do
   if [ "x$2" != "x" ] ; then
start_spinner  "$2"
   fi
      local stat=$?
      if [ "x${with_wget}" != "xnointernet" ]; then
         if [ "x${with_wget}" == "xcurl" ]; then
            curl -sf ${url} -o $ifile 2>/dev/null
            stat=$?
         else   
            ${with_wget:-wget} -N ${url} > /dev/null 2>&1
            stat=$?
         fi
      fi
   if [ "x$2" != "x" ] ; then
stop_spinner
   fi
      if [ $stat == 0 ]; then break; fi
   done
   ## fi
   if [ -e ./${ifile} ] ; then return 0; else return 9 ; fi
}

function get_qcplatform
{
        local ARCH=""
        local os="`uname -s 2>/dev/null`"
        local ht="`uname -m 2>/dev/null`"
        case "$os,$ht" in
        Linux,ppc64le )         ARCH=LINUX_Power ;;
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
                                                                                            
function get_version_string
{
   if [ ! -e $QC/version.txt ] ; then return 9 ; fi
   local cver="0.0.0"
   local line; while read line ; do
     if [ "x$line" == "x" ] ; then continue ; fi
     local tline=${line//./}
     isdigit "$tline"
     if [ $? != 0 ] ; then continue ; fi
     cver=${line}
     break
   done < $QC/version.txt
   echo $cver
   return 0
}

function set_color_code
{
txtblk='\e[0;30m' # Black - Regular                                                                                    
txtred='\e[0;31m' # Red                                                                                                
txtgrn='\e[0;32m' # Green                                                                                              
txtylw='\e[0;33m' # Yellow                                                                                             
txtblu='\e[0;34m' # Blue                                                                                               
txtpur='\e[0;35m' # Purple                                                                                             
txtcyn='\e[0;36m' # Cyan                                                                                               
txtwht='\e[0;37m' # White                                                                                              
bldblk='\e[1;30m' # Black - Bold                                                                                       
bldred='\e[1;31m' # Red                                                                                                
bldgrn='\e[1;32m' # Green                                                                                              
bldylw='\e[1;33m' # Yellow                                                                                             
bldblu='\e[1;34m' # Blue                                                                                               
bldpur='\e[1;35m' # Purple                                                                                             
bldcyn='\e[1;36m' # Cyan                                                                                               
bldwht='\e[1;37m' # White                                                                                              
unkblk='\e[4;30m' # Black - Underline                                                                                  
undred='\e[4;31m' # Red                                                                                                
undgrn='\e[4;32m' # Green                                                                                              
undylw='\e[4;33m' # Yellow                                                                                             
undblu='\e[4;34m' # Blue                                                                                               
undpur='\e[4;35m' # Purple                                                                                             
undcyn='\e[4;36m' # Cyan                                                                                               
undwht='\e[4;37m' # White                                                                                              
bakblk='\e[40m'   # Black - Background                                                                                 
bakred='\e[41m'   # Red                                                                                                
bakgrn='\e[42m'   # Green                                                                                              
bakylw='\e[43m'   # Yellow                                                                                             
bakblu='\e[44m'   # Blue                                                                                               
bakpur='\e[45m'   # Purple                                                                                             
bakcyn='\e[46m'   # Cyan                                                                                               
bakwht='\e[47m'   # White                                                                                              
txtrst='\e[0m'    # Text Reset                                                                                         
}

function spinner(){                                                                                                    
    ## Adjust to taste (or leave empty)                                                                                
    SP_WIDTH=1.1  ## Try: SP_WIDTH=5.5                                                                                 
    SP_DELAY=.2                                                                                                        
    SP_CHAR='/-\|'                                                                                                     
    SP_STRING=${SP_CHAR:-"'|/=\'"}                                                                                     
    local white="\e[1;37m" ; local green="\e[1;32m";  local red="\e[1;31m"; local blue="\e[1;34m"; local nc="\e[0m"    
    sp='/-\|'                                                                                                          
    local t0=$(date +%s)                                                                                               
    while [ true ]; do                                                                                                 
        kill -s 0 $1 >/dev/null 2>&1                                                                                   
        if [ $? != 0 ]; then break; fi                                                                                 
        local t1=$(date +%s)                                                                                           
        if [ "x$2" == "x" ] ; then                                                                                     
           printf "${blue}\r ${sp:i++%${#sp}:1} ${nc}";                                                                
        else                                                                                                           
           printf "${blue}\r $2 $((t1-t0))s  ${sp:i++%${#sp}:1} ${nc}";                                                
        fi                                                                                                             
        sleep ${SP_DELAY:-.3}                                                                                          
        #printf "$SP_COLOUR\e7  %${SP_WIDTH}s  \e8\e[0m" "$SP_STRING"                                                  
        #SP_STRING=${SP_STRING#"${SP_STRING%?}"}${SP_STRING%?}                                                         
    done                                                                                                               
}                                                                                                                      
                                                                                                                       
function start_spinner                                                                                                 
{                                                                                                                      
   spinner $$ "$1"  &                                                                                                  
   _spid=$!                                                                                                            
}                                                                                                                      

function stop_spinner                                                                                                  
{                                                                                                                      
   echo                                                                                                                
   kill -9 ${_spid} >/dev/null 2>&1                                                                                    
   wait ${_spid} >/dev/null 2>&1                                                                                       
} 

#--------------------------------------  
#                                      
#     Prepare .update directory        
#     set wget if needed                                                                    
#     download update script and update list 
#                              
#     ... validate update script and update list ... 
#
#-------------------------------------- 
        

# 
# read config file or if new installation, ask QCSCRATCH QCLOCSCR 
#
 
function split_string  ## str delimiter strlist
{
   local _str="$1"
   local delimiter="$2"
   local _strlist=()
   local OLDIFS=$IFS ; IFS="$delimiter"
   local _array=(${_str}) 
   IFS=$OLDIFS
   local i;  for (( i=0 ; i<${#_array[@]} ; i++ )) ; do
        local item=$(trim_var "${_array[$i]}")
        _strlist+=("$item")
   done
   local ret_var=$3;  eval $ret_var="()"
   local i; for (( i=0 ; i<${#_strlist[@]} ; i++ )) ; do
        eval $ret_var+="(\"${_strlist[i]}\")" 
   done
}


function read_list_file  #listfile star_mark end_mark delimiter list
{
   local listfile="$1"
   local sta_mark="$2"
   local end_mark="$3"
   local delimiter="$4"
   local lists=()
   local istat; let istat=9
   local line
   while read line ; do 
      local arr 
      split_string "$line" "$delimiter" arr
      local arr0="${arr[0]}"
      if [ "x${arr0}" == "x" ] ; then continue; fi
      if [ "x" == "x${sta_mark}" ] ; then istat=0; fi
      if [ "x${arr0}" == "x${sta_mark}" ] ; then istat=0; continue; fi
      if [ "x${arr0}" == "x${end_mark}" ] ; then  break ; fi
      if [ $istat == 0 ]; then
         lists+=("$line")
      fi
   done < "$listfile"
  
   local ret_var; ret_var=$5;  eval $ret_var="()"
   local i; for (( i=0 ; i<${#lists[@]} ; i++ )) ; do
            eval $ret_var+="(\"${lists[i]}\")" ; done
}

function find_match_list  #lists dilimeter sstr matchlists  [iloc]
{
   local lc1=("${!1}")
   local delimiter="$2"
   local sstr="$3"
   local iloc="$5"
   if [ "x${iloc}" == "x" ] ; then  iloc=0; fi
   local matchlist=()
   #
   local iret=9
   if [ "x${sstr}" == "x" ]; then return 9; fi
   local i; for (( i=0 ; i<${#lc1[@]} ; i++ )) ; do
       local str="${lc1[$i]}"
       split_string "$str" "$delimiter" sslist
       case "x${sslist[0]}" in   x#* )  continue ;; esac
       if [ "x${sstr}" == "x${sslist[${iloc}]}" ] ; then 
          matchlist+=("$str")
          iret=0
       fi
   done
   #
   local ret_var; ret_var=$4;  eval $ret_var="()"
   local i; for (( i=0 ; i<${#matchlist[@]} ; i++ )) ; do
            eval $ret_var+="(\"${matchlist[i]}\")" ; done
   return ${iret}
}

function find_match_record #lists dilimeter sstr ipos $4 $5 $6 ...
{
   local lc1=("${!1}")
   local delimiter="$2"
   local matchlistx=()
   find_match_list lc1[@] "$delimiter" "$3"  matchlistx "$4"
   local iret=$?
   local sstr=""; local sstrx; for sstrx in  "${matchlistx[@]}"  ; do sstr="$sstrx" ; done
   local strlist=()
   split_string "$sstr" "$delimiter" strlist
   #
   shift ; shift; shift; shift
   local nargs=$#
   local i; for ((i=0;i<$nargs;i++)) ; do
      local ret_var;  ret_var=$1;   eval $ret_var=\"${strlist[$i]}\"
      shift
   done
   return ${iret}
}

function setup_qc_runtime_env
{
   #with_qcscratch  with_qclocalscr
   clear
   echo
   echo " $(tput bold)******************************************************************"
   echo " *                                                                *"
   echo " *                  Q-Chem Runtime Environment                    *"
   echo " *                                                                *"
   echo " ******************************************************************$(tput sgr0)"
   echo
   
   echo " \$QCSCRATCH: " 
   echo " A scratch directory, specified by the \$QCSCRATCH variable, is "
   echo " required for storing temporary files and for restarting jobs."
   echo " In a cluster environment the scratch directory must be a "
   echo " shared directory available to all of the nodes." 
   echo
   local qcscr=""
   while [ true ] ; do
       echo " Please specify the full path for a scratch directory"
       printf "\n > " ; read qcscr leftover
       if [ "x$qcscr" == "x" ] ; then continue ; fi
       if [ ! -d $qcscr ] ; then
          local yon=""
          while [ true ] ; do 
              echo
              echo   " The directory $qcscr does not exist"
              printf " Would you like to specify another? (<y>/n) > "
              read yon leftover
              if [ "x$yon" == "x" ] ; then break; fi
              if [ "x$yon" == "xy" ] || [ "x$yon" == "xY" ] ; then break; fi
              if [ "x$yon" == "xn" ] || [ "x$yon" == "xN" ] ; then break; fi
          done
          if [ "x$yon" == "xn" ] || [ "x$yon" == "xN" ] ; then break; fi
          continue
       fi
       break
   done
   with_qcscratch="$qcscr"
   #
   if [ "x${with_qcmpi}" == "xSEQ" ] ; then
      with_qcrsh="ssh"
      return
   fi
   echo
   echo " For performance reasons, some parallel platforms provide "
   echo " scratch space local to each node"
   qclocscr=""
   while [ true ] ; do
       printf " Do you want to use a local scratch directory? (y/n) > "
       read yon leftover
       if [ "x$yon" == "xn" ] || [ "x$yon" == "xN" ] ; then break; fi
       if [ "x$yon" != "xy" ] && [ "x$yon" != "xY" ] ; then continue; fi
       #
       echo " Please specify the full path of your local scratch directory"      
       printf " > " ; read qclocscr leftover
       if [ "x$qclocscr" == "x" ] ; then continue ; fi
       if [ "x$qclocscr" == "x${with_qcscratch}" ] ; then
            echo "  local scratch directory can not be the same as the scratch directory"
            continue 
       fi
       if [ ! -d $qclocscr ] ; then
          local yon=""
          while [ ture ] ; do 
              echo   " The directory $qclocscr does not exist"
              printf " Would you like to specify another? (<y>/n) > "
              read yon leftover
              if [ "x$yon" == "x" ] ; then break; fi
              if [ "x$yon" == "xy" ] || [ "x$yon" == "xY" ] ; then break; fi
              if [ "x$yon" == "xn" ] || [ "x$yon" == "xN" ] ; then break; fi
          done
          if [ "x$yon" == "xn" ] || [ "x$yon" == "xN" ] ; then break; fi
          continue
       fi
       break
   done
   with_qclocalscr="$qclocscr"
   #
   echo
   echo " To run Q-Chem in parallel passwordless rsh/ssh between "
   echo " computing nodes is required." 
   echo
   local qcrsh0="ssh"
   while [ true ] ; do
       echo   " Please select or enter the remote shell command to use"
       printf " (rsh/<ssh>) > "
       read qcrsh leftover
       if [ "x$qcrsh" == "x" ] ; then qcrsh=$qcrsh0 ; fi
       
       which ${qcrsh} >/dev/null 2>&1
       if [ $? != 0 ] ; then 
           echo "  can not find command $qcrsh you entered "
           continue
       fi
       break
       #
       $rsh localhost echo "" >/dev/null 2>&1
       if [ $? != 0 ]; then 
          local yon=""
          while [ ture ] ; do 
              echo " Failed passwordless login test using $qcrsh on localhost"
              printf " Would you like to specify another remote shell command? (<y>/n) > "
              read yon leftover
              if [ "x$yon" == "x" ] ; then break; fi
              if [ "x$yon" == "xy" ] || [ "x$yon" == "xY" ] ; then break; fi
              if [ "x$yon" == "xn" ] || [ "x$yon" == "xN" ] ; then break; fi
          done
          if [ "x$yon" == "xn" ] || [ "x$yon" == "xN" ] ; then break; fi
          continue
       fi
       break
   done
   with_qcrsh="$qcrsh"
}

function setup_qc_preference
{
   echo
   echo " Default Upper Memory Limit:"
   echo " The MEM_TOTAL keyword in Q-Chem input files specifies the "
   echo " maximum amount of memory used by each Q-Chem process. "
   echo " Here you can set a default value for MEM_TOTAL, which"
   echo " will be saved in \$QC/config/preference file. You can edit"
   echo " this file later or specify MEM_TOTAL in input files."
   echo

   with_qcmem=8000
   while [ true ] ; do
       printf " Please specify a default value for MEM_TOTAL in megabytes [8000] \n\n > "
       read qcmem leftover
       if [ "x$qcmem" == "x" ] ; then break; fi
       isdigit "$qcmem"
       if [ $? != 0 ] ; then
           echo "  input format error ... not an integer " 
           continue
       fi
       if [[ $qcmem -gt 1000000 ]] ;  then
           echo "  selection not valid ... out of range  "
           continue
       fi
       with_qcmem=$qcmem
       break
   done
}

# ===========================================
#
#  required environment setting : QC , INSTALLTYPE
#
# ===========================================

function install_qchem
{
   # set default updatedir if not already set
   if [ "x${with_updatedir}" == "x" ] ; then
      with_updatedir=${QC}/.update
   fi

   #
   # 1. detect QCPLATFORM
   #                                                                                            
   QCPLATFORM=$(get_qcplatform)                                                                
   if [ $? != 0 ]; then                                                                        
      echo " Failed to detect QCPLATFORM -- ${QCPLATFORM}"                                  
      exit 9
   fi                                                                                          
   #echo "QCPLATFORM is ${QCPLATFORM}" 

   #
   # 2. read latest configure status list -- liveupdate.list  
   #
   local new_cfgs=()
   local new_exes=()
   local updatef1=${with_updatedir}/update.list
   if [ -f $updatef1 ] ; then
      read_list_file $updatef1 "#sta_config" "#end_config"  ";"  new_cfgs
      read_list_file $updatef1 "#sta_exes"   "#end_exes"    ";"  new_exes_list
      find_match_list new_exes_list[@] ";" "${QCPLATFORM}"       new_exes  0
   fi

   #
   # 3. read current configure status list
   #
   local curr_cfgs=() 
   local his_cfgx=() 
   local updatef0=${with_updatedir}/current.list
   if [  -f $updatef0 ] ; then
      read_list_file $updatef0 "#sta_config" "#end_config" ";"  curr_cfgs
      read_list_file $updatef0 "#sta_hislog" "#end_hislog" ";"  his_cfgx
   fi

   #
   # 4. check version
   #
   find_match_record curr_cfgs[@] ";" "VERSION"  0  t_id  c_ver
   if [ "x${c_ver}" == "x" ] ; then
      c_ver=$(get_version_string)
   fi
   find_match_record new_cfgs[@] ";" "VERSION"  0  t_id  n_ver
   let c_verlic=`echo $c_ver  | awk -F"." '{for(i=1;i<=2;i++){if (i<=NF) printf $i; else printf "0"} }'` 
   let n_verlic=`echo $n_ver  | awk -F"." '{for(i=1;i<=2;i++){if (i<=NF) printf $i; else printf "0"} }'` 
   if_lic_upgrade=0
   if [ ${c_verlic} -lt ${n_verlic} ] ; then
       if_lic_upgrade=1
   fi   
   #echo " c_verlic n_verlic if_lic_upgrade : $c_verlic - $n_verlic - $if_lic_upgrade "
   if [ "x${with_update}" == "x1" ]; then
     if [ ${c_verlic} -ge 40 ] && [ ${c_verlic} -lt ${n_verlic} ] ; then
         #echo " c_verlic n_verlic if_lic_upgrade : $c_verlic - $n_verlic - $if_lic_upgrade "
         echo 
         echo "  The existing Q-Chem version is $c_ver. " 
         #echo "  If you upgrade to version $n_ver you would need to get a new license for $n_ver," 
         #echo "  or your Q-Chem would not run. " 
         echo "  Upgrade to the existing directory is disabled " 
         echo "  Please run qcinstall.sh and install Q-Chem to a new directory"
         exit 0
         echo
         yon=""
         while [ true ]; do
            yon=""
            echo "  Do you want to proceed with the upgrade process? (y/n)" 
            read yon leftover
            if [ "x$yon" == "xy" ] || [ "x$yon" == "xn" ] || [ "x$yon" == "xx" ]; then break; fi
         done 
         if [ "$yon" == 'n' ] || [ "x$yon" == "xx" ] ; then exit 0; fi
     fi
   fi
    
   #
   # 5. check config_id
   #
   if_sele_exe=9
   find_match_record curr_cfgs[@] ";" "CONFIG_ID" 0   t_id  c_config_id 
   if [ $? == 0 ] && [ "x${c_config_id}" != "x" ] ; then
      find_match_record new_exes[@] ";" "${c_config_id}"  2  t_platform with_qcmpi with_config_id with_config_id_s with_driver_id with_config_string 
      if [ $? == 0 ] ; then
         if_sele_exe=0
      else
         echo 
         echo "  current installed Q-Chem configure is detected as ${c_config_id} " 
         echo "  however, no matching configure found in update list  " 
         echo "  you will need to choose installation binary manually " 
         echo "  please contact support@q-chem.com for questions " 
         echo 
      fi
   fi
   #echo " $with_qcmpi --  $with_config_id -- $with_config_id_s -- $with_driver_id "
      
   # 5b.  select configure ID
   # 
   if [ ${if_sele_exe} != 0 ] ; then
      echo 
      echo " You are installing Q-Chem ${n_ver}"
      echo " Available packages for $QCPLATFORM:"
      local record; local ritems ; local t_comment 
      local nexes=${#new_exes[@]}
      local i; for (( i=0 ; i<${nexes} ; i++ )) ; do
          record="${new_exes[$i]}"
          split_string "$record" ";" ritems
          t_comment="${ritems[5]}"
          echo "  $(( $i + 1 )) -- ${t_comment}" 
      done
      local isel ; local leftover
      while [ true ] ; do 
          echo
          printf " Please choose package to install or press 'x' to exit [1-${nexes}]\n\n > "
          read isel leftover
          if [ "x$isel" == "xx" ]; then  exit 9 ;   fi
          if [ x"$isel" = x ]; then continue ; fi
          isdigit "$isel"
          if [ $? != 0 ] ; then 
              echo "  input format error ... not an integer " 
              continue
          fi
          if [[ $isel -gt $nexes ]] ;  then
              echo "  selection not valid ... out of range  "
              continue
          fi
          isel=$(($isel - 1))
          break
      done
      #
      #
      record="${new_exes[$isel]}"
      split_string "$record" ";" ritems
      with_qcmpi="${ritems[1]}"
      with_config_id="${ritems[2]}"
      with_config_id_s="${ritems[3]}"
      with_driver_id="${ritems[4]}"
      #echo " $with_qcmpi --  $with_config_id -- $with_config_id_s -- $with_driver_id "
   fi 
   
   #
   # 6. components update/installation 
   #  
#   echo
#   echo "QC_CONFIG_ID is ${with_config_id}"
   echo
   if [ "x${with_installdir}" != "x" ] ; then
      echo " The installer is now extracting required components"
   else
      echo " The installer will now download required components"
   fi
   local nupdate=0
   local curr_cfgx=() 
   if [ "x${with_update_check}" == "x1" ] ; then
      echo 
      echo "QC_UPDATE_MODE is CHECK-ONLY --- NO actually update will be performed."
      echo
   fi
   local components="${with_config_id} ${with_config_id_s} ${with_driver_id} qcaux qcsample qcbin qcdoc"
   if [ "${with_config_id}" == "${with_config_id_s}" ]; then
      components="${with_config_id} ${with_driver_id} qcaux qcsample qcbin qcdoc"
   fi
   for icomp in ${components}  ; do 
      local doupdate=true

      # -- get component info

      find_match_record curr_cfgs[@] ";" "${icomp}" 0 tcfgx tverx
      if [ "x$tverx" == "x" ] ; then tverx=0 ;  fi
      isdigit $tverx
      if [ $? != 0 ] ; then 
          echo "  component ${icomp} has incorrect version number ${tver}" 
          tverx=0
      fi

      find_match_record new_cfgs[@] ";" "${icomp}" 0 tcfg tver turl tdir turl2 
      isdigit $tver
      if [ $? != 0 ] ; then echo 
          echo "  component ${icomp} has incorrect version number ${tver}"  
          echo "  please contact support@q-chem.com to resolve this problem"
          doupdate=false
      fi
      if [[ $tver -le $tverx ]] ;  then  
          doupdate=false 
      fi
      #echo "$tcfg -- $tver -- $turl -- $tdir -- turl2"

      if [ "x$doupdate" == "xfalse" ] ; then
          strprt=$(printf " %35s ; %10s "  ${icomp}  ${tverx} )
          curr_cfgx+=( "$strprt" )
          continue
      fi

      if [ "x${with_update_check}" == "x1" ] ; then
         echo "  component $icomp should be updated from version $tverx to $tver --- current run is check only"
         nupdate=$(( $nupdate +  1 ))
         continue
      fi
      local disp_msg="  updating $icomp from version $tverx to version $tver  "
      if [ "x${tverx}" == "x0" ] ; then
         disp_msg="  downloading and installing $icomp version $tver  "
      fi

      fname=$(basename "$turl")
      instdir=${QC}/$tdir
      wget_url $turl "${disp_msg}"
      if [ $? != 0 ]; then
          echo
          echo " Failed to obtain $icomp version $tver from the website." 
          echo " Please check your internet connection and try again at a later time,"
          echo " or contact support@q-chem.com if this problem persists."
          echo
          err_exit " Online update failed for component $icomp " 
          strprt=$(printf " %35s ; %10s "  ${icomp}  ${tverx} )
          curr_cfgx+=( "$strprt" )
          continue
      fi

      # -- component install

      if [  "x$icomp" == "xqcsample" ] ; then
             if [  ${tverx} -lt 1 ] ; then  ##older version before 4.0.1 or new installation
             if [ -d "$QC/samples" ] && [ ! -d "$QC/samples/freq" ] && [ ! -e "$QC/samples_old" ] ; then 
                mv $QC/samples $QC/samples_old
                echo "   samples directory is reorganized since Q-Chem 4.0.1"
                echo "   existing samples dir has been renamed as samples_old "
             fi
             fi
      fi
      if [  "x$icomp" == "xqcaux" ] ; then
             if [  ${tverx} -lt 1 ] ; then  ##older version before 4.0.1 or new installation
             if [ -d $QC/aux ] && [ ! -d $QC/qcaux ] ; then 
                echo "   existing aux directory in \$QC is renamed as qcaux "
             fi
             fi
      fi

      mkdir -p "${instdir}"
      if [ "x$icomp" == "x${with_config_id}" ] || [ "x$icomp" == "x${with_config_id_s}" ] ; then
          gunzip ${fname} 
          if [ $? != 0 ]; then
            echo
            echo "  failed to unzip the downloaded binary $fname " 
            echo "  please try to run update again and "
            echo "  contact support@q-chem.com if this problem persists"
            strprt=$(printf " %35s ; %10s "  ${icomp}  ${tverx} )
            curr_cfgx+=( "$strprt" )
            continue
          fi
          mv ${fname%.gz} $instdir/qcprog.exe.$icomp.${tver}
          if [ "x$icomp" == "x${with_config_id}" ] ; then 
             ( cd $instdir; ln -sf qcprog.exe.$icomp.${tver} qcprog.exe )
          fi
          if [ "x$icomp" == "x${with_config_id_s}" ] ; then 
             ( cd $instdir; ln -sf qcprog.exe.$icomp.${tver} qcprog.exe_s )
          fi
          chmod -R 755 $instdir
      else
          (gunzip ${fname} ; mv ${fname%.gz} $instdir; cd $instdir; tar xvf ${fname%.gz}) > /dev/null 2>&1
          #gunzip ${fname}
          #tar xvf ${fname%.gz} -C "$instdir" >/dev/null 2>&1
          cd "$instdir" && rm -f "${fname%.gz}"
          if [ "x$icomp" == "xqcbin" ] ; then
              chmod -R 755  $instdir
              cd $instdir
              ln -sf get_hostid.${QCPLATFORM}  get_hostid
          else
              chmod -R og-w $instdir
          fi
      fi

      # -- book keeping
      strprt=$(printf " %35s ; %10s "  ${icomp}  ${tver} )
      curr_cfgx+=( "$strprt" )
      if [ $nupdate -eq 0 ] ; then 
         his_cfgx+=("$(date) ") 
      fi
      his_cfgx+=("-   ${icomp} updated from version ${tverx} to ${tver} ")
      nupdate=$(( $nupdate +  1 ))

   done  
   if [ "x${with_update_check}" == "x1" ] ; then
      if [ $nupdate -le 0 ] ; then
       echo " Q-Chem is up to date. No new updates are available." 
      else
       echo "Your Q-Chem installation has $[nupdate] components to be updated. " 
       echo "Please run \$QC/qcupdate.sh to update"
      fi
      echo "Completed Q-Chem update check ..." 
      return 0;
   fi

   #update environment setting file
   cat ${with_updatedir}/qcenv_sh | sed -e "s|QC=\$QC|QC=$QC|" > $QC/qcenv.sh
   cat ${with_updatedir}/qcenv_csh | sed -e "s|setenv QC \$QC|setenv QC $QC|" > $QC/qcenv.csh
   if [ "x${with_qcmpi}" != "xSEQ" ] && [ "x${with_qcmpi}" != "xseq" ] && [ "x${with_qcmpi}" != "x" ] ; then  
      touch $QC/bin/.parallel 
   fi
   

   # 6b. update current configuration file 
   #
   with_old_version=${c_ver}
   with_version=${n_ver}
   local tlog=${with_updatedir}/current.list2
   echo                     >  ${tlog}
   date                     >> ${tlog}
   echo                     >> ${tlog}
   echo "#sta_config"       >> ${tlog}
   printf " %35s ; %10s \n"  "VERSION"    ${with_version}   >> ${tlog}
   printf " %35s ; %10s \n"  "CONFIG_ID"  ${with_config_id} >> ${tlog}
   local i; for (( i=0 ; i<${#curr_cfgx[@]} ; i++ )) ; do  echo "${curr_cfgx[$i]}" >>  ${tlog}; done
   echo "#end_config"       >> ${tlog}
   echo                     >> ${tlog}
   echo "#sta_hislog"       >> ${tlog}
   local i; for (( i=0 ; i<${#his_cfgx[@]} ; i++ )) ; do  echo "${his_cfgx[$i]}" >>  ${tlog}; done
   #array_print his_cfgx[@] >> ${tlog}
   echo "#end_hislog"       >> ${tlog}
   echo                     >> ${tlog}
   mv -f $tlog ${with_updatedir}/current.list

   echo 
   if [ $nupdate -le 0 ] ; then
       echo "${with_version}"   > $QC/version.txt
       echo " Q-Chem is up to date. No new updates are available." 
   else
       echo "${with_version}"   > $QC/version.txt
       if [ "x${with_update}" == "x0" ] ; then
          echo " Installation of Q-Chem components has successfully completed." 
       else
          echo " Q-Chem components have been successfully updated." 
       fi
   fi
   echo

start_spinner 
   read -t 4  any
stop_spinner 
   #sleep 3

   #
   # 7. setup runtime environment 
   #        shellvar.txt -- qcscratch qclocscr mem_tot exe_name
   #        preferences  -- MEM_TOTAL
   #
   mkdir -p $QC/config
   local cnflist=()
   local cfgfile=$QC/config/shellvar.txt
   if_setup_env=9
   if [  -e $cfgfile ] ; then
      if_setup_env=0
      read_list_file $cfgfile "" "" "$IFS" cnflist
      find_match_record cnflist[@] "$IFS" "QCSCRATCH"  0  t_id  with_qcscratch
      if [ $? != 0 ] ; then if_setup_env=9; fi
      find_match_record cnflist[@] "$IFS" "QCLOCALSCR" 0  t_id  with_qclocalscr
      find_match_record cnflist[@] "$IFS" "QCRSH"      0  t_id  with_qcrsh
      if [ $? != 0 ] ; then if_setup_env=9; fi
      find_match_record cnflist[@] "$IFS" "QCMPI"      0  t_id  with_qcmpi2
   fi

   if [ ${if_setup_env} != 0 ] ; then
       setup_qc_runtime_env
   fi

   local tshv="$cfgfile"
   if [ -e $QC/aux/atoms ] ; then with_qcaux=$QC/aux ; fi 
   if [ -e $QC/qcaux/atoms ] ; then with_qcaux=$QC/qcaux ; fi 
   echo "QC          ${QC}"               > ${tshv}
   echo "QCPLATFORM  ${QCPLATFORM}"      >> ${tshv}
   echo "QCAUX       ${with_qcaux}"      >> ${tshv}
   echo "QCSCRATCH   ${with_qcscratch}"  >> ${tshv}
   echo "QCLOCALSCR  ${with_qclocalscr}" >> ${tshv}
   echo "QCRSH       ${with_qcrsh}"      >> ${tshv}
   echo "QCMPI       $(tolower "${with_qcmpi}")"    >> ${tshv}

   local tpref=$QC/config/preferences
   if [ ! -e $tpref ] ; then
       setup_qc_preference
       echo "\$rem"                      > ${tpref}
       echo " MEM_TOTAL  $with_qcmem "  >> ${tpref}
       echo "\$end"                     >> ${tpref}
   fi

clear
echo
echo " $(tput bold)******************************************************************"
echo " *                                                                *"
echo " *                    Q-Chem Runtime Environment                  *"
echo " *                                                                *"
echo " ******************************************************************$(tput sgr0)"
echo
   cat << END_OF_RUNTIMENV_SUMMARY
                                                    
  The Q-Chem system configuration preference file is: 
  $QC/config/preferences
 
  The environment variables file is: 
  $QC/config/shellvar.txt
 
 ******************************************************************

END_OF_RUNTIMENV_SUMMARY
start_spinner 
   read -t 4  any
stop_spinner 
    
   #
   # 8. license update  
   #    preference mpi/bin/machines, rhosts, enter
   #
   if [ ${if_lic_upgrade} != 0 ] || [ "x${with_update}" == "x2" ] ; then
      register_qchem
      qchem_license
start_spinner 
   read -t 4  any
stop_spinner 
   fi

clear
echo
echo " $(tput bold)******************************************************************"
echo " *                                                                *"
echo " *                    Q-Chem Installation Summary                 *"
echo " *                                                                *"
echo " ******************************************************************$(tput sgr0)"
echo
printf  " \n\
                                                                  \n\
  Q-Chem installation/update has been completed.                  \n\
                                                                  \n\
  To run Q-Chem calculations simply source the setup script below.\n\
                                                                  \n\
  For tcsh or csh:                                                \n\
  ${bldblu}source $QC/qcenv.csh${txtrst}                          \n\
                                                                  \n\
  For bash:                                                       \n\
  ${bldblu}. $QC/qcenv.sh${txtrst}                                \n\
                                                                  \n\
  You can put the above lines in your shell startup script        \n\
  ~/.cshrc for tcsh/csh or ~/.bashrc for bash.                    \n\
                                                                  \n\
  To get the latest Q-Chem updates please run                     \n\
                                                                  \n\
  ${bldblu}$QC/qcupdate.sh${txtrst}                               \n\
                                                                  \n\
  To regenerate license data please run                           \n\
                                                                  \n\
  ${bldblu}$QC/qcinstall.sh --update-lic${txtrst}                 \n\
                                                                  \n\
  ****************************************************************\n\
    \n"

    #
    # update the main script
    #
    cp -f ${with_updatedir}/qcinstall.sh $QC >/dev/null
    echo " $QC/qcinstall.sh --update \$1 " > $QC/qcupdate.sh
    chmod 755 $QC/qcupdate.sh
}


function write_qcenv_module
{
  local qcmpi=$(tolower "${with_qcmpi}")
  local qcprog="$QC/exe/qcprog.exe"
  local qcprog_s="$QC/exe/qcprog.exe_s"
  if [ ! -e "${qcprog_s}" ] ; then qcprog_s=${qcprog}; fi

   cat << END_OF_QCENV_MODULE > ${QC}/qcenv.tcl
#%Module1.0###############################################
##
##  Q-Chem modulefile
##
proc ModulesHelp { } {
        puts stderr "\tQ-Chem module file."
}

## Create a whatis file.  Not nessecary but cool.
module-whatis   "Q-Chem ${with_version} release environment module"

## Set a few personal aliases
set-alias       "qc"    "cd \\\$QC"

## Set an environment variable
setenv          QC  "$QC"
setenv          QCAUX  "$QC/qcaux"
setenv          QCPLATFORM  "${QCPLATFORM}"
setenv          QCMPI  "${qcmpi}"
setenv          QCRSH  "${with_qcrsh}"
setenv          QCPROG  "${qcprog}"
setenv          QCPROG_S  "${qcprog_s}"

## Add my bin directory to the path
prepend-path     PATH    "$QC/bin"
prepend-path     PATH    "$QC/exe"

END_OF_QCENV_MODULE
}

. ./license.sh
#. ./register.sh

if [ "x$QC" == "x" ] ; then
   export QC=`pwd`
   export with_update=2
fi
if [ "x${with_updatedir}" == "x" ] ; then
      with_updatedir=${QC}/.update
fi
with_wget=${with_wget:-wget}
set_color_code
install_qchem  
write_qcenv_module 

#for gpu installer
if [ "x${with_config_id}" == "xLINUX_Ix86_64_GPU" ] ; then
 export WITH_GPU=1
 export regiinfo
 ${QC}/.update/brianqc_installer.bin
fi
exit 0

function ttt01
{
      register_qchem

#start_spinner 
   read -t 3  any
#stop_spinner 

      if [ "x${with_qcmpi}" == "xSEQ" ] || [ "x${with_qcmpi}" == "xseq" ] || [ "x${with_qcmpi}" == "x" ] ; then
        serial_license
      else
        parallel_license
      fi
      local stat=$?
      local i; for (( i=0 ; i<${#sidstrlist[@]} ; i++ )) ; do  echo "  ${sidstrlist[$i]}" ; done

      if [  $stat == 0 ] ; then
          submit_license "${with_email}"
      else
          failed_license
      fi
}
