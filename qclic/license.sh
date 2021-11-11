#!/bin/bash

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

isdigit ()    # Tests whether *entire string* is numerical.
{             # In other words, tests for integer variable.
  [ $# -eq 1 ] || returna 9;
  case $1 in
    *[!0-9]*|"") return 9;;
              *) return 0;;
  esac
}

function check_email
{
    regex="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\
$"
    local ix="$1"
    if [[ $ix =~ $regex ]] ; then
       return 0
    else
       return 9
    fi
}

function register_by_userinfo
{
    with_ordernum=0
    while [ true ]; do
      echo
      echo "  -----------------------------"
      echo                                                                                       
      echo "  Q-Chem User Registration:"
      echo "  [IMPORTANT: a valid Email entered below is REQUIRED to receive license]"
      echo                                                                                        
      echo "  Type your information and press <Enter> "
      echo
      printf "  Name:"                                                                      
      read with_username
      printf "  Department/Group:"
      read with_group
      printf "  GroupLeader:"
      read with_groupleader
      printf "  Institute/Company:"
      read with_company
      while [ true ]; do
        printf "  EMAIL:"
        read with_email
        check_email "${with_email}"
        if [ $? != 0 ] ; then
           printf "  Invalid email address format. \n"
           printf "  MUST provide a valid email for registration\n"
           continue
        fi
        break
      done
      echo
      echo "  -----------------------------"

      echo
      echo "  User Registraton Information:"
      echo "  -----------------------------"
      echo "  Order Number: ${with_ordernum}"
      echo "  User Name:    ${with_username}"
      echo "  Department:   ${with_group}"
      echo "  GroupLeader:  ${with_groupleader}"
      echo "  Institute:    ${with_company}"
      echo "  Email:        ${with_email}"
      echo

      local confirm
      while [ true ]; do
         printf "  Is the above information correct?<y/n>...<y>"
         read confirm
         if [ "x$confirm" == "xy" -o  "x$confirm" == "x" ] ; then break; fi
         if [ "x$confirm" == "xn" ] ; then break; fi
      done
      if [ "x$confirm" == "xy" -o  "x$confirm" == "x" ] ; then break; fi
    done
    echo "  Thank you for your registration!  "
    echo 
} 

function qchem_license_agreement
{
   clear
   echo
   echo " $(tput bold)******************************************************************"
   echo " *                                                                *"
   echo " *                     Q-Chem License Agreement                   *"
   echo " *                                                                *"
   echo " ******************************************************************$(tput sgr0)"
   echo
   
   cat << ENDOF_QC_LIC_AGREEMENT

 Please review Q-Chem's licensing agreement before registration. 

ENDOF_QC_LIC_AGREEMENT

      local confirm
      while [ true ]; do
         printf "  Would you like to view the licensing agreement? <y/n>...<y>"
         read confirm
         if [ "x$confirm" == "xy" -o  "x$confirm" == "x" ] ; then break; fi
         if [ "x$confirm" == "xn" ] ; then break; fi
      done
      if [ "x$confirm" == "xy" -o  "x$confirm" == "x" ] ; then 
         more -d $QC/doc/HighPerfLicense.txt
         local agreed
         while [ true ]; do
            printf "  Do you accept the terms of the licensing agreement? <y/n>...<y>"
            read agreed
            if [ "x$agreed" == "xy" -o  "x$agreed" == "x" ] ; then break; fi
            if [ "x$agreed" == "xn" ] ; then break; fi
         done
         if [ "x$agreed" == "xn" ] ; then 
            echo "  Licensing agreement declined ... quit license registration" 
            exit -1
         fi
      else
         echo ""
         echo "  Please read the agreement at your leisure."
         echo "  It is located in the" \$QC"/doc directory."
         echo ""
         sleep 3
      fi
}

