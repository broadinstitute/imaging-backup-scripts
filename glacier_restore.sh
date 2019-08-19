# Restore data from Glacier

# Assumes that the tarballs are created using aws_backup.sh
#
# Usage example:
#
# Restore only images of a plate
#
#      ./glacier_restore.sh --project_name 2013_Gustafsdottir_PLOSONE --batch_id BBBC022 --plate_id 20586 --get_images
#
# Restore only backend of a plate
#
#      ./glacier_restore.sh --project_name 2013_Gustafsdottir_PLOSONE --batch_id BBBC022 --plate_id 20586 --get_backend
#
# Restore both, images and backend, of a plate
#
#      ./glacier_restore.sh --project_name 2013_Gustafsdottir_PLOSONE --batch_id BBBC022 --plate_id 20586 --get_backend --get_images
#
# Only check status, but don't restore, images and backend of a plate
#
#      ./glacier_restore.sh --project_name 2013_Gustafsdottir_PLOSONE --batch_id BBBC022 --plate_id 20586 --get_backend --get_images --check_status
#
#      If a request has been made, you'll receive a response similar to the following if the restore is still in progress
#
#      > "Restore": "ongoing-request=\"true\""
#      > "StorageClass": "GLACIER"
#
#      After the restore is complete, the response is similar to the following
#
#      "Restore": "ongoing-request=\"false\", expiry-date=\"Sun, 13 Aug 2017 00:00:00 GMT\""
#
#      If no request has been made, "Restore" key will be absent
#
# Check status of restoring backend for a list of plates
#
#      echo "20586 20589" | tr " " "\n" > list_of_plates.txt
#
#      parallel -a list_of_plates.txt ./glacier_restore.sh --project_name 2013_Gustafsdottir_PLOSONE --batch_id BBBC022 --plate_id {1} --get_backend --check_status
#
# If there are several plates, it is easier to save output in separate files, one per plate
#
#      parallel --results restore -a list_of_plates.txt ./glacier_restore.sh --project_name 2013_Gustafsdottir_PLOSONE --batch_id BBBC022 --plate_id {1} --get_backend --check_status
#
# This will produce a list of files that look like this. Inspect the stdout of each plate to view status
#
#      $ tree restore
#      restore/
#      └── 1
#          ├── 20586
#          │   ├── seq
#          │   ├── stderr
#          │   └── stdout
#          └── 20589
#              ├── seq
#              ├── stderr
#              └── stdout



progname=`basename $0`

while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        --project_name)
        project_name="$2"
        shift
        ;;
        --batch_id)
        batch_id="$2"
        shift
        ;;
        --plate_id)
        plate_id="$2"
        shift
        ;;
        --bucket)
        bucket="$2"
        shift
        ;;
        --cold_bucket)
        cold_bucket="$2"
        shift
        ;;
        --get_images)
        get_images=YES
        ;;
        --get_backend)
        get_backend=YES
        ;;
        --check_status)
        check_status=YES
        ;;
        -t|--tmpdir)
        tmpdir="$2"
        shift
        ;;
        *)
        echo "unknown option"
        ;;
    esac
    shift
done

cold_bucket="${cold_bucket:-imaging-platform-cold}"
get_images="${get_images:-NO}"
get_backend="${get_backend:-NO}"
check_status="${check_status:-NO}"

tarball_1_prefix=imaging_analysis/${project_name}/plates/${project_name}_${batch_id}_${plate_id}_images_illum_analysis
tarball_2_prefix=imaging_analysis/${project_name}/plates/${project_name}_${batch_id}_${plate_id}_backend
tarball_1=${tarball_1_prefix}.tar.gz
tarball_2=${tarball_2_prefix}.tar.gz
tarball_1_md5=${tarball_1_prefix}.md5
tarball_2_md5=${tarball_2_prefix}.md5

if [[ ${get_images} == "YES" ]];then

    echo "Get images ..."

    if [[ ${check_status} == "NO" ]];then

        aws s3api restore-object --bucket ${cold_bucket} --key ${tarball_1_md5} --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Standard"}}'

        aws s3api restore-object --bucket ${cold_bucket} --key ${tarball_1} --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Standard"}}'

    fi

    aws s3api head-object --bucket ${cold_bucket} --key ${tarball_1_md5}

    aws s3api head-object --bucket ${cold_bucket} --key ${tarball_1}
    
    echo Download:s3://${cold_bucket}/{tarball_1}

fi


if [[ ${get_backend} == "YES" ]];then

    echo "Get backend ..."

    if [[ ${check_status} == "NO" ]];then

        aws s3api restore-object --bucket ${cold_bucket} --key ${tarball_2_md5} --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Standard"}}'

        aws s3api restore-object --bucket ${cold_bucket} --key ${tarball_2} --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Standard"}}'
    fi

    aws s3api head-object --bucket ${cold_bucket} --key ${tarball_2_md5}

    aws s3api head-object --bucket ${cold_bucket} --key ${tarball_2}

    echo Download:s3://${cold_bucket}/{tarball_2}

fi


