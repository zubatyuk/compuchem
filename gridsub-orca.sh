#!/bin/bash

#defaults
cluster='ISMA'
memory=1024
nodes=1
time=50h

orca_pkg_tbz="arcls gsiftp://grid.isma.kharkov.ua/compuchemgridua/common/pkg/orca_2_9_1_linux_x86-64.tbz"
pkg_trans=0

xrsladd=""

function usage {
        echo "Usage: $0 [-h] [-c cluster] [-m memory_MB] [-t time] [-n nodes] inputfile"
        exit
}

#optparse
OPTIND=1
while getopts hc:n:m:t:i: opt; do
        case "$opt" in
                c) cluster=$OPTARG;;
                m) memory=$OPTARG;;
                t) time=$OPTARG;;
                n) nodes=$OPTARG;;
                h) usage;;
                \?) usage;;
        esac
done
shift $(($OPTIND - 1))

input=$1

#check input file
if [ -z $input ]; then
        echo "Input file not defined. Exiting.."
        usage
        exit
elif [ ! -f $input ]; then
        echo "Input file does not exists. Exiting.."
        usage
        exit
fi

#inputfiles
inputFiles="
(\"run.sh\" \"runscript.tmp\")
(\"$input\" \"\")
"

for i in xyz pdb gbw; do
        if [ -f ${input%.*}.$i ]; then
                $inputFiles="$inputFiles
                        (\"${input%.*}.$i\" \"\")"
        fi
done

#cluster
cluster=${cluster,,}
if [ $cluster = 'isma' ]; then
        endpoint='https://grid.isma.kharkov.ua:60443/arex'
        script="#!/bin/bash
source /SOFTWARE/bin/pbs_run_envi.sh
module load mpi/openmpi-1.6
module load chem/orca
cd \$SCRATCH
cp \$PBS_O_WORKDIR/\$1 .

for i in gbw xyz pdb trj; do
        ln -sf \$PBS_O_WORKDIR/\${1%.*}.\$i \${1%.*}.\$i
done

echo \"\" >> \$1
echo \"%pal nprocs \$PBS_NP end\" >> \$1

\$ORCA/orca \$1 > \$PBS_O_WORKDIR/\${1%.*}.out
rm -fr *.tmp* *.ges
cp -vf \${1%.*}.* \$PBS_O_WORKDIR
"
elif [ $cluster = 'icyb' ]; then
        endpoint='uagrid.org.ua'
        xrsladd="$xrsladd
(runTimeEnvironment=\"APPS/CHEM/ORCA-2.9.1\")
(runTimeEnvironment=\"ENV/MPI/OPENMPI-1.4\")"
        script="#!/bin/bash
echo \"\" >> \$1
echo \"%pal nprocs \$SLURM_NPROCS end\" >> \$1
\$ORCA/orca \$1 > \${1%.*}.out
rm -fr *.tmp* *.ges
"
elif [ $cluster = 'imbg' ]; then
        endpoint='https://arc.imbg.org.ua:60000/arex'
        pkg_trans=1
        script="#!/bin/bash
mkdir orca
tar -xjvf orca.tar.bz2 -C orca --strip=1
rm -fr orca.tar.bz2
export PATH=\`pwd\`/orca:\$PATH
orca \$1 > \${1%.*}
rm -fr *.tmp* *.ges
rm -fr orca
"
else
        echo 'Unknown cluster. Using most general run script.'
        endpoint=$cluster
        pkg_trans=1
        script="#!/bin/bash
mkdir orca
tar -xjvf orca.tar.bz2 -C orca --strip=1
rm -fr orca.tar.bz2
export PATH=\`pwd\`/orca:\$PATH
orca \$1 > \${1%.*}
rm -fr *.tmp* *.ges
rm -fr orca
"
fi

echo "$script" > runscript.tmp

if [ $pkg_trans = 1 ]; then
        inputFiles="$inputFiles
(\"orca.tar.bz2\" \"${orca_pkg_tbz}\")
"
fi

#make xrsl
xrsl="&
(executable=\"run.sh\")
(arguments=\"${input}\")
(inputFiles=
$inputFiles
)
(outputFiles=(\"/\" \"\"))
(memory=\"$((memory*$nodes))\")
(wallTime=\"$time\")
(stdout=\"${input%.*}.stdout\")
(stderr=\"${input%.*}.stderr\")
(jobName=\"${input%.*}\")
(count=$nodes)
(countpernode=$nodes)
$xrsladd
"
echo "$xrsl" > jobsub.tmp

#submit job
arcsub -o .arcjobs -c $endpoint -f jobsub.tmp

