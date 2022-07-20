#!/bin/bash
# from https://gist.github.com/emersonf/7413337?permalink_comment_id=4239419#gistcomment-4239419
set -euo pipefail
if [ $# -ne 2 ]; then
    echo "Usage: $0 file partSizeInMb";
    exit 0;
fi
file=$1
if [ ! -f "$file" ]; then
    echo "Error: $file not found." 
    exit 1;
fi
partSizeInMb=$2
partSizeInB=$((partSizeInMb * 1024 * 1024))
fileSizeInB=$(du -b "$file" | cut -f 1)
parts=$((fileSizeInB / partSizeInB))
if [[ $((fileSizeInB % partSizeInB)) -gt 0 ]]; then
    parts=$((parts + 1));
fi
checksumFile=$(mktemp -t s3md5.XXXXXXXXXXXXX)
for (( part=0; part<$parts; part++ ))
do
    skip=$((partSizeInMb * part))
    $(dd bs=1M count=$partSizeInMb skip=$skip if="$file" 2> /dev/null | md5sum >> $checksumFile)
done
etag=$(echo $(xxd -r -p $checksumFile | md5sum)-$parts | sed 's/ --/-/')
echo -e "${1}\t${etag}"
rm $checksumFile
