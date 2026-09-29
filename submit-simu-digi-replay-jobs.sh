#!/bin/bash

# ------------------------------------------------------------------------- #
# This script submits g4sbs, sbsdig, and replay jobs to the batch farm and  #
# enusres they run in right order. There is a flag that can be set to run   #
# all the jobs on ifarm as well.                                            #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ---------                                                                 #
# S. Seeds <sseeds@jlab.org> Added version control machinery                #
# ------------------------------------------------------------------------- #

# Setting necessary environments via setenv.sh
source setenv.sh

# Set path to version information
USER_VERSION_PATH="$SCRIPT_DIR/misc/version_control/user_env_version.conf"
# Check to verify information is at location and update as necessary
$SCRIPT_DIR/misc/version_control/check_and_update_versions.sh

# List of arguments
preinit=$1      # G4SBS preinit macro w/o file extention (Must be located at $G4SBS/scripts or $G4SBS/scripts/gmn)
sbsconfig=$2    # SBS configuration (Valid options: GMN4,GMN7,GMN11,GMN14,GMN8,GMN9,GEN2,GEN3,GEN4)
nevents=$3      # No. of events to generate per job
fjobid=$4       # first job id
njobs=$5        # total no. of jobs to submit 
run_on_ifarm=$6 # 1=>Yes (If true, runs all jobs on ifarm)
# Workflow name (Not relevant if run_on_ifarm = 1)
workflowname=
# Specify a directory on volatile to store g4sbs, sbsdig, & replayed files.
# Working on a single directory is convenient & safe for the above mentioned
# three processes to run smoothly.
outdirpath=
# -------------------------------------------------------------------------- #

# ------ Variables to allocate time and memory for each type of jobs  ------ #
# -------------------------------------------------------------------------- #
# g4sbs jobs
G4SBSJOBram='1500MB'
G4SBSJOBdisk='5GB'
G4SBSJOBtime='24h'
# sbsdig jobs
SBSDIGJOBram='1200MB'
SBSDIGJOBdisk='100MB'
SBSDIGJOBtime='6h'
# replay jobs
REPLAYJOBram='1200MB'
REPLAYJOBdisk='1GB'
REPLAYJOBtime='6h'
# -------------------------------------------------------------------------- #

# Sanity check 0: Checking the environments
if [[ ! -d $SCRIPT_DIR ]]; then
    echo -e '\nERROR!! Please set "SCRIPT_DIR" path properly in setenv.sh script!\n'; exit;
elif [[ ! -d $G4SBS ]]; then
    echo -e '\nERROR!! Please set "G4SBS" path properly in setenv.sh script!\n'; exit;
elif [[ ! -d $LIBSBSDIG ]]; then
    echo -e '\nERROR!! Please set "LIBSBSDIG" path properly in setenv.sh script!\n'; exit;
elif [[ (! -d $ANALYZER) && ($useJLABENV -eq 1) ]]; then
    echo -e '\nERROR!! Please set "ANALYZER" path properly in setenv.sh script!\n'; exit;
elif [[ ! -d $SBSOFFLINE ]]; then
    echo -e '\nERROR!! Please set "SBSOFFLINE" path properly in setenv.sh script!\n'; exit;
elif [[ ! -d $SBS_REPLAY ]]; then
    echo -e '\nERROR!! Please set "SBS_REPLAY" path properly in setenv.sh script!\n'; exit;
fi

# Sanity check 1: Validating the number of arguments provided
if [[ "$#" -ne 6 ]]; then
    echo -e "\n--!--\n Illegal number of arguments!!"
    echo -e " This script expects 6 arguments: <preinit> <sbsconfig> <nevents> <fjobid> <njobs> <run_on_ifarm>\n"
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
		read -p "Enter desired outdirpath   : " temp2
		outdirpath=$temp2		
		break; ;;
	esac
    done
fi

# Sanity check 2: Checking the existance of G4SBS preinit macro
g4sbsmacro=$G4SBS'/scripts/'$preinit'.mac'
g4sbsmacrogmn=$G4SBS'/scripts/gmn/'$preinit'.mac'
if [[ ! -f $g4sbsmacro && ! -f $g4sbsmacrogmn ]]; then
    echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
    echo -e "G4SBS preinit macro, $g4sbsmacro or $g4sbsmacrogmn, doesn't exist! Aborting!\n"
    exit;
fi

# Create the output directory if necessary
if [[ ! -d $outdirpath ]]; then
    { #try
	mkdir $outdirpath
    } || { #catch
	echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
	echo -e $outdirpath "doesn't exist and cannot be created! \n"
	exit;
    }
fi

# Creating the workflow
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 create $workflowname
else
    echo -e "\nRunning all jobs on ifarm!\n"
fi

# Choosing the right GEM config for digitization
gemconfig=0
if [[ ($sbsconfig == GMN4) || ($sbsconfig == GMN7) ]]; then
    gemconfig=12
elif [[ $sbsconfig == GMN11 ]]; then
    gemconfig=10
elif [[ ($sbsconfig == GMN14) || ($sbsconfig == GMN8) || ($sbsconfig == GMN9) || ($sbsconfig == GEN2) || ($sbsconfig == GEN3) || ($sbsconfig == GEN4) ]]; then
    gemconfig=8
    # GEP has only one SBS GEM config. However, each setting has a different DB file for digitization. To handle that without major change to the code we are using gemconfig flag.
