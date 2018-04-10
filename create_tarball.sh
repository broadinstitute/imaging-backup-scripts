#!/bin/bash

# Script to create zipped tarballs 

# Use long queue if any subdirectory is likely to take longer than 2 hours
# short: 2 hour limit (as of 2016/11).
# long: No time limit (as of 2016/11)

# The file EXCLUDE_LIST should have one line for each subdirectory (absolute path) that 
# should be excluded

function FORMAT_DIR_NAME() {
    echo $1|sed 's,/\+,/,g'|sed 's,/$,,g'
}

function FORMAT_FILE_NAME() {
    echo $1|sed 's, \+,_,g'
}

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
    EXCLUDE_LIST="$2"
    shift
    ;;
    --queue)
    QUEUE="$2"
    shift
    ;;
    --dryrun)
    DRYRUN=YES
    ;;
    *)
    echo "Unknown option"
    ;;
esac
shift
done

SOURCE_DIR="${SOURCE_DIR:-/cbnt/cbimageX/HCS}"

DEST_DIR="${DEST_DIR:-/imaging/cold/cbnt_cbimageX_backup}"

EXCLUDE_LIST="${EXCLUDE_LIST:-UNSPECIFIED}"

QUEUE="${QUEUE:-short}"

DRYRUN="${DRYRUN:-NO}"

DEST_DIR=`FORMAT_DIR_NAME $DEST_DIR/$SUB_DIR`

SOURCE_DIR=`FORMAT_DIR_NAME $SOURCE_DIR/$SUB_DIR`

#dir_list=`find ${SOURCE_DIR} -maxdepth 1 -mindepth 1 -type d`

mkdir -p ${DEST_DIR}

for dir in ${SOURCE_DIR}/*; do
    [ -d "${dir}" ] || continue

    dir=`FORMAT_DIR_NAME "${dir}"`

    echo Handling "${dir}"

    if [ "$EXCLUDE_LIST" != "UNSPECIFIED" ]
    then
        if `grep -Fq "${dir}" $EXCLUDE_LIST`
        then    
            echo Skipping "${dir}"
        
            continue
        fi
    fi
    
    file=`basename "${dir}"`

    file=`FORMAT_FILE_NAME "${file}"`

    QSUB="qsub -q ${QUEUE} -cwd -o ${DEST_DIR}/x${file}.stdout -e ${DEST_DIR}/x${file}.stderr -N x${file} -b y -V"

    TARGZ_FILE=${DEST_DIR}/${file}.tar.gz

    MD5_FILE=${DEST_DIR}/${file}.md5

    CMD_TARGZ="tar cvf - \"${dir}\" | gzip --fast > $TARGZ_FILE"

    CMD_MD5="tar -xOzf  ${DEST_DIR}/${file}.tar.gz | md5sum > $MD5_FILE"

    #CMD_MD5="md5sum ${DEST_DIR}/${file}.tar.gz > $MD5_FILE"

    if [[ -f $TARGZ_FILE ]]; then
	echo $TARGZ_FILE exists. Only creating md5.

	CMD="$CMD_MD5"
    else
	CMD="$CMD_TARGZ; $CMD_MD5"

    fi

    if [ "$DRYRUN" == "YES" ]
    then
        echo $QSUB $CMD

    else
        $QSUB $CMD

    fi
done

