#!/bin/bash

###########################################################################################################
# Setup environments
###########################################################################################################
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/code/rooutil/thisrooutil.sh
export SCRAM_ARCH=slc7_amd64_gcc900
export CMSSW_VERSION=CMSSW_11_2_0_pre5
source /cvmfs/cms.cern.ch/cmsset_default.sh
cd /cvmfs/cms.cern.ch/$SCRAM_ARCH/cms/cmssw/$CMSSW_VERSION/src
eval `scramv1 runtime -sh`
cd - > /dev/null
echo "Setup following ROOT.  Make sure it's slc7 variant. Otherwise the looper won't compile."
which root

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$DIR
export PATH=$PATH:$DIR/bin
export PATH=$PATH:$DIR/efficiency/bin
export TRACKLOOPERDIR=$DIR

###########################################################################################################
# Validation scripts
###########################################################################################################

# List of benchmark efficiencies are set as an environment variable
export LATEST_CPU_BENCHMARK_EFF_MUONGUN="/nfs-7/userdata/phchang/segmentlinking/benchmarks/7d8f188/eff_plots__CPU_7d8f188_muonGun/efficiencies.root"
export LATEST_CPU_BENCHMARK_EFF_PU200="/nfs-7/userdata/phchang/segmentlinking/benchmarks/3bb6b6b/PU200/eff_plots__CPU_3bb6b6b_PU200/efficiencies.root"

run_gpu()
{
    version=$1
    sample=$2
    nevents=$3
    shift
    shift
    shift
    # GPU unified
    sdl_make_tracklooper -m $*
    sdl -n ${NEVENTS} -o ${OUTDIR}/gpu_${version}.root -i ${sample}
    sdl_plot_efficiency -i ${OUTDIR}/gpu_${version}.root -g ${PDGID} -p 4 -f
}
export -f run_gpu

validate_efficiency_usage() {
    echo "ERROR - Usage:"
    echo
    echo "      sh $(basename $0) SAMPLETYPE [SPECIFICGPUVERISON] [NEVENTS]"
    echo
    echo "Arguments:"
    echo "   SAMPLETYPE                          muonGun, PU200, or pionGun"
    echo "   SPECIFICGPUVERSION (optional)       unified, unified_cache, ... , explicit, explicit_newgrid, ... , etc."
    echo "   NEVENTS            (optional)       200, 10000, -1, etc."
    echo ""
    exit
}


# Function to validate segment linking
sdl_validate_efficiency() {

    if [ -z ${1} ]; then validate_efficiency_usage; fi

    # Parsing command-line opts
    while getopts ":h" OPTION; do
      case $OPTION in
        h) usage;;
        :) usage;;
      esac
    done

    # Shift away the parsed options
    shift $(($OPTIND - 1))

    SAMPLE=${1}
    if [[ ${SAMPLE} == *"pionGun"* ]]; then
        PDGID=211
    elif [[ ${SAMPLE} == *"muonGun"* ]]; then
        PDGID=13
    elif [[ ${SAMPLE} == *"PU200"* ]]; then
        PDGID=0
    fi

    SPECIFICGPUVERSION=${2}

    if [ -z ${3} ]; then
        NEVENTS=200 # If no number of events provided, validate on first 200 events
        if [[ ${SAMPLE} == *"PU200"* ]]; then
            NEVENTS=30 # If PU200 then run 30 events
        fi
    else
        NEVENTS=${3} # If provided set the NEVENTS
    fi

    pushd ${TRACKLOOPERDIR}
    GITHASH=$(git rev-parse --short HEAD)
    DIRTY=""
    DIFF=$(git diff)
    if [ -z "${DIFF}" ]; then
        DIRTY=""
    else
        DIRTY="DIRTY"
    fi
    popd
    GITHASH=${GITHASH}${DIRTY}

    OUTDIR=outputs_${GITHASH}_${SAMPLE}

    # Delete old run
    rm -rf ${OUTDIR}
    mkdir -p ${OUTDIR}

    # Run different GPU configurations
    if [ -z ${SPECIFICGPUVERSION} ] || [[ "${SPECIFICGPUVERSION}" == "unified" ]]; then
        run_gpu unified ${SAMPLE} ${NEVENTS}
    fi
    if [ -z ${SPECIFICGPUVERSION} ] || [[ "${SPECIFICGPUVERSION}" == "unified_cache" ]]; then
        run_gpu unified_cache ${SAMPLE} ${NEVENTS} -c
    fi
    if [ -z ${SPECIFICGPUVERSION} ] || [[ "${SPECIFICGPUVERSION}" == "unified_cache_newgrid" ]]; then
        run_gpu unified_cache_newgrid ${SAMPLE} ${NEVENTS} -c -g
    fi
    if [ -z ${SPECIFICGPUVERSION} ] || [[ "${SPECIFICGPUVERSION}" == "unified_newgrid" ]]; then
        run_gpu unified_newgrid ${SAMPLE} ${NEVENTS} -g
    fi
    if [ -z ${SPECIFICGPUVERSION} ] || [[ "${SPECIFICGPUVERSION}" == "explicit" ]]; then
        run_gpu explicit ${SAMPLE} ${NEVENTS} -x
    fi
    if [ -z ${SPECIFICGPUVERSION} ] || [[ "${SPECIFICGPUVERSION}" == "explicit_cache" ]]; then
        # run_gpu explicit_cache ${SAMPLE} -x -c # Does not run on phi3
        :
    fi
    if [ -z ${SPECIFICGPUVERSION} ] || [[ "${SPECIFICGPUVERSION}" == "explicit_cache_newgrid" ]]; then
        # run_gpu explicit_cache_newgrid ${SAMPLE} -x -c -g # Does not run on phi3
        :
    fi
    if [ -z ${SPECIFICGPUVERSION} ] || [[ "${SPECIFICGPUVERSION}" == "explicit_newgrid" ]]; then
        run_gpu explicit_newgrid ${SAMPLE} ${NEVENTS} -x -g
    fi

    sdl_compare_efficiencies -i ${SAMPLE} -t ${GITHASH} -f

}
export -f sdl_validate_efficiency

#eof
