#!/bin/bash

# ------------------------------------------------------------------------- #
# This script runs sbsdig jobs.                                             #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ------------------------------------------------------------------------- #

#SBATCH --partition=production
#SBATCH --account=halla
#SBATCH --mem-per-cpu=1500

# list of arguments
txtfile=$1 # .txt file containing input file paths
infilename=$2
gemconfig=$3 # valid options: 8,10,12 (Represents # GEM modules)
sbsconfig=$4
run_on_ifarm=$5
g4sbsenv=$6
libsbsdigenv=$7
ANAVER=$8      # Analyzer version
useJLABENV=$9  # Use 12gev_env instead of modulefiles?
JLABENV=${10}     # /site/12gev_phys/softenv.sh version
do_backg=${11}  # if '1', then beam-background will be added during the digitization.
beambackg_root_file=${12} # location of the 'analyzed' (containing background histograms) background ROOT file w/ absolute path.
beambackg_nevents=${13}   # The number of simulated beam-background events used to create above ROOT file in input 12.
backgscale_beamcurr=${14} # The assumed beam current in *Amperes*, to scale the background put on the simulated data accordingly.

if [ -z "$do_backg" ] # default to not doing background if not specified.
then
    do_backg=0 
fi

# paths to necessary libraries (ONLY User specific part) ---- #
export G4SBS=$g4sbsenv
export LIBSBSDIG=$libsbsdigenv
# ----------------------------------------------------------- #

ifarmworkdir=${PWD}
if [[ $isifarm == 1 ]]; then
    SWIF_JOB_WORK_DIR=$ifarmworkdir
    echo -e "Running all jobs on ifarm!"
fi
echo 'Work directory = '$SWIF_JOB_WORK_DIR

# Enabling module
MODULES=/etc/profile.d/modules.sh 
if [[ $(type -t module) != function && -r ${MODULES} ]]; then 
    source ${MODULES} 
fi 
# Choosing software environment
if [[ (! -d /group/halla/modulefiles) || ($useJLABENV -eq 1) ]]; then 
    source /site/12gev_phys/softenv.sh $JLABENV
else 
    module purge
    module use /group/halla/modulefiles    
    module load analyzer/$ANAVER
    module list
fi

# Setup sbsdig specific environments
source $G4SBS/bin/g4sbs.sh
source $LIBSBSDIG/bin/sbsdigenv.sh

# Choosing the right DB file depending on GEM config
if [[ $gemconfig -eq 8 ]]; then
    dbfile=$LIBSBSDIG/db/db_gmn_conf_8gemmodules_$sbsconfig.dat
elif [[ $gemconfig -eq 10 ]]; then
    dbfile=$LIBSBSDIG/db/db_gmn_conf_10gemmodules_$sbsconfig.dat
elif [[ $gemconfig -eq 12 ]]; then
    dbfile=$LIBSBSDIG/db/db_gmn_conf_12gemmodules_$sbsconfig.dat
elif [[ $gemconfig -eq -1 ]]; then #GEP-1
    dbfile=$LIBSBSDIG/db/db_gep1_conf_single-analyzer.dat
elif [[ $gemconfig -eq -2 ]]; then #GEP-2
    dbfile=$LIBSBSDIG/db/db_gep2_conf_single-analyzer.dat
elif [[ $gemconfig -eq -3 ]]; then #GEP-3
    dbfile=$LIBSBSDIG/db/db_gep3_conf_single-analyzer.dat    
else
    echo -e "[run-sbsdig.sh] ERROR!! Enter valid GEM config!"
    exit;
fi
if [[ $sbsconfig == GEN2 || $sbsconfig == GEN3 || $sbsconfig == GEN4 ]]; then
    dbfile=$LIBSBSDIG/db/db_gen_conf_8gemmodules_$sbsconfig.dat
fi

# creating input text file
echo $infilename >>$txtfile
echo 'endlist' >>$txtfile

# if background is going to be included, 
if [[ $do_backg -eq 1 ]]; then
    if [ -f "$beambackg_root_file" ]; then #This check is redundant as it is already supposed to be checked by up-stream 'submit' scripts but let's do it anyway.
        echo "$beambackg_root_file $beambackg_nevents $backgscale_beamcurr" >>$txtfile
        echo 'end_bkgdinfo' >>$txtfile	
    else
        echo -e "[run-sbsdig.sh] EROOR!! The entered beam-background ROOT file does not exists."
        exit;
    fi
else
    echo "No backg added!"
fi

# run the sbsdig command
sbsdig $dbfile $txtfile

# cleaning up the work directory
rm $txtfile
