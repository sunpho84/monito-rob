#!/bin/bash

#SBATCH -p boost_usr_prod
##SBATCH -A INF24_lqcd123_1
#SBATCH -A IscrB_VITO-QCD 
#SBATCH --output=tw25_s1.%j.out
#  SBATCH  --time 9:00:00
##SBATCH --qos=qos_lowprio
#SBATCH -N 2
#SBATCH --exclusive
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-node=4
#SBATCH --mem=494000
#SBATCH --job-name=48t25s1


export QUDA_RESOURCE_PATH=$PWD
export OMP_NUM_THREADS=4
export OMP_PROC_BIND=true
export KMP_AFFINITY=scatter,granularity=fine,1
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/leonardo/home/userexternal/fsanfili/programs/quda_bacchio/build/install/lib



mkdir -p out_tw_25_s
rm -fr stop_tw_25_s
mpirun --map-by socket:PE=8 \
        --rank-by core \
        -np ${SLURM_NTASKS} \
        /leonardo/home/userexternal/fsanfili/programs/nissa/build3/bin/ib input tw_25_s
