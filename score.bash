#!/bin/bash

current_date=$(date +"%Y%m%d_%H%M")
echo "BEGIN SCORE SCRIPT ${current_date}"

module load anaconda/miniconda-latest
eval "$(conda shell.bash hook)"
conda activate "$HOME/testing/env/test"

pushd "$HOME/testing/"
mpirun python score.py \
    --prefix "results$current_date" \
    --log "score$current_date.log"

echo "END SCORE SCRIPT $(date)"
