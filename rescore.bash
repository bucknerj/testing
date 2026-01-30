#!/bin/bash

test_dir=$1
old_dir=$2
new_dir=$3

read -rd '' seddir << EOF
/SET OMP_NUM_THREADS=2/d
/CUDA device/d
/alloc/d
/atsx/d
/shmem: mmap:/d
/create_and_attach/d
/Revision unknown/d
/Git commit/d
/CMA: no RDMA devices found/d
/Maximum number of ATOMS:/d
/Current HEAP/d
/Created on/d
/Current operating system/d
/CREATED BY USER/d
/ELAPSED TIME:/d
/CPU TIME:/d
/CPU TIME=/d
/ OPNLGU> /d
/ Eigenvalue=/d
/ energ=/d
/ rnew=/d
/ Improved step=/d
/! input data directory/d
/! scratch directory/d
/RDCMND substituted parameter/d
/TITLE> */d
/CHARMM>/d
/CHARMM.* Version /d
/Parameter #/d
/Processing passed argument /d
/Parameter: /d
/ Attempting to open/d
/ Other: /d
/ TIME= /d
s/ \\./0\\./g
s/ -\\./-0\\./g
s/ +\\./+0\\./g
/ALLHP: /d
/ALLHP> /d
/FREHP: /d
/FREHP> /d
/PRINHP> /d
/SEEDS>/d
/RANDOM NUM/d
s/  *ISEED =  *1$//
/MAKINB.*RESIZING/d
/Total heap storage needed /d
/^coor. length /d
/FCTINI> Surface tension coeff/d
/SA modulation: /d
/random clcg/d
/CLCG Random/d
/reference distance/d
/allocated space for coor/d
/Number of lone-pairs/d
/CGONNB = .* CGOFNB =/d
/EANGLC: QANGTYPE =/d
/EANGLE> FORCE: ANGLE NOT FLAT/d
/PARRDR> ALL ANGLES HAVE POSITIVE MINIMA/d
/EANGLE> Using CHARMM angle function/d
/E[A-Z]*C: Using routine E[A-Z]*F/d
/TORQ> No external forces defined/d
/QM groups found: * 0/d
/----------/d
/Git commit ID/d
/SVN revision/d
/operation not performed/d
/VALB CPUC/d
/ EEMA$/d
/^ *$/d
/Splitting recip cores into (y by z):/d
/Using FFTW/d
/Using MKL/d
/Using Pub FFT/d
/Using Column FFT/d
/NUMBER OF ENERGY EVALUATIONS/d
/TOTAL NUMBER OF CYCLES/d
/There are no .*straints/d
/emapwrite> /d
/OpenMM initiated with/d
/In OpenMM plugin directory/d
/libOpenMM/d
/libOmmXml/d
/Reaction field dielectric/d
/COLLCT_FSTSHK/d
/FSSHKINI/d
/VCLOSE:/d
/Parallel load balance/,\$d
/New timer profile/,\$d
/NBLIST_BUILDER Allocating grid/d
EOF

if [ ! -d "scratch" ]; then
    echo "FATAL ERROR"
    echo "please create a directory named $PWD/scratch"
    exit 1
fi

echo "$seddir" > scratch/seddir

for out_file in $(ls $new_dir/*.out); do
    out_base=$(basename -- "$out_file")
    test_name=${out_base%.*}

    test_suite=$(find "$test_dir" -name "$test_name.inp" | \
		     sed -rn 's/.*c(.*)test.*/\1/p')

    echo " "
    echo "<** ${test_suite} : $test_name **>" `date`

    compare=1
    grep " TERMINATION" $out_file &> /dev/null
    status=$?
    if [ $status -ne 0 ]; then
	echo "***** NO TERMINATION  *****"
	compare=0
    fi

    grep "ABNORMAL TERMINATION" $out_file &> /dev/null
    status=$?
    if [ $status -eq 0 ]; then
	echo "***** ABNORMAL TERMINATION *****"
	compare=0
    fi

    grep -i "TESTCASE RESULT: SKIP|test not performed" $out_file | grep -v "!" &> /dev/null
    status=$?
    if [ $status -eq 0 ]; then
	echo "***** SKIPPED *****"
	compare=0
    fi

    grep -i "TESTCASE RESULT: FAIL" $out_file &> /dev/null
    status=$?
    if [ $status -eq 0 ]; then
	echo "***** FAILED *****"
	compare=0
    fi

    if [ ! -f "$old_dir/$test_name.out" ]; then
	echo "***** NEW *****"
	compare=0
    fi

    grep -i "TESTCASE RESULT: PASS" $out_file &> /dev/null
    status=$?
    if [ $status -eq 0 ]; then
	compare=0
    fi

    if [ $compare -eq 1 ]; then
	sed -f scratch/seddir "$old_dir/$test_name.out" > scratch/old.out
	sed -f scratch/seddir "$out_file" > scratch/new.out
	diff scratch/old.out scratch/new.out
    fi
done