elif [[ $sbsconfig == GEP1 ]]; then
    gemconfig=-1
elif [[ $sbsconfig == GEP2 ]]; then
    gemconfig=-2
elif [[ $sbsconfig == GEP3 ]]; then
    gemconfig=-3        
else
    echo -e "Enter valid SBS config! Valid options: GMN4,GMN7,GMN11,GMN14,GMN8,GMN9,GEN2,GEN3,GEN4,GEP1,GEP2,GEP3"
    exit;
fi

for ((i=$fjobid; i<$((fjobid+njobs)); i++))
do
    # lets submit g4sbs jobs first
    outfilebase=$preinit'_job_'$i
    postscript=$preinit'_job_'$i'.mac'
    g4sbsjobname=$preinit'_job_'$i

    g4sbsscript=$SCRIPT_DIR'/run-g4sbs-simu.sh'' '$preinit' '$postscript' '$nevents' '$outfilebase' '$outdirpath' '$run_on_ifarm' '$G4SBS' '$ANAVER' '$useJLABENV' '$JLABENV

    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -partition production -name $g4sbsjobname -cores 1 -disk $G4SBSJOBdisk -ram $G4SBSJOBram -time $G4SBSJOBtime $g4sbsscript
    else
	$g4sbsscript
    fi

    # time to aggregate g4sbs job summary
    aggsuminfile=$outdirpath'/'$preinit'_job_'$i'.csv'
    aggsumjobname=$preinit'_asum_job_'$i
    aggsumoutfile=$outdirpath'/'$preinit'_summary.csv'

    aggsumscript=$SCRIPT_DIR'/agg-g4sbs-job-summary.sh'

    if [[ ($i == 0) || (! -f $aggsumoutfile) ]]; then
	$aggsumscript $aggsuminfile '1' $aggsumoutfile $SCRIPT_DIR
    fi
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -antecedent $g4sbsjobname -partition production -name $aggsumjobname -cores 1 -disk 1GB -ram 150MB -time 1h $aggsumscript $aggsuminfile '0' $aggsumoutfile $SCRIPT_DIR
    else
	$aggsumscript $aggsuminfile '0' $aggsumoutfile $SCRIPT_DIR
    fi

    # now, it's time for digitization
    txtfile=$preinit'_job_'$i'.txt'
    sbsdigjobname=$preinit'_digi_job_'$i
    sbsdiginfile=$outdirpath'/'$outfilebase'.root'

    sbsdigscript=$SCRIPT_DIR'/run-sbsdig.sh'' '$txtfile' '$sbsdiginfile' '$gemconfig' '$sbsconfig' '$run_on_ifarm' '$G4SBS' '$LIBSBSDIG' '$ANAVER' '$useJLABENV' '$JLABENV
    
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -antecedent $g4sbsjobname -partition production -name $sbsdigjobname -cores 1 -disk $SBSDIGJOBdisk -ram $SBSDIGJOBram -time $SBSDIGJOBtime $sbsdigscript
    else
	$sbsdigscript
    fi

    # finally, lets replay the digitized data
    digireplayinfile=$preinit'_job_'$i
    digireplayjobname=$preinit'_digi_replay_job_'$i

    digireplayscript=$SCRIPT_DIR'/run-digi-replay.sh'' '$digireplayinfile' '$sbsconfig' '-1' '$outdirpath' '$run_on_ifarm' '$ANALYZER' '$SBSOFFLINE' '$SBS_REPLAY' '$ANAVER' '$useJLABENV' '$JLABENV
    
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -antecedent $sbsdigjobname -partition production -name $digireplayjobname -cores 1 -disk $REPLAYJOBdisk -ram $REPLAYJOBram -time $REPLAYJOBtime $digireplayscript
    else
	$digireplayscript
    fi
done

# add a copy of the version control to outputdir for traceability
# Define the path for the version file within the output directory
VERSION_FILE="$outdirpath/${preinit}_version.txt"

# Function to append version information to the file
append_version_info() {
    # Add the date and time of creation to the version file
    echo "# Version file created on $(date '+%Y-%m-%d %H:%M:%S')" >> "$VERSION_FILE"

    # Add the configured run range to the version file
    ljobid=$((fjobid + njobs))
    echo "# This run range from $fjobid to $ljobid" >> "$VERSION_FILE"

    # Append the contents of last_update.conf to the version file
    echo "" >> "$VERSION_FILE" # Add an empty line for readability
    cat "$USER_VERSION_PATH" >> "$VERSION_FILE"
    echo "" >> "$VERSION_FILE" # Add an empty line for readability
}

# Check if the VERSION_FILE already exists
if [ -f "$VERSION_FILE" ]; then
    # VERSION_FILE exists, append new version information
    echo "Appending version information to existing $VERSION_FILE"
    append_version_info
else
    # VERSION_FILE does not exist, create it and add version information
    echo "Creating new $VERSION_FILE and adding version information"
    touch "$VERSION_FILE" # Ensure the file exists before appending
    append_version_info
fi

echo "Version information has been saved to $VERSION_FILE"

# run the workflow and then print status
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 run $workflowname
    echo -e "\n Getting workflow status.. [may take a few minutes!] \n"
    swif2 status $workflowname
fi
