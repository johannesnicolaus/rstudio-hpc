#!/bin/bash
#SBATCH -J rstudio
#SBATCH --export=ALL
#SBATCH --nodes=1 --ntasks-per-node=2
#SBATCH --signal=2
##SBATCH --no-requeue
#SBATCH -o /flash/LuscombeU/nico/rstudio.out
#SBATCH -e /flash/LuscombeU/nico/rstudio.err
#SBATCH -p compute
#SBATCH --mem=128G

# modified from https://www.rocker-project.org/use/singularity/
export PASSWORD=$(openssl rand -base64 15)

# get unused socket per https://unix.stackexchange.com/a/132524
# tiny race condition between the python & singularity commands
readonly PORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

mkdir ${HOME}/rstudio-hpc
cat >> ${HOME}/rstudio-hpc/log.txt << END

--- `date` ---
1. SSH tunnel from your workstation using the following command:

   ssh -L 8787:${HOSTNAME}:${PORT} ${USER}@deigo

   and point your web browser to http://localhost:8787

2. log in to RStudio Server using the following credentials:

   user: ${USER}
   password: ${PASSWORD}

When done using RStudio Server, terminate the job by:

1. Exit the RStudio Session ('power' button in the top right corner of the RStudio window)
2. Issue the following command on the login node:

      scancel ${PBS_JOBID}
END

# make ssh key for passwordless internode ssh
# if you already have a public key copy it to .ssh/authorized_keys
if [ ! -e ${HOME}/.ssh/id_rsa.pub ]
then
  cat /dev/zero | ssh-keygen -t rsa -N ""
  cat ${HOME}/.ssh/id_rsa.pub >> ${HOME}/.ssh/authorized_keys
  chmod 700 ${HOME}/.ssh; chmod 640 ${HOME}/.ssh/authorized_keys
fi

# User-installed R packages go into their home directory
if [ ! -e ${HOME}/.Renviron ]
then
  printf '\nNOTE: creating ~/.Renviron file\n\n'
  echo 'R_LIBS_USER=~/R/%p-library/%v' >> ${HOME}/.Renviron
  # env vars need to go in the .Renviron file
fi

# make outfolder (check for errors)
mkdir -p ${HOME}/rstudio-hpc/output

# create secure-cookie-key (thanks @MboiTui)
if [ ! -e ${HOME}/tmp/rstudio-server/${USER}_secure-cookie-key ]
then
   mkdir -p ${HOME}/tmp/rstudio-server/
   export UUID=$(python  -c 'import uuid; print(uuid.uuid1())')
   echo ${UUID} > ${HOME}/tmp/rstudio-server/${USER}_secure-cookie-key
fi

# By default the only host file systems mounted within the container are $HOME, /tmp, /proc, /sys, and /dev.
# you can use --bind [-B] to bind other file systems
module load singularity
singularity exec /flash/LuscombeU/nico/test/rstudio-hpc/test/test.sif bash -c "\
  source ${HOME}/.Renviron && \
  rserver --www-port ${PORT} --auth-none=0 --auth-pam-helper-path=pam-helper \
  --secure-cookie-key-file ${HOME}/tmp/rstudio-server/${USER}_secure-cookie-key
  "

echo "finished"
