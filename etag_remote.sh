#!/bin/bash
set -euo pipefail
if [ $# -ne 1 ]; then
    echo "Usage: $0 file";
    exit 0;
fi
file=$1

bucket=imaging-platform-cold
prefix=imaging_docs

etag_remote=$(aws s3api head-object --bucket ${bucket} --key ${prefix}/${file} |jq '.ETag' -|tr -d '"'|tr -d '\\')

echo ${etag_remote}
