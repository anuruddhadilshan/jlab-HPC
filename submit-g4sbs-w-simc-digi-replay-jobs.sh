#!/bin/bash

# ------------------------------------------------------------------------- #
# This script runs g4sbs jobs using existing SIMC outputs as inputs. Then   #
# runs the corresponding sbsdig and replay jobs.                            #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 09-29-2025                           #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script below.  #
# ---------                                                                 #
# ------------------------------------------------------------------------- #

# ------------------- Notes and Instructions (READ BEFORE EXECUTION) -------------------- #
# --------------------------------------------------------------------------------------- #
# 1. This script takes 7 arguments. See description below.                                #
# 2. Total no. of events must match # SIMC events for consistency.                        #
# 3. Be sure to edit "workflowname" variable appropriately before executing script.       #
# 4. Be sure to edit "outdirpath" variable appropriately before executing script.         #
# 6. List of interdependencies: utility.py, run-g4sbs-w-simc.sh, run-sbsdig.sh,  run-digi-#
#    replay.sh | All these scripts must be present in the $SCRIPT_DIR                     #
# --------------------------------------------------------------------------------------- #

# Setting necessary environments via setenv.sh
source setenv.sh

# Set path to version information
USER_VERSION_PATH="$SCRIPT_DIR/misc/version_control/user_env_version.conf"
# Check to verify information is at location and update as necessary
$SCRIPT_DIR/misc/version_control/check_and_update_versions.sh

# ------ Variables needed to be set properly for successful execution ------ #
# -------------------------------------------------------------------------- #
# SIMC input file (don't add file extension). Must be located at $SIMC/infiles. 
# G4SBS macro should have same name as SIMC input file just with different 
# file extention and should be located at $G4SBS/scripts.
infile=$1       # File base of the input SIMC file
prefix=$2       # Optional prefix to be added to the g4sbs macro to be used
simcindir=$3    # Directory containing SIMC outputs to be used as g4sbs inputs
sbsconfig=$4    # SBS configuration (Valid options: 4,7,11,14,8,9
nevents=$5      # No. of g4sbs events to generate (must match # SIMC events)
fjobid=$6       # first job id
njobs=$7        # total no. of jobs to submit 
run_on_ifarm=$8 # 1=>Yes (If true, runs all jobs on ifarm)
# ----/\---- Above variables are taken as arguments to this script ---/\---- # 
# Workflow name
workflowname=
# Specify a directory on volatile to store simc, g4sbs, sbsdig, & replayed outfiles.
# Working on a single directory is convenient & safe for the above mentioned
# four processes to run coherently without any error.
outdirpath=
# -------------------------------------------------------------------------- #

# ------ Variables to allocate time and memory for each type of jobs  ------ #
# -------------------------------------------------------------------------- #
# g4sbs jobs
G4SBSJOBram='1200MB'
G4SBSJOBdisk='1GB'
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
if [[ "$#" -ne 8 ]]; then
    echo -e " \n --!!--\n ERROR! Illegal number of arguments!! \n ------"
    echo -e " This script takes 8 arguments:"
    echo -e "  1. <infile>       : File base of the input SIMC file."
    echo -e "  2. <prefix>       : Optional prefix to be added to the g4sbs macro to be used."    
    echo -e "  3. <simcindir>    : Directory containing SIMC outputs to be used as g4sbs inputs"
    echo -e "  4. <sbsconfig>    : SBS configuration (Valid options: GMN4,GMN7,GMN11,GMN14,GMN8,GMN9,GEN2,GEN3,GEN4)."    
    echo -e "  5. <nevents>      : No. of g4sbs events to generate (must match # SIMC events)"  
    echo -e "  6. <fjobid>       : First job id."  
    echo -e "  7. <njobs>        : Total no. of jobs to submit."
    echo -e "  8. <run_on_ifarm> : 1=>Yes (If true, runs all jobs on ifarm)"
    echo -e " ------"
    echo -e ' ** Make sure "workflowname" & "outdirpath" variables are set properly in the script.'
    echo -e ' ** Read the "Notes and Instructions" block at the top of script for more information.\n'
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

# adding the optional prefix
simcfilebase=$infile
if [[ -n "$prefix" ]]; then
    infile="${prefix}_${infile}"
