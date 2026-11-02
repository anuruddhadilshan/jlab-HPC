#!/bin/bash

# ------------------------------------------------------------------------- #
# This script runs g4sbs jobs on ifarm or submits them to batch farm.       #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ------------------------------------------------------------------------- #

# Setting necessary environments via setenv.sh
source setenv.sh
if [[ ! -d $SCRIPT_DIR ]]; then
    echo -e '\nERROR!! Please set "SCRIPT_DIR" path properly in setenv.sh script!\n'; exit;
elif [[ ! -d $G4SBS ]]; then
    echo -e '\nERROR!! Please set "G4SBS" path properly in setenv.sh script!\n'; exit;
fi

preinit=$1      # G4SBS preinit macro w/o file extention (Must be located at $G4SBS/scripts or $G4SBS/scripts/gmn)
nevents=$2      # No. of events to generate per job
fjobid=$3       # first job id
njobs=$4        # total no. of jobs to submit 
run_on_ifarm=$5 # 1=>Yes (If true, runs all jobs on ifarm)
workflowname=gep_G4SBS
outdirpath=/lustre24/expphy/volatile/halla/sbs/adr/gep-sim/GEP3_mod/elastics_g4sbsout

# Validating the number of arguments provided
if [[ "$#" -ne 5 ]]; then
    echo -e "\n--!--\n Illegal number of arguments!!"
    echo -e " This script expects 5 arguments: <preinit> <nevents> <fjobid> <njobs> <run_on_ifarm>\n"
    exit;
else 
    echo -e '\n------'
    echo -e ' Check the following variable(s):'
    if [[ $run_on_ifarm -ne 1 ]]; then
	echo -e ' "workflowname" : '$workflowname''
    fi
    echo -e ' "outdirpath"   : '$outdirpath' \n------'
    while true; do
	read -p "Do they look good? [y/n] " yn
	echo -e ""
	case $yn in
	    [Yy]*) 
		break; ;;
	    [Nn]*) 
		if [[ $run_on_ifarm -ne 1 ]]; then
		    read -p "Enter desired workflowname : " temp1
		    workflowname=$temp1
		fi
		read -p "Enter desired outdirpath : " temp2
		outdirpath=$temp2		
		break; ;;
	esac
    done
fi

# Sanity check 1: Checking the existance of G4SBS preinit macro
g4sbsmacro=$G4SBS'/scripts/'$preinit'.mac'
g4sbsmacrogmn=$G4SBS'/scripts/gmn/'$preinit'.mac'
if [[ ! -f $g4sbsmacro && ! -f $g4sbsmacrogmn ]]; then
    echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
    echo -e "G4SBS preinit macro, $g4sbsmacro or $g4sbsmacrogmn, doesn't exist! Aborting!\n"
    exit;
fi

# Sanity check 2: Create the output directory if necessary
if [[ ! -d $outdirpath ]]; then
    { #try
	mkdir $outdirpath
    } || { #catch
	echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
	echo -e $outdirpath "doesn't exist and cannot be created!\n"
	exit;
    }
fi

# Creating the workflow
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 create $workflowname
else
    echo -e "\nRunning all jobs on ifarm!\n"
fi

for ((i=$fjobid; i<$((fjobid+njobs)); i++))
do
    # lets submit g4sbs jobs first
    outfilebase=$preinit'_job_'$i
    postscript=$preinit'_job_'$i'.mac'
    g4sbsjobname=$preinit'_job_'$i

    g4sbsscript=$SCRIPT_DIR'/run-g4sbs-simu.sh'' '$preinit' '$postscript' '$nevents' '$outfilebase' '$outdirpath' '$run_on_ifarm' '$G4SBS' '$ANAVER' '$useJLABENV' '$JLABENV

    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -partition production -name $g4sbsjobname -cores 1 -disk 5GB -ram 1500MB $g4sbsscript
    else
	$g4sbsscript
    fi

    # time to aggregate g4sbs job summary
    aggsuminfile=$outdirpath'/'$preinit'_job_'$i'.csv'
    aggsumjobname=$preinit'_asum_job_'$i
    aggsumoutfile=$outdirpath'/'$preinit'_summary.csv'

    aggsumscript=$SCRIPT_DIR'/agg-g4sbs-job-summary.sh'

    if [[ ($i == 0) || (! -f $aggsumoutfile) ]]; then
	$aggsumscript $aggsuminfile 1 $aggsumoutfile $SCRIPT_DIR
    fi
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -antecedent $g4sbsjobname -partition production -name $aggsumjobname -cores 1 -disk 1GB -ram 150MB $aggsumscript $aggsuminfile 0 $aggsumoutfile $SCRIPT_DIR
    else
	$aggsumscript $aggsuminfile 0 $aggsumoutfile $SCRIPT_DIR
    fi
done

# run the workflow and then print status
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 run $workflowname
    echo -e "\n Getting workflow status.. [may take a few minutes!] \n"
    swif2 status $workflowname
fi
