# This script create two tarballs for each plate of data.
# The first tarball (with suffix _images_illum_analysis) contains
# - images (typically ~230Gb)
# - illumination functions (tiny)
# - CellProfiler measurements as CSV files (typically ~30Gb)
#
# The second tarball (with suffix _backend) contains
# - SQLite backend created by ingesting the CSV files (typically ~24Gb)
# - CSV and GCT files created by processing the SQLite backend (tiny)
#
# The tar balls are stored at this location
#
# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_images_illum_analysis.tar.gz
# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_backend.tar.gz
#
# e.g.
# .
# └── imaging-platform-cold
#     └── imaging_analysis
#         └── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad
#             └── plates
#                 ├── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092655_images_illum_analysis.tar.gz
#                 ├── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092655_backend.tar.gz
#                 ├── ...
#                 ├── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092789_images_illum_analysis.tar.gz
#                 └── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092789_backend.tar.gz
#
# The corresponding md5 files are also stored alongside the tar.gz files
#
# When 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092655_*.tar.gz files are unzipped,
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
#     --plate_id BR00092655 \
#.    --tmpdir ~/ebs_tmp


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

# project_name=2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad
# batch_id=2017_12_05_Batch2
# plate_id_full="BR00092655__2017-12-10T12_48_16-Measurement 1"
# plate_id=BR00092655
# tmpdir=~/ebs_tmp


bucket="${bucket:-imaging-platform}"
cold_bucket="${cold_bucket:-imaging-platform-cold}"
tmpdir="${tmpdir:-/tmp}"

s3_prefix=s3://${bucket}/projects/${project_name}
s3_cold_prefix=s3://${cold_bucket}/imaging_analysis/${project_name}/plates
s3_cold_prefix_key=imaging_analysis/${project_name}/plates
plate_archive_tag=${project_name}_${batch_id}_${plate_id}
script_dir=$(pwd)

# report sizes
# s3cmd du "${s3_prefix}/${batch_id}/images/${plate_id_full}"
# s3cmd du "${s3_prefix}/${batch_id}/illum/${plate_id}"
# s3cmd du "${s3_prefix}/workspace/analysis/${batch_id}/${plate_id}"
# s3cmd du "${s3_prefix}/workspace/backend/${batch_id}/${plate_id}"

#https://stackoverflow.com/questions/19622198/what-does-set-e-mean-in-a-bash-script#comment36826142_19622569
# Exit immediately if a command exits with a non-zero status
trap 'exit' ERR

# create staging directory

cd $tmpdir

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

function process_tar_file {

    tar_file=$1

    file_listing_tar=${tar_file}_file_listing_tar.txt

    tar -tzf ${tar_file}.tar.gz | awk -F/ '{ if($NF != "") print }' | sort > ${file_listing_tar}

    # calculate md5

    md5sum ${tar_file}.tar.gz > ${tar_file}.md5

    # copy to S3

    aws s3 cp ${tar_file}.tar.gz ${s3_cold_prefix}/${tar_file}.tar.gz

    # check whether local ETag and remote Etag match
    # https://github.com/antespi/s3md5

    etag_local=$(${script_dir}/s3md5 8 ${tar_file}.tar.gz)

    etag_remote=$(aws s3api head-object --bucket ${cold_bucket} --key ${s3_cold_prefix_key}/${tar_file}.tar.gz |jq '.ETag' -|tr -d '"'|tr -d '\\')

    if [ "$etag_local" != "$etag_remote" ]; then
      echo "Remote and local ETags don't match"
      echo "Remote =" $etag_remote
      echo "Local  =" $etag_local
      exit 1
    fi

    # copy md5 to remote

    aws s3 cp ${tar_file}.md5 ${s3_cold_prefix}/${tar_file}.md5

    # remove local cache of tarball and md5

    rm -rf ${tar_file}.tar.gz ${tar_file}.md5

}

# create tarball for images, illum, analysis folders

tar_file=${plate_archive_tag}_images_illum_analysis

tar -czf ${tar_file}.tar.gz \
  "${plate_archive_tag}/${project_name}/${batch_id}/images/${plate_id_full}" \
  "${plate_archive_tag}/${project_name}/${batch_id}/illum/${plate_id}" \
  "${plate_archive_tag}/${project_name}/workspace/analysis/${batch_id}/${plate_id}"

process_tar_file ${tar_file}

file_listing_tar_1=${tar_file}_file_listing_tar.txt

# create tarball for backend folders

tar_file=${plate_archive_tag}_backend

tar -czf ${tar_file}.tar.gz \
  "${plate_archive_tag}/${project_name}/workspace/backend/${batch_id}/${plate_id}"

process_tar_file ${tar_file}

file_listing_tar_2=${tar_file}_file_listing_tar.txt

# create combined file listings

cat ${file_listing_tar_1} ${file_listing_tar_2} | sort > ${plate_archive_tag}_file_listing_tar.txt

rm ${file_listing_tar_1} ${file_listing_tar_2}

# remove downloaded files

rm -rf ${plate_archive_tag}

# remove files from S3

echo Run these commands to delete files on S3

echo aws s3 rm --recursive "${s3_prefix}/${batch_id}/images/${plate_id_full}"
echo aws s3 rm --recursive "${s3_prefix}/${batch_id}/illum/${plate_id}"
echo aws s3 rm --recursive "${s3_prefix}/workspace/analysis/${batch_id}/${plate_id}"
echo aws s3 rm --recursive "${s3_prefix}/workspace/backend/${batch_id}/${plate_id}"


