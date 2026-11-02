#!/bin/bash

# ------------------------------------------------------------------------- #
# This script submits jobs to replay digitized data to batch farm.          #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# ------------------------------------------------------------------------- #

# Setting necessary environments via setenv.sh
source setenv.sh

# List of arguments
inputfile=$1  # Digitized ROOT filebase w/o extention
indirpath=$2  # Directory containing ditized ROOT files 
outdirpath=$indirpath # 
sbsconfig=$3  # SBS configuration
nevents=$4
fjobid=$5     # first job id
njobs=$6      # total no. of jobs to submit
run_on_ifarm=$7
# workflow name
workflowname=gep_sim_replay

# Checking the environments
if [[ ! -d $SCRIPT_DIR ]]; then
    echo -e '\nERROR!! Please set "SCRIPT_DIR" path properly in setenv.sh script!\n'; exit;
elif [[ (! -d $ANALYZER) && ($useJLABENV -eq 1) ]]; then
    echo -e '\nERROR!! Please set "ANALYZER" path properly in setenv.sh script!\n'; exit;
elif [[ ! -d $SBSOFFLINE ]]; then
    echo -e '\nERROR!! Please set "SBSOFFLINE" path properly in setenv.sh script!\n'; exit;
elif [[ ! -d $SBS_REPLAY ]]; then
    echo -e '\nERROR!! Please set "SBS_REPLAY" path properly in setenv.sh script!\n'; exit;
fi

# Validating the number of arguments provided
if [[ "$#" -ne 7 ]]; then
    echo -e "\n--!--\n Illegal number of arguments!!"
    echo -e " This script expects 7 arguments: <g4sbsfilebase> <g4sbsfiledir> <sbsconfig> <nevents> <fjobid> <njobs> <run_on_ifarm>\n"
    exit;
else 
    if [[ $run_on_ifarm -ne 1 ]]; then
	echo -e '\n------'
	echo -e ' Check the following variable(s):'
	echo -e ' "workflowname" : '$workflowname''
	while true; do
	    read -p "Do they look good? [y/n] " yn
	    echo -e ""
	    case $yn in
		[Yy]*) 
		    break; ;;
		[Nn]*) 
		    read -p "Enter desired workflowname : " temp1
		    workflowname=$temp1
		    break; ;;
	    esac
	done
    fi
fi

# Creating the workflow
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 create $workflowname
else
    echo -e "\nRunning all jobs on ifarm!\n"
fi

# looping over jobs
for ((i=$fjobid; i<$((fjobid+njobs)); i++))
do
    digireplayinfile=$inputfile'_job_'$i
    digireplayjobname=$inputfile'_digi_replay_job_'$i

    digireplayscript=$SCRIPT_DIR'/run-digi-replay.sh'' '$digireplayinfile' '$sbsconfig' '$nevents' '$outdirpath' '$run_on_ifarm' '$ANALYZER' '$SBSOFFLINE' '$SBS_REPLAY' '$ANAVER' '$useJLABENV' '$JLABENV
    
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -partition production -name $digireplayjobname -cores 1 -disk 100GB -ram 5GB -time 24h $digireplayscript
    else
	$digireplayscript
    fi
done

# run the workflow and then print status
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 run $workflowname
    echo -e "\n Getting workflow status.. [may take a few minutes!] \n"
    swif2 status $workflowname
fi
