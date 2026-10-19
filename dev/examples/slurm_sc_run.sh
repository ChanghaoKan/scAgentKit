#!/usr/bin/env bash
# Site-specific template only. This script does not submit itself.
# Review the account/partition/time/memory requests with your cluster's guidance.
#SBATCH --job-name=scagentkit-resume
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=scagentkit-%j.log

set -euo pipefail

# Configure these in your submission environment or replace them below.
# Use durable server storage, not node-local temporary storage.
: "${SCAGENTKIT_PROJECT_DIR:?Set the durable project directory}"
: "${SCAGENTKIT_R_DRIVER:?Set the path to your reviewed R driver}"

if [[ ! -f "$SCAGENTKIT_R_DRIVER" ]]; then
  printf '%s\n' 'The selected R driver does not exist.' >&2
  exit 1
fi

# Activate your site's R environment here, if required, for example:
# module load R
# Keep API credentials in the running machine's user secret/environment mechanism.
# Do not echo them or add them to this script, the project, or scheduler logs.

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-2}"
export OPENBLAS_NUM_THREADS="$OMP_NUM_THREADS"
export VECLIB_MAXIMUM_THREADS="$OMP_NUM_THREADS"

# The driver should accept a project directory and a mode, and call sc_run() for
# 'run' or sc_run_resume() for 'resume'. Awaiting review is a normal saved pause;
# the R process should return normally so the compute allocation can end.
# Human approval occurs separately; a later resume job uses the same directory.
exec Rscript --vanilla "$SCAGENTKIT_R_DRIVER" "$SCAGENTKIT_PROJECT_DIR" "${SCAGENTKIT_RUN_MODE:-resume}"