function register_by_order_number
{
#  print_msg_get_ordernum
   clear
   echo
   echo " $(tput bold)******************************************************************"
   echo " *                                                                *"
   echo " *                    Q-Chem License Registration                 *"
   echo " *                                                                *"
   echo " ******************************************************************$(tput sgr0)"
   echo
   cat << ENDOF_GET_ORDER_NUM

 Registration is required to use Q-Chem. Please provide a valid
 e-mail address in order to receive a Q-Chem license file.

  - If you are a current Q-Chem user, please provide the order number 
    below. It can be found in the e-mail you received from Q-Chem.

  - If you are a new Q-Chem user without an order number, please enter 0
    below and provide the registration information subsequently.

ENDOF_GET_ORDER_NUM

#
#- get old order number
#
   local ordnum=0
   local ordfound
   while [ true ] ; do
      ordfound=false
      printf "  Please enter your order number: "
      read ordnum leftover
      if [ "x$ordnum" == "x" ] ; then continue; fi
      isdigit "$ordnum"
      if [ $? -ne 0 ] ; then
         echo "  The order number $ordernum you entered has format error"
         continue
      fi
      if [ "x$ordnum" == "x0" ] ; then break; fi
      if [ $ordnum -le 1000 -o $ordnum -gt 9999 ] ; then
         echo "  The order number $ordernum you entered is not valid"
         continue
      fi
      ordfound=true
      with_ordernum=$ordnum

      while [ true ] ; do 
         echo
         echo    "  [IMPORTANT: a valid Email is REQUIRED to receive license]"
         printf  "  Please enter your email address CORRECTLY: "
         read with_email
         check_email "${with_email}"
         if [ $? != 0 ] ; then
           printf "  Invalid email address format. \n"
           printf "  MUST provide a valid email for registration\n"
           continue
         fi
         break
      done
         
      echo
      echo "  User Registration Information:"
      echo "  -----------------------------"
      echo "  Order Number: ${with_ordernum}"
      echo "  Email:        ${with_email}"
      echo

      local confirm
      while [ true ]; do
         printf "  Is the above information correct?<y/n>...<y>"
         read confirm
         if [ "x$confirm" == "xy" -o  "x$confirm" == "x" ] ; then break; fi
         if [ "x$confirm" == "xn" ] ; then break; fi
      done
      if [ "x$confirm" == "xy" -o  "x$confirm" == "x" ] ; then break; fi
   done

   if [ $ordfound == "true" ] ; then 
      echo 
      echo "  Thank you for your registration!  "
      echo
      return 0
   else 
      return 9
   fi
}

function register_qchem
{
   
   qchem_license_agreement

   register_by_order_number
   if [ $? != 0 ] ; then
      register_by_userinfo
   fi
   regiinfo+=("Order Number: ${with_ordernum}   ")
   regiinfo+=("User Name:    ${with_username}   ")
   regiinfo+=("Department:   ${with_group}      ")
   regiinfo+=("Group Leader: ${with_groupleader}")
   regiinfo+=("Institute:    ${with_company}    ")
   regiinfo+=("Email:        ${with_email}      ")
}

#
#
#

