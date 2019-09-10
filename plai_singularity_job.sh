#PBS -o hpc_output/${PBS_JOBID}.out
#PBS -e hpc_output/${PBS_JOBID}.err

# THIS SCRIPT IS CALLED OUTSIDE USING "qsub"
# FOLLOWING ENV VARIABLES HAS TO BE PROVIDED:
#   - CMD
#   - CONTAINER
#   - BASERESULTSDIR
#   - OVERLAYDIR_CONTAINER
#   - RESULTSDIR_CONTAINER

PBS_TMPDIR="/var/tmp/amunk_tmp_${PBS_JOBID}"

mkdir -p $PBS_TMPDIR

DB="db_${PBS_JOBID}"
OVERLAY="overlay_${PBS_JOBID}"
TMP="tmp_${PBS_JOBID}"

cd "$BASERESULTSDIR"

# move data to temporary SLURM DIR which is much faster for I/O
echo "Copying singularity to ${PBS_TMPDIR}"
time rsync -av "$CONTAINER" "${PBS_TMPDIR}"

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
cd "$PBS_TMPDIR"

if [ ! -z "${STUFF_TO_TAR}" ]; then
    echo "Moving tarball to slurm tmpdir"
    time tar -xf "${BASERESULTSDIR}/tar_ball_${stuff_to_tar_suffix}.tar"
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

echo "COMMANDS GIVEN: ${CMD}"
echo "STUFF TO TAR: ${STUFF_TO_TAR}"
echo "RESULTS TO TAR: ${RESULTS_TO_TAR}"

# --nv option: bind to system libraries (access to GPUS etc.)
# --no-home and --contain mimics the docker container behavior
# without those /home and more will be mounted be default
# using "run" executed the "runscript" specified by the "%runscript"
# any argument give "CMD" is passed to the runscript
/usr/local/bin/singularity run \
            --nv \
            -B "results:/results" \
            -B "${DB}":/db \
            -B "${TMP}":/tmp \
            -B "${OVERLAY}":"${OVERLAYDIR_CONTAINER}" \
            --no-home \
            --contain \
            --writable-tmpfs \
            "$CONTAINER" \
            "$CMD" 2>&1 | tee -a ${EXP_DIR}/hpc_scripts/hpc_output/output_${PBS_JOBID}.txt


######################################################################

# MAKE SURE THE RESULTS SAVED HAVE UNIQUE NAMES EITHER USING JOB ID AND
# OR SOME OTHER WAY - !!!! OTHERWISE STUFF WILL BE OVERWRITEN !!!!

######################################################################

if [ -z ${RESULTS_TO_TAR} ]; then
    # IF NO RESULTS TO TAR IS SPECIFIED - MAKE A TARBALL OF THE ENTIRE RESULTS DIRECTORY
    RESULTS_TO_TAR=("results")
else
    # if variable is provided make into an array
    IFS=' ' read -a RESULTS_TO_TAR <<< $RESULTS_TO_TAR
fi

# replace any "/"-character or spaces with "_" to use as a name
results_to_tar_suffix=$(tr ' |/' '_' <<< ${RESULTS_TO_TAR[@]})

# make a tarball of the results
time tar -cf "tar_ball_${results_to_tar_suffix}_${PBS_JOBID}.tar" ${RESULTS_TO_TAR[@]}

# move unpack the tarball to the BASERESULTSDIR
cd $BASERESULTSDIR
time tar --keep-newer-files -xf "${PBS_TMPDIR}/tar_ball_${results_to_tar_suffix}_${PBS_JOBID}.tar"

######################################################################

# CLEANUP

# remove temporary directories
rm -rf "${PBS_TMPDIR}"
