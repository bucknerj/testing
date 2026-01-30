#!/bin/bash

# commas need careful handling because sbatch --export is a comma delimited list
declare -A configs=(
  [gamus]='--with-gamus'
  [gpu]='-u --with-blade --with-fftdock --with-repdstr'
  [lite]='--lite -g'
  [ljpme]='--with-ljpme'
  [misc2]="--without-domdec --with-g09 -a 'DISTENE,MTS'"
  [misc]="-a 'ABPO,ADUMBRXNCOR,ROLLRXNCOR,CORSOL,CVELOCI,PINS,ENSEMBLE,SAMC,MCMA,GSBP,PIPF,POLAR,PNM,RISM,CONSPH,RUSH,TMD,DIMS,MSCALE,EDS'"
  [mndo97]='--with-mndo97'
  [sccdftb]='--with-sccdftb'
  [squantm]='--with-squantm'
  [stringm]='--with-stringm'
  [tamd]='--without-mpi -a TAMD'
)

if [[ $# -eq 1 ]]; then
  echo "build $1 selected"
  name=$1
  config="${configs[$name]}"
  sbatch --job-name="$name-build" \
         --export=ALL,build_name="$name",configure_arguments="$config" \
         -o "install-$name/%x-%j.out" \
         build.bash
  exit 0
fi

for name in "${!configs[@]}"; do
  config="${configs[$name]}"
  sbatch --job-name="$name.build" \
         --export=ALL,build_name="$name",configure_arguments="$config" \
         -o "install-$name/%x-%j.out" \
         build.bash
done
