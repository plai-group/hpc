#!/bin/bash

# THIS SCRIPT IS CALLED OUTSIDE USING "sbatch"
# FOLLOWING ENV VARIABLES HAS TO BE PROVIDED:
#   - CMD
#   - CONTAINER
#   - BASERESULTSDIR
#   - OVERLAYDIR_CONTAINER
#   - STUFF_TO_TAR - e.g. move the training data to the PLAI_TMPDIR for traning a network
#   - RESULTS_TO_TAR - the results we seek to move back from the temporary file; e.g. if we train an inference network we don't need to also move the training data back again

# see eg. https://docs.computecanada.ca/wiki/A_tutorial_on_%27tar%27

PLAI_TMPDIR="/scratch-ssd/amunk_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"

mkdir -p $PLAI_TMPDIR

DB="db_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
OVERLAY="overlay_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
TMP="tmp_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
HOME_OVERLAY="home_overlay_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"

cd "$BASERESULTSDIR"

# move data to temporary SLURM DIR which is much faster for I/O
echo "Copying singularity (${CODE_DIR}/${CONTAINER}) to ${PLAI_TMPDIR}"
time rsync -av "${CODE_DIR}/${CONTAINER}" "${PLAI_TMPDIR}"
time rsync -av "${CODE_DIR}/hpc_files/array_command_list_${EXP_NAME}.txt" "${PLAI_TMPDIR}"

# replace any "/"-character or spaces with "_" to use as a name
stuff_to_tar_suffix=$(tr ' |/' '_' <<< ${STUFF_TO_TAR})

if [ ! -z "${STUFF_TO_TAR}" ]; then
    if [ ! -f "tar_ball_${stuff_to_tar_suffix}.tar" ]; then
        # make tarball in $BASERESULTSDIR
        echo "Creating tarball"
        time tar -cf "tar_ball_${stuff_to_tar_suffix}.tar" $STUFF_TO_TAR
    fi
fi

# go to temporary directory
cd "$PLAI_TMPDIR"

if [ ! -z "${STUFF_TO_TAR}" ]; then
    echo "Moving tarball to slurm tmpdir"
    time tar --keep-newer-files -xf "${BASERESULTSDIR}/tar_ball_${stuff_to_tar_suffix}.tar"
fi

# ensure resultsdir exists
if [ ! -d results ]; then
    mkdir results
fi

# make directory that singularity can mount to and use to setup a database
# such as postgresql or a monogdb etc.
if [ ! -d "$DB" ]; then
    mkdir "$DB"
fi

# make overlay directory, which may or may not be used
if [ ! -d "$OVERLAY" ]; then
    mkdir "$OVERLAY"
fi

# make tmp overlay directory otherwise /tmp in container will have very limited disk space
if [ ! -d "$TMP" ]; then
    mkdir "$TMP"
fi

if [ ! -d datasets ]; then
    mkdir datasets
fi

if [ ! -d "$HOME_OVERLAY" ]; then
    mkdir "$HOME_OVERLAY"
fi

CMD=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "array_command_list_${EXP_NAME}.txt")
echo "COMMANDS GIVEN: ${CMD}"
echo "STUFF TO TAR: ${STUFF_TO_TAR}"
echo "RESULTS TO TAR: ${RESULTS_TO_TAR}"

# --nv option: bind to system libraries (access to GPUS etc.)
# --no-home and --containall mimics the docker container behavior
# --cleanenv is crucial to get wandb to work, as local environment variables may cause it to break on some systems
# without those /home and more will be mounted be default
# using "run" executed the "runscript" specified by the "%runscript"
# any argument give "CMD" is passed to the runscript
SINGULARITYENV_SLURM_JOB_ID=$SLURM_JOB_ID \
    SINGULARITYENV_SLURM_PROCID=$SLURM_PROCID \
    SINGULARITYENV_SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID \
    SINGULARITYENV_SLURM_ARRAY_TASK_ID=$SLURM_ARRAY_TASK_ID \
    SINGULARITYENV_WANDB_ENTITY="Muffiuz" \
    /opt/singularity/bin/singularity run \
    --nv \
    --cleanenv \
    -B results:"${RESULTS_MOUNT}" \
    -B datasets:/datasets \
    -B "${HOME_OVERLAY}":"${HOME}" \
    -B ${DB}:/db \
    -B ${TMP}:/tmp \
    -B ${OVERLAY}:${OVERLAYDIR_CONTAINER} \
    --no-home \
    --containall \
    --writable-tmpfs \
    ${CONTAINER} \
    ${CMD}

######################################################################

# Move results back (if RESULTS_TO_TAR is set)

# MAKE SURE THE RESULTS SAVED HAVE UNIQUE NAMES EITHER USING JOB ID AND
# OR SOME OTHER WAY - !!!! OTHERWISE STUFF WILL BE OVERWRITTEN !!!!

######################################################################

if  [ ! -z "${RESULTS_TO_TAR}" ]; then
    # if variable is provided make into an array
    IFS=' ' read -a RESULTS_TO_TAR <<< "${RESULTS_TO_TAR[@]}"
    # replace any "/"-character or spaces with "_" to use as a name
    results_to_tar_suffix="$(tr ' |/' '_' <<< ${RESULTS_TO_TAR[@]})"

    # make a tarball of the results
    time tar -cf "tar_ball_${results_to_tar_suffix}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.tar" "${RESULTS_TO_TAR[@]}"

    # move unpack the tarball to the BASERESULTSDIR
    cd "${BASERESULTSDIR}/${EXP_NAME}"
    time tar --keep-newer-files -xf "${PLAI_TMPDIR}/tar_ball_${results_to_tar_suffix}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.tar"
fi

######################################################################

# CLEANUP

# remove temporary directories
rm -rf "${PLAI_TMPDIR}"
echo "CHECK WHATS IN /scratch-ssd:" && ls /scratch-ssd
