# This script create a single tarball for each plate of data. The tarball contains
# - images (typically ~230Gb)
# - illumination functions (tiny)
# - CellProfiler measurements as CSV files (typically ~30Gb)
# - SQLite backend created by ingesting the CSV files (typically ~24Gb)
#
# The tar ball is stored at this location
#
# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>.tar.gz
#
# e.g.
# .
# └── imaging-platform-cold
#     └── imaging_analysis
#         └── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad
#             └── plates
#                 ├── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092655.tar.gz
#                 ├── ...
#                 └── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092789.tar.gz
#
#
# When 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092655.tar.gz is unzipped,
# the directory structure will look like this
# .
# └── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad
#     ├── 2017_12_05_Batch2
#     │   ├── illum
#     │   │   └── BR00092655
#     │   └── images
#     │       └── BR00092655__2017-12-10T12_48_16-Measurement 1
#     └── workspace
#         ├── analysis
#         │   └── 2017_12_05_Batch2
#         │       └── BR00092655
#         └── backend
#             └── 2017_12_05_Batch2
#                 └── BR00092655
# Example usage:
#
# ./aws_backup.sh \
#     --project_name 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad \
#     --batch_id 2017_12_05_Batch2 \
#     --plate_id_full "BR00092655__2017-12-10T12_48_16-Measurement 1" \
#     --plate_id BR00092655
#.    --tmp_dir ~/ebs_tmp


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
        tmp_dir="$2"
        shift
        ;;
        *)
        echo "unknown option"
        ;;
    esac
    shift
done

bucket="${bucket:-imaging-platform}"
cold_bucket="${cold_bucket:-imaging-platform-cold}"
tmp_dir="${tmp_dir:-/tmp}"

s3_prefix=s3://${bucket}/projects/${project_name}
s3_cold_prefix=s3://${cold_bucket}/imaging_analysis/${project_name}/plates
s3_cold_prefix_key=imaging_analysis/${project_name}/plates
plate_archive_tag=${project_name}_${batch_id}_${plate_id}

# report sizes
# s3cmd du "${s3_prefix}/${batch_id}/images/${plate_id_full}"
# s3cmd du "${s3_prefix}/${batch_id}/illum/${plate_id}"
# s3cmd du "${s3_prefix}/workspace/analysis/${batch_id}/${plate_id}"
# s3cmd du "${s3_prefix}/workspace/backend/${batch_id}/${plate_id}"

#https://stackoverflow.com/questions/19622198/what-does-set-e-mean-in-a-bash-script#comment36826142_19622569
# Exit immediately if a command exits with a non-zero status
trap 'exit' ERR

# create staging directory

cd $tmp_dir

mkdir -p ${plate_archive_tag}

cd ${plate_archive_tag}

# create subdirectories

mkdir -p "${project_name}/${batch_id}/images/${plate_id_full}"
mkdir -p "${project_name}/${batch_id}/illum/${plate_id}"
mkdir -p "${project_name}/workspace/analysis/${batch_id}/${plate_id}"
mkdir -p "${project_name}/workspace/backend/${batch_id}/${plate_id}"


cd ${project_name}

# get file listing

file_listing_s3=../../${plate_archive_tag}_file_listing_s3.txt
rm -rf ${file_listing_s3}
touch ${file_listing_s3}

aws s3 ls --recursive "${s3_prefix}/${batch_id}/images/${plate_id_full}"  >> ${file_listing_s3}
aws s3 ls --recursive "${s3_prefix}/${batch_id}/illum/${plate_id}" >> ${file_listing_s3}
aws s3 ls --recursive "${s3_prefix}/workspace/analysis/${batch_id}/${plate_id}" >> ${file_listing_s3}
aws s3 ls --recursive "${s3_prefix}/workspace/backend/${batch_id}/${plate_id}" >> ${file_listing_s3}

cat ${file_listing_s3} | awk -F/ '{ if($NF != "") print }' | cut -c32- | sort > file_listing_s3.bak

mv file_listing_s3.bak ${file_listing_s3}

# download data from S3

aws s3 sync "${s3_prefix}/${batch_id}/images/${plate_id_full}" "${batch_id}/images/${plate_id_full}"
aws s3 sync "${s3_prefix}/${batch_id}/illum/${plate_id}" "${batch_id}/illum/${plate_id}"
aws s3 sync "${s3_prefix}/workspace/analysis/${batch_id}/${plate_id}" "workspace/analysis/${batch_id}/${plate_id}"
aws s3 sync "${s3_prefix}/workspace/backend/${batch_id}/${plate_id}" "workspace/analysis/${batch_id}/${plate_id}"

# TODO Do checks to ensure transfer happened after each of the steps above

cd ../../

# create tarball

tar -czf ${plate_archive_tag}.tar.gz ${plate_archive_tag} || { echo 'my_command failed' ; exit 1; }

file_listing_tar=${plate_archive_tag}_file_listing_tar.txt

tar -tzf ${plate_archive_tag}.tar.gz | awk -F/ '{ if($NF != "") print }' > ${file_listing_tar}

# calculate md5

md5sum ${plate_archive_tag}.tar.gz > ${plate_archive_tag}.md5

# copy to S3
aws s3 cp ${plate_archive_tag}.tar.gz ${s3_cold_prefix}/${plate_archive_tag}.tar.gz

# check whether local ETag and remote Etag match
# https://github.com/antespi/s3md5
etag_local=$(./s3md5 8 ${plate_archive_tag}.tar.gz)

etag_remote=$(aws s3api head-object --bucket ${cold_bucket} --key ${s3_cold_prefix_key}/${plate_archive_tag}.tar.gz |jq '.ETag' -|tr -d '"'|tr -d '\\')

if [ "$etag_local" != "$etag_remote" ]; then
  echo "Remote and local ETags don't match"
  echo "Remote =" $etag_remote
  echo "Local  =" $etag_local
  exit 1
fi

# copy md5 to remote

aws s3 cp ${plate_archive_tag}.md5 ${s3_cold_prefix}/${plate_archive_tag}.md5

# remove local cache of tarball and md5

rm -rf ${plate_archive_tag} ${plate_archive_tag}.tar.gz ${plate_archive_tag}.md5

# remove files from S3

echo Run these commands to delete files on S3

echo aws s3 rm --recursive "${s3_prefix}/${batch_id}/images/${plate_id_full}"
echo aws s3 rm --recursive "${s3_prefix}/${batch_id}/illum/${plate_id}"
echo aws s3 rm --recursive "${s3_prefix}/workspace/analysis/${batch_id}/${plate_id}"
echo aws s3 rm --recursive "${s3_prefix}/workspace/backend/${batch_id}/${plate_id}"


