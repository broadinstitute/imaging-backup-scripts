#!/bin/bash

# Script to create zipped tarballs 

# Use long queue if any SUB_DIRectory is likely to take longer than 2 hours
# short: 2 hour limit (as of 2016/11).
# long: No time limit (as of 2016/11)

# EXCLUDE_FILE should have one line for each subdirectory (absolute path) that 
# should be excluded


programname=$0

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --source_dir)
    SOURCE_DIR="$2"
    shift
    ;;
    --dest_dir)
    DEST_DIR="$2"
    shift
    ;;
    --sub_dir)
    SUB_DIR="$2"
    shift
    ;;
    --exclude)
    EXCLUDE_FILE="$2"
    shift
    ;;
    --queue)
    QUEUE="$2"
    shift
    ;;
    *)
    echo "Unknown option"
    ;;
esac
shift
done

SOURCE_DIR="${SOURCE_DIR:-/cbnt/cbimageX/HCS}"

DEST_DIR="${DEST_DIR:-/imaging/cold/cbnt_cbimageX_backup}"

SUB_DIR="${SUB_DIR:-xiaoyunwu}"

EXCLUDE_FILE="${EXCLUDE_FILE:-UNSPECIFIED}"

QUEUE="${QUEUE:-short}"

dir_list=`find ${SOURCE_DIR}/$SUB_DIR -maxdepth 1 -mindepth 1 -type d`

mkdir -p ${DEST_DIR}/${SUB_DIR}

for dir in $dir_list;
do
	if [ "$EXCLUDE_FILE" != "UNSPECIFIED" ]
	then
	    if `grep -Fxq $dir $EXCLUDE_FILE`
    	    then    
		echo Skipping $dir
		
		continue
	    fi
	fi
	
	file=`basename $dir`

	qsub -q ${QUEUE} -cwd -o ${DEST_DIR}/${SUB_DIR}/x${file}.log -N x${file} -j y -b y -V "tar cvf - ${dir} | gzip --fast > ${DEST_DIR}/${SUB_DIR}/${file}.tar.gz"
done

