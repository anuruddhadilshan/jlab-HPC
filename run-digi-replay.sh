#!/bin/bash

# ------------------------------------------------------------------------- #
# This script runs replay jobs of pseudo (i.e. digitized) data.             #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ------------------------------------------------------------------------- #

#SBATCH --partition=production
#SBATCH --account=halla
#SBATCH --mem-per-cpu=1500

# list of arguments
inputfile=$1
sbsconfig=$2
maxevents=$3
datadir=$4
run_on_ifarm=$5
analyzerenv=$6
sbsofflineenv=$7
sbsreplayenv=$8
ANAVER=$9        # Analyzer version
useJLABENV=${10} # Use 12gev_env instead of modulefiles?
JLABENV=${11}    # /site/12gev_phys/softenv.sh version

# paths to necessary libraries (ONLY User specific part) ---- #
export ANALYZER=$analyzerenv
export SBSOFFLINE=$sbsofflineenv
export SBS_REPLAY=$sbsreplayenv
# ----------------------------------------------------------- #

ifarmworkdir=${PWD}
if [[ $run_on_ifarm == 1 ]]; then
    SWIF_JOB_WORK_DIR=$ifarmworkdir
    echo -e "Running all jobs on ifarm!"
fi
echo -e 'Work directory = '$SWIF_JOB_WORK_DIR

experiment="${sbsconfig:0:3}"
config="${sbsconfig:3}"

# Enabling module
MODULES=/etc/profile.d/modules.sh 
if [[ $(type -t module) != function && -r ${MODULES} ]]; then 
    source ${MODULES} 
fi 
# Choosing software environment
if [[ (! -d /group/halla/modulefiles) || ($useJLABENV -eq 1) ]]; then 
    source /site/12gev_phys/softenv.sh $JLABENV
    source $ANALYZER/bin/setup.sh
else
    module purge
    module use /group/halla/modulefiles
    module load analyzer/$ANAVER
    module list
fi

# setting analyzer specific paths
export ANALYZER_CONFIGPATH=$SBS_REPLAY/replay
source $SBSOFFLINE/bin/sbsenv.sh

export DB_DIR=$SBS_REPLAY/DB_MC
export OUT_DIR=$SWIF_JOB_WORK_DIR
export DATA_DIR=$datadir

# echoing for debugging
echo " == Might help with debuggig == \n"
echo -e "PATH= "$PATH "\n"
echo -e "LD_LIBRARY_PATH= "$LD_LIBRARY_PATH "\n"
echo -e "ROOTSYS= "$ROOTSYS "\n"
echo -e "$(env | grep -i root) \n" 

# handling any existing .rootrc file in the work directory
# mainly necessary while running the jobs on ifarm
if [[ -f .rootrc ]]; then
    mv .rootrc .rootrc_temp
fi
cp $SBS/run_replay_here/.rootrc $SWIF_JOB_WORK_DIR

if [ $experiment == 'GMN' ] #GMN replay
then
    analyzer -b -q 'replay_gmn_mc.C+("'$inputfile'",'$config','$maxevents')'    
fi

if [ $experiment == 'GEN' ] #GEN replay
then
    analyzer -b -q 'replay_gen_mc.C+("'$inputfile'",'$config','$maxevents')'    
fi

if [ $experiment == 'GEP' ] #GEP replay
then
    analyzer -b -q 'replay_gep_mc.C+("'$inputfile'",'$config','$maxevents')'    
fi

# move output files
mv $OUT_DIR'/replayed_'$inputfile'.root' $DATA_DIR
mv $OUT_DIR'/replayed_'$inputfile'.log' $DATA_DIR

# clean up the work directory
rm .rootrc
if [[ -f .rootrc_temp ]]; then
    mv .rootrc_temp .rootrc
fi