function parallel_license
{
   clear
   echo " $(tput bold)******************************************************************"
   echo " *                                                                *"
   echo " *                    Q-Chem License Registration                 *"
   echo " *                                                                *"
   echo " ******************************************************************$(tput sgr0)"
   echo
   cat << END_OF_CLUSTER_LICENSE

The following procedure will run the license program, 
\$QC/bin/get_hostid, on all the cluster nodes to collect 
the require data for node-locked licensing, provided:

1. the Q-Chem directory is installed as a shared directory among all
   the nodes
2. passwordless rsh/ssh between all the nodes is enabled.

If the above criteria are not met, you will need to perform the 
licensing procedure manually.  Please see the file README.License for
details.

END_OF_CLUSTER_LICENSE
    #print_msg_cluster_license
    yon=""                                                                                                             
    while [ true ] ; do
        echo  "  Would you like to proceed with the automated procedure?"                                                 
        printf "  Enter \"y\" or press <enter> to continue or \"n\" to exit: "
        read yon leftover
        if [ "x$yon" == "x" ] ; then break; fi
        if [ "$yon" == "y" -o "$yon" == "n" -o "$yon" == "Y" -o "$yon" == "N" ] ; then break; fi
    done  
    if [ "x$yon" == "xn" -o "x$yon" == "xN" ] ; then return 9; fi

    #print_msg_select_rsh
    #RSHNAME="rsh"
    #if [ "$QCPLATFORM" == "HP_UX" ]; then RSHNAME="remsh"; fi
    #while [ true ] ; do
    #    echo ""
    #    printf "Which remote shell protocol would you like to use? (${RSHNAME}/ssh)"
    #    read rsh
    #    if [ "x$rsh" == "x$RSHNAME" -o "x$rsh" == "xssh" ]; then break; fi
    #done
    QCRSH=$with_qcrsh

    #print_msg_select_fileorenter

   cat << END_OF_CLUSTER_LICENSE2

You have two options for entering the list of nodes to be licensed.

1. Specifying a file containing the list of all the machine.  This is 
   just a straight text file that has the hostname of each machine.

2. Explicitly entering each machine. You will be prompted to enter 
   each name individually.

END_OF_CLUSTER_LICENSE2

 hostoklist=()
 sidoklist=()
 hostxxlist=()
 sidxxlist=()
 while [ true ] ;  do
    while [ true ]; do 
        printf "   Which method would you like to use: [F]ile or [E]xplicit? (F or E)"
        read fe leftover
        if [ "x$fe" == "xf" -o "x$fe" == "xF" ] ; then break ; fi
        if [ "x$fe" == "xe" -o "x$fe" == "xE" ] ; then break ; fi
    done

    if [ "x$fe" == "xf" -o "x$fe" == "xF" ] ; then 
        #print_msg_machine_file
        if [ -f $HOME/.rhosts ] ; then hostf_default=$HOME/.rhosts ; fi
        while [ true ]; do
           echo "Please give the full path to the machine list file. [${hostf_default}]" 
           echo "Enter 'q' to quit license procedure" 
           read hostf leftover 
           if [ "x$hostf" == "xq" ] ; then break; fi
           if [ "x$hostf" == "x" ] ; then hostf=${hostf_default}; fi
           if [ -e "$hostf" ] && [ -f "$hostf" ] ; then break; fi
       done
       #
       if [ -e "$hostf" ] && [ -f "$hostf" ] ; then 
           hostlist_tmp=()
           userlist_tmp=()
           while read line ; do 
              local arr=(${line});
              hostlist_tmp+=("${arr[0]}")
              userlist_tmp+=("${arr[1]}")
           done < "$hostf" 
       fi
       if [ "x$hostf" == "xq" ] ; then 
           return 9
       fi
    fi

    if [ "x$fe" == "xe" -o "x$fe" == "xE" ] ; then 
       #print_msg_machine_enter
       echo
       echo "Enter Machine Names:"
       hostlist_tmp=()
       while [ true ]; do
          echo "  Please enter the hostname of the machine you would like to license"
          echo "  [just press return to exit]:"
          printf "  " ; read hostnm leftover
          if [ "x$hostnm" == "x" ] ; then break; fi
          hostlist_tmp+=("$hostnm")
       done
    fi

    echo "Start collecting node license data:"
    local th_ok=(); local ts_ok=()
    local th_xx=(); local ts_xx=()
    for (( i=0 ; i<${#hostlist_tmp[@]} ; i++ )) ; do
       host="${hostlist_tmp[i]}"
       user="${userlist_tmp[i]}"
       if [ "x${user}" == "x" ] ;  then user="${USER}"; fi
       cmd="${QCRSH} $host -l $user printf '@@@' && $QC/bin/get_hostid"
       if [ "x${QCRSH}" == "xssh" ] ; then
           cmd="${QCRSH} -o ConnectTimeout=5 $host -l $user printf '@@@' && $QC/bin/get_hostid"
       fi
         
       echo "  licensing node $host ... please wait ..."
       ## for valid execution must $?==0 && outstr not empty
       outstr=$($cmd)
       local stat=$?
       outstr=${outstr##*@@@}
       if [ $stat == 0 ] && [ "x${outstr}" != "x" ] ;  then
           hostoklist+=("$host")
           sidoklist+=("$host $outstr")
           th_ok+=("$host")
           ts_ok+=("$host $outstr")
       else
           hostxxlist+=("$host")
           sidxxlist+=("$host $outstr")
           th_xx+=("$host")
           ts_xx+=("$host $outstr")
       fi
       #echo "        $host $outstr"
    done
    if [ ${#th_xx[@]} -ne 0 ] ; then
       echo "  Number of nodes requested for licensing:    ${#hostlist_tmp[@]}"
       echo "  Number of nodes with valid license data:    ${#th_ok[@]}"
       echo "  Number of nodes with invalid license data:  ${#th_xx[@]}"
       echo "  Failed to obtain valid license data on the following nodes"
       for (( i=0 ; i<${#ts_xx[@]} ; i++ )) ; do 
          echo "        ${ts_xx[i]}" 
       done
       local yn
       while [ true ]; do
          printf "   would you want to add more nodes to replace the failed ones?(y/n)"
          read yn leftover
          if [ "x$yn" == "xy" -o "x$yn" == "xY" ] ; then break ; fi
          if [ "x$yn" == "xn" -o "x$yn" == "xN" ] ; then break ; fi
       done
       if [ "x$yn" == "xy" -o "x$yn" == "xY" ] ; then continue ; fi
    fi
    break;
 done
 hostlist=()
 sidstrlist=()
 for (( i=0 ; i<${#hostoklist[@]} ; i++ )) ; do
       hostlist+=("${hostoklist[$i]}")
       sidstrlist+=("${sidoklist[$i]}")
 done
 for (( i=0 ; i<${#hostxxlist[@]} ; i++ )) ; do
       hostlist+=("${hostxxlist[$i]}")
       sidstrlist+=("${sidxxlist[$i]}")
 done
 echo
 echo "Finished licensing ${#hostlist[@]} total nodes, ${#hostoklist[@]} valid SIDs obtained."
 return 0
}

function flexnet_license
{
    echo
    echo " FlexNet licensing requires deploying a central license management server."
    echo " The Q-Chem distribution provides the necessary software and documentation:"
    echo "  - Server software (lmgrd or lmadmin) under \$QC/bin/flexnet"
    echo "  - License Administration Guide under \$QC/doc/flexnet"
    echo "  - Q-Chem specific instructions in \$QC/doc/README.FlexNet"
    echo
    echo " Please refer to these resources when setting up FlexNet."
    echo
    echo " The FlexNet license file for your order will be provided upon request"
    echo " to license@q-chem.com."
    echo
    printf " Please press Enter to continue > "
    read flexnet_ack
    return 0
}

function serial_license
{
    hostlist=()
    sidstrlist=()
    host=$(hostname 2>/dev/null)
    outstr=$($QC/bin/get_hostid 2>/dev/null)
    sidstrlist+=("$host $outstr")
    hostlist+=("$host")
    return 0
}

function timer_spinner(){
    local cnt=$2
    local white="\e[1;37m" ; local green="\e[1;32m";  
    local red="\e[1;31m"; local blue="\e[1;34m"; local nc="\e[0m"
    ## while [ true ]; do
    for (( i=${cnt} ; 0<=i; i-- )) ; do
        kill -s 0 $1 >/dev/null 2>&1
        if [ $? != 0 ]; then break; fi
        printf "\b\b${blue}%02d${nc}" $i;
        sleep 1
    done
}

function start_timer_spinner
{
   timer_spinner $$ "$1"  &
   _spid=$!
}

function stop_timer_spinner
{
   echo
   kill -9 ${_spid} >/dev/null 2>&1
   wait ${_spid} >/dev/null 2>&1
}

function license_display_submission  #$1= license.data file
{
  let nl=$(wc -l $QC/license.data | awk '{printf $1}')
  let nmax=36
  printf "                                              \n\
  Below is the license data to be submitted to Q-Chem.  \n\
  Only the first $nmax lines are displayed below.       \n"
  printf "  ---------------------------------------------------  \n"

  head -n $nmax "$1"
  if [ $nl -gt $nmax ] ; then
    printf "\n"
    printf "         ...... \n"
    printf "         ...... \n"
  fi
  echo
  printf "  ---------------------------------------------------  \n"
  echo
  printf "  Just wait or press <Enter> to submit license data,\n  or type 'n' to abort submission     " 
  start_timer_spinner 20
  read -t 20 any
  stop_timer_spinner
  echo $any
  if [ "x$any" == "xn" ] ; then return 9; fi
  return 0
}

function urlencode2 {
echo "$@" | sed 's/ /%20/g;s/!/%21/g;s/"/%22/g;s/#/%23/g;s/\$/%24/g;s/\&/%26/g;s/'\''/%27/g;s/(/%28/g;s/)/%29/g;s/:/%3A/g'
}

function failed_license
{
cat << ENDOF_FAILED_LIC

   ==========================================

   Failed to complete Q-Chem license data gathering

   You may need to manually run \$QC/bin/get_hostid
   on all the computing nodes and send the collected
   outputs to license@q-chem.com

   ==========================================

ENDOF_FAILED_LIC
}

function submit_license
{  
   with_wget="nothanks"
   #
   #license_display_submission $1
   #if [ $? != 0 ] ; then return $? ; fi   
   echo " The installer is now submitting license data to the Q-Chem server"
   echo 
   local emailaddr="$1"
   local filenm="$2"
   local x=$(urlencode2 "$(cat ${filenm})")
   local regmsg="${QC}/.update/regmsg.txt"
   rm -f ${regmsg}
   local stat=9
   if [ "x${with_wget}" == "xcurl" ] ; then
     ${with_wget} --connect-timeout 15 -sf -X POST -d "regiemail=${emailaddr}&filedata=$x" https://www.q-chem.com/ttt/upload3.php -o ${regmsg}
     stat=$?
     cat ${regmsg} | head -n 100
   elif [ "x${with_wget}" != "xnointernet" ] ; then
     ${with_wget:-wget} --connect-timeout=15 --post-data "regiemail=${emailaddr}&filedata=$x" -O ${regmsg} https://www.q-chem.com/ttt/upload3.php >/dev/null 2>&1
     stat=$?
     cat ${regmsg} | head -n 100
   else
     echo '  -------------------------------------  '
     echo '       WARNING !!!                       ' 
     echo "  No internet connection detected !      "
     echo "  Online license submission is skipped ! "
     echo " "
     echo "  Please email file $QC/license.data to  "
     echo "  license@q-chem.com to request license  " 
     echo '  -------------------------------------  '
     echo " "
     echo "  Press any key to continue " 
     read    yon leftover
   fi
   #
   # 
   #
   if [ $stat == 0 ] ; then
cat << ENDOF_SUBMIT_LIC

  --------------------------------------------------

     Summary of License Data Gathering

  The licenses data has been submitted to Q-Chem 
  office. You should receive a confirmation email
  and subsequently the license file at the email
  address $emailaddr

  If you do not receive the confirmation email 
  within an hour please email the file
  $QC/license.data
  to license@q-chem.com to request your license.

  --------------------------------------------------

ENDOF_SUBMIT_LIC
   else
cat << ENDOF_SUBMIT_LIC2

   Failed to submit license data online

   Q-Chem licenses data is written in 
   $QC/license.data

   Please e-mail this file to license@q-chem.com to receive your license.

ENDOF_SUBMIT_LIC2
   fi
   read -t 4 any
   return 0
}

function write_license_file
{
   #
   # generate license data file 
   local tlicf="$1"
   local tdate=$(date)
   echo                              >  ${tlicf}
   echo "  $tdate    "               >> ${tlicf}
   echo "  #sta_regi "               >> ${tlicf}
   local i; for (( i=0 ; i<${#regiinfo[@]} ; i++ )) ; do  echo "        ${regiinfo[$i]}" >> ${tlicf} ; done
   echo "  #end_regi "               >> ${tlicf}
   echo "  QCPLATFORM  $QCPLATFORM"  >> ${tlicf}
   echo "  QCMPI       ${with_qcmpi}">> ${tlicf}
   echo "  QCVERSION   ${with_version}">> ${tlicf}
   echo "  QCOLDVER    ${with_old_version}">> ${tlicf}
   echo "  QCLICOPT    ${lic_opt}"   >> ${tlicf}
   if [ "x$qcloud_flexid" != "x" ] ; then
      echo "  QCFLEXID    ${qcloud_flexid}"   >> ${tlicf}
   fi
   echo "  #sta_sid  "               >> ${tlicf}
   local i; for (( i=0 ; i<${#sidstrlist[@]} ; i++ )) ; do  echo "      ${sidstrlist[$i]}" >> ${tlicf} ; done
   echo "  #end_sid  "               >> ${tlicf}
}

function present_license_options
{    
    local lic_opt=""
    local rval=0
    clear
    echo " $(tput bold)******************************************************************"
    echo " *                                                                *"
    echo " *                    Q-Chem Licensing Options                    *"
    echo " *                                                                *"
    echo " ******************************************************************$(tput sgr0)"
    echo
    
    echo " Q-Chem has two options for licensing: "
    echo""
    echo " 1-- Node-locked licensing where licenses are issued "
    echo "     for specific machines. This is appropriate for "
    echo "     single computers and most small clusters. "
    echo ""
    echo " 2-- FlexNet based remote licensing. This option "
    echo "     requires a central licensing server and is "
    echo "     appropriate for larger clusters and multi- "
    echo "     user environments. "
    echo ""
    
    while [ true ]; do
        echo " Please specify the licensing scheme from above. (<1>/2) "
        printf "\n > "
        read lic_opt leftover
        if [ "x$lic_opt" == "x" ] ; then
            return 1
        fi
        if [ "x$lic_opt" == "x1" ] ; then
            return 1
        fi
        if [ "x$lic_opt" == "x2" ] ; then
            return 2
        fi
    done
}

function qchem_license
{
      # return with_email
      #register_qchem

start_timer_spinner 3
   read -t 3  any
stop_spinner 
      
      
      if [ "x$qcloud_dir" == "x" ] ; then
         present_license_options
         lic_opt=$?
      else
	 lic_opt="flexnet-aws"
      fi

      if [ "x$lic_opt" == "x2" ] ; then
        lic_opt="flexnet"
      fi
    
      if [ "x$lic_opt" == "x1" ] ; then
        lic_opt="nodelocked"
      fi
      
      local stat="" 
      if [ "x$lic_opt" == "xflexnet" ] ; then
        
        flexnet_license
        stat=$?
      else      
          if [ "x${with_qcmpi}" == "xSEQ" ] || [ "x${with_qcmpi}" == "xseq" ] || [ "x${with_qcmpi}" == "x" ] ; then
              serial_license
          else
              parallel_license
          fi
          stat=$?
      
      
          #
          # display license info && add default machine file
          #
          local i; for (( i=0 ; i<${#sidstrlist[@]} ; i++ )) ; do  echo "  ${sidstrlist[$i]}" ; done
          # generate machine file
          mfile=$QC/bin/mpi/machines; echo > ${mfile}
          local i; for (( i=0 ; i<${#hostoklist[@]} ; i++ )) ; do  echo "  ${hostoklist[$i]}" >> ${mfile} ; done
          mfile=$QC/bin/mpi/machines.all; echo > ${mfile}
          local i; for (( i=0 ; i<${#hostlist[@]} ; i++ )) ;   do  echo "  ${hostlist[$i]}"   >> ${mfile} ; done

      fi

      local licf="$QC/license.data"
      write_license_file "$licf"


      if [  $stat == 0 ] ; then
          submit_license "${with_email}" "$licf"
      else
          failed_license
      fi
      
      return $stat
}


#register_qchem
#submit_license /home/zgan/tinstall/license.data gzt036@yahoo.com



