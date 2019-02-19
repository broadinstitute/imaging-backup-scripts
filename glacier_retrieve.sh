# Retrieve data from Glacier

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
        --plate_id_full)
        plate_id_full="$2"
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

# project_name=2013_Gustafsdottir_PLOSONE
# batch_id=BBBC022
# plate_id_full="20586"
# plate_id=20586
# tmpdir=~/ebs_tmp

bucket="${bucket:-imaging-platform}"
cold_bucket="${cold_bucket:-imaging-platform-cold}"
tmpdir="${tmpdir:-/tmp}"

# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_images_illum_analysis.tar.gz

BUCKET=imaging-platform-cold
PROJECT_NAME=2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad
BATCH_ID=2016_04_01_a549_48hr_batch1
PLATE_ID=SQ00014812

tarball_1_prefix=imaging_analysis/${PROJECT_NAME}/plates/${PROJECT_NAME}_${BATCH_ID}_${PLATE_ID}_images_illum_analysis

tarball_2_prefix=imaging_analysis/${PROJECT_NAME}/plates/${PROJECT_NAME}_${BATCH_ID}_${PLATE_ID}_backend

tarball_1=${tarball_1_prefix}.tar.gz
tarball_2=${tarball_2_prefix}.tar.gz
tarball_1_md5=${tarball_1_prefix}.md5
tarball_2_md5=${tarball_2_prefix}.md5

aws s3 ls s3://${BUCKET}/${tarball_1}
aws s3 ls s3://${BUCKET}/${tarball_2}
aws s3 ls s3://${BUCKET}/${tarball_1_md5}
aws s3 ls s3://${BUCKET}/${tarball_2_md5}


aws s3api restore-object --bucket ${BUCKET} --key ${tarball_1_md5} --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Standard"}}'

aws s3api head-object --bucket ${BUCKET} --key ${tarball_1_md5}
