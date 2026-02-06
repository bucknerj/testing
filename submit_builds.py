#!/usr/bin/env python3

import sys
import subprocess
from pathlib import Path

# Configuration dictionary (matching your Bash associative array)
configs = {
    'gamus': '--with-gamus',
    'gpu': '-u --with-blade --with-fftdock --with-repdstr',
    'gpu2': '-u --with-blade --with-fftdock --with-repdstr',
    'lite': '--lite -g',
    'ljpme': '--with-ljpme',
    'misc2': "--without-domdec --with-g09 -a 'DISTENE,MTS'",
    'misc': "-a 'ABPO,ADUMBRXNCOR,ROLLRXNCOR,CORSOL,CVELOCI,PINS,ENSEMBLE,SAMC,MCMA,GSBP,PIPF,POLAR,PNM,RISM,CONSPH,RUSH,TMD,DIMS,MSCALE,EDS'",
    'mndo97': '--with-mndo97',
    'sccdftb': '--with-sccdftb',
    'squantm': '--with-squantm',
    'stringm': '--with-stringm',
    'tamd': '--without-mpi -a TAMD',
}

def submit_build(name):
    """Submit a build job to Slurm for the given configuration."""
    config = configs[name]
    outdir = Path(f"install-{name}")
    outdir.mkdir(parents=True, exist_ok=True)
    output_file = outdir / "%x-%j.out"

    sbatch_cmd = [
        "sbatch",
        f"--job-name={name}-build",
        f"--export=build_name={name},configure_arguments={config}",
        "-o", str(output_file),
        "build.bash"
    ]

    print(f"Submitting build job for '{name}' with config: {config}")
    subprocess.run(sbatch_cmd, check=True)

def main():
    # If a single argument is given, submit only that build
    if len(sys.argv) == 2:
        name = sys.argv[1]
        if name not in configs:
            print(f"Unknown build name: {name}")
            sys.exit(1)
        print(f"Build {name} selected")
        submit_build(name)
        sys.exit(0)

    # Otherwise, submit all builds
    for name in configs:
        submit_build(name)

if __name__ == "__main__":
    main()
