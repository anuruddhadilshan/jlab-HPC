#!/bin/bash

## Retry SWIF2 workflows periodically
## P. Datta

wflows=(wf1 wf2)
niterations=5
sleep_time=3600   # seconds

run_workflow() {

    workflowname=$1
    iteration=$2

    echo "[$workflowname] Retry iteration #: $iteration"

    swif2 run "$workflowname"

    swif2 retry-jobs "$workflowname" -problem SLURM_NODE_FAIL
    swif2 retry-jobs "$workflowname" -problem SLURM_FAILED
    swif2 retry-jobs "$workflowname" -problem SWIF_SYSTEM_ERROR

    swif2 modify-jobs "$workflowname" -time mult 2 -problem SLURM_TIMEOUT
    swif2 retry-jobs "$workflowname" -problem SLURM_TIMEOUT

    swif2 modify-jobs "$workflowname" -ram mult 2 -problem SLURM_OUT_OF_MEMORY
}

for ((i=1; i<=niterations; i++))
do
    echo "========== Iteration $i/$niterations =========="

    # Process workflows in parallel
    for wf in "${wflows[@]}"
    do
        run_workflow "$wf" "$i" &
    done

    # Wait until all workflows finish this iteration
    wait

    # Don't sleep after the final iteration
    if (( i < niterations )); then
        echo "Sleeping for $sleep_time seconds..."
        sleep "$sleep_time"
    fi
done

echo "All workflows completed."