fi

# Sanity check 4: Finding matching G4SBS preinit macro for SIMC infile
g4sbsmacro=$G4SBS'/scripts/'$infile'.mac'
g4sbsmacrogmn=$G4SBS'/scripts/gmn/'$infile'.mac'
if [[ ! -f $g4sbsmacro && ! -f $g4sbsmacrogmn ]]; then
    echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
    echo -e "G4SBS preinit macro, $g4sbsmacro or $g4sbsmacrogmn, doesn't exist! Aborting!\n"
    exit;
fi

# Reading SIMC infile ("ngen" flag) to determine no. of g4sbs events to generate
#nevents=$(python3 $SCRIPT_DIR'/'utility.py 'grab_simc_param_value' $simcmacro 'ngen')
if [[ $nevents -lt 0 ]]; then
    echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
    echo -e "Illegal no. of events! nevents = $nevents | Aborting!\n"
    exit;
else
    echo -e "\n ** $nevents SIMC (and g4sbs) events will be generated per job!"
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
else
    echo -e "Enter valid SBS config! Valid options: GMN4,GMN7,GMN11,GMN14,GMN8,GMN9,GEN2,GEN3,GEN4"
    exit;
fi

# Loop to create jobs
for ((i=$fjobid; i<$((fjobid+njobs)); i++))
do
    # submitting SIMC jobs
    simcoutfile=$simcindir'/'$simcfilebase'_job_'$i'.root'
    if [[ ! -f $simcoutfile ]]; then
	echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
	echo -e "SIMC ROOT file, $simcoutfile, doesn't exist for job $i! Skipping!\n"
	continue;
    fi
    
    # submitting g4sbs jobs using SIMC outfiles
    outfilebase=$infile'_job_'$i
    postscript=$infile'_job_'$i'.mac'
    g4sbsjobname=$infile'_g4sbs_job_'$i

    g4sbsscript=$SCRIPT_DIR'/run-g4sbs-w-simc.sh'' '$infile' '$postscript' '$nevents' '$outfilebase' '$outdirpath' '$simcoutfile' '$run_on_ifarm' '$G4SBS' '$ANAVER' '$useJLABENV' '$JLABENV

    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -partition production -name $g4sbsjobname -cores 1 -disk $G4SBSJOBdisk -ram $G4SBSJOBram -time $G4SBSJOBtime $g4sbsscript
    else
	$g4sbsscript
    fi

    # now, it's time for digitization
    txtfile=$infile'_job_'$i'.txt'
    sbsdigjobname=$infile'_digi_job_'$i
    sbsdiginfile=$outdirpath'/'$outfilebase'.root'

    sbsdigscript=$SCRIPT_DIR'/run-sbsdig.sh'' '$txtfile' '$sbsdiginfile' '$gemconfig' '$sbsconfig' '$run_on_ifarm' '$G4SBS' '$LIBSBSDIG' '$ANAVER' '$useJLABENV' '$JLABENV
    
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -antecedent $g4sbsjobname -partition production -name $sbsdigjobname -cores 1 -disk $SBSDIGJOBdisk -ram $SBSDIGJOBram -time $SBSDIGJOBtime $sbsdigscript
    else
	$sbsdigscript
    fi

    # finally, lets replay the digitized data
    digireplayinfile=$infile'_job_'$i
    digireplayjobname=$infile'_digi_replay_job_'$i

    digireplayscript=$SCRIPT_DIR'/run-digi-replay.sh'' '$digireplayinfile' '$sbsconfig' '-1' '$outdirpath' '$run_on_ifarm' '$ANALYZER' '$SBSOFFLINE' '$SBS_REPLAY' '$ANAVER' '$useJLABENV' '$JLABENV
    
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -antecedent $sbsdigjobname -partition production -name $digireplayjobname -cores 1 -disk $REPLAYJOBdisk -ram $REPLAYJOBram -time $REPLAYJOBtime $digireplayscript
    else
	$digireplayscript
    fi
done

# # keep a copy of SIMC job summary file in the $outdirpath as well
# cp $simcnormtable $outdirpath

# add a copy of the version control to simcout for traceability
# Define the path for the version file within the output directory
VERSION_FILE="$simcoutdir/${infile}_version.txt"

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