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
# The tar balls (and their corresponding md5 files) are stored at this location on the "cold" bucket (e.g. imaging-platform-cold)
#
# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_images_illum_analysis.tar.gz
# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_backend.tar.gz
# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_images_illum_analysis.md5
# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_backend.md5
#
# The file listing of the contents of both tarballs (as they existed on S3) are stored at this location on the "cold" bucket
#
# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_file_listing_untrimmed_s3.txt
# 
# e.g.
# .
# └── imaging-platform-cold
#     └── imaging_analysis
#         └── 2013_Gustafsdottir_PLOSONE
#             └── plates
#                 ├── 2013_Gustafsdottir_PLOSONE_BBBC022_20586_file_listing_untrimmed_s3.txt
#                 ├── 2013_Gustafsdottir_PLOSONE_BBBC022_20586_backend.md5
#                 ├── 2013_Gustafsdottir_PLOSONE_BBBC022_20586_backend.tar.gz
#                 ├── 2013_Gustafsdottir_PLOSONE_BBBC022_20586_images_illum_analysis.md5
#                 ├── 2013_Gustafsdottir_PLOSONE_BBBC022_20586_images_illum_analysis.tar.gz
#                 ├── ...
#                 ├── 2013_Gustafsdottir_PLOSONE_BBBC022_20589_file_listing_untrimmed_s3.txt
#                 ├── 2013_Gustafsdottir_PLOSONE_BBBC022_20589_backend.md5
#                 ├── 2013_Gustafsdottir_PLOSONE_BBBC022_20589_backend.tar.gz
#                 ├── 2013_Gustafsdottir_PLOSONE_BBBC022_20589_images_illum_analysis.md5
#                 └── 2013_Gustafsdottir_PLOSONE_BBBC022_20589_images_illum_analysis.tar.gz
#
# Additionally, the following 3 files are stored in the "live" bucket (e.g. imaging-platform)
# 
# s3://imaging-platform/projects/<PROJECT_NAME>/workspace/backup/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_file_listing_s3.txt
# s3://imaging-platform/projects/<PROJECT_NAME>/workspace/backup/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_file_listing_tar.txt
# s3://imaging-platform/projects/<PROJECT_NAME>/workspace/backup/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>_delete_s3.sh
#
# The first two are file listings of the archives as they exist on S3 and in the tarball respectively. They have been
# formatted so that they can be compared via diff or by their ETag. 
#
# The third file has a list of awscli commands to delete the files that have been archived by this process.
# 
# When 2013_Gustafsdottir_PLOSONE_BBBC022_20586_*.tar.gz files are unzipped like this,
#
# tar xzf 2013_Gustafsdottir_PLOSONE_BBBC022_20586_images_illum_analysis.tar.gz --strip-components=1
# tar xzf 2013_Gustafsdottir_PLOSONE_BBBC022_20586_backend.tar.gz --strip-components=1
#
# the directory structure will look like this
# .
# └── 2013_Gustafsdottir_PLOSONE
#     ├── BBBC022
#     │   ├── illum
#     │   │   └── 20586
#     │   └── images
#     │       └── 20586
#     └── workspace
#         ├── analysis
#         │   └── BBBC022
#         │       └── 20586
#         └── backend
#             └── BBBC022
#                 └── 20586
# Example usage:
#
# ./aws_backup.sh \
#     --project_name 2013_Gustafsdottir_PLOSONE \
#     --batch_id BBBC022 \
#     --plate_id_full "20586" \
#     --plate_id 20586 \
#     --tmpdir ~/ebs_tmp
# 
# Note: In the example above, `plate_id` and `plate_id_full` are the same but this is not always true.
# E.g. The `plate_id` for "BR00092655__2017-12-10T12_48_16-Measurement 1" is "BR00092655"


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

s3_prefix=s3://${bucket}/projects/${project_name}
s3_backup_prefix=s3://${bucket}/projects/${project_name}/workspace/backup
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

file_listing_untrimmed_s3=../../${plate_archive_tag}_file_listing_untrimmed_s3.txt

rm -rf ${file_listing_untrimmed_s3}

touch ${file_listing_untrimmed_s3}

# aws s3 ls return 1 if file / prefix doesn't exist
trap '' ERR

aws s3 ls --recursive "${s3_prefix}/${batch_id}/images/${plate_id_full}"  >> ${file_listing_untrimmed_s3}
aws s3 ls --recursive "${s3_prefix}/${batch_id}/illum/${plate_id}" >> ${file_listing_untrimmed_s3}
aws s3 ls --recursive "${s3_prefix}/workspace/analysis/${batch_id}/${plate_id}" >> ${file_listing_untrimmed_s3}
aws s3 ls --recursive "${s3_prefix}/workspace/backend/${batch_id}/${plate_id}" >> ${file_listing_untrimmed_s3}

# reset trap to exit
trap 'exit' ERR

# make list of files on S3
cat ${file_listing_untrimmed_s3} | \
  awk -F/ '{ if($NF != "") print }' | \
  tr -s " " | \
  cut -d" " -f3,4 | \
  awk '{ print $2 "\t" $1}' | \
  sed s,projects/,,g | \
  sort > \
  ${file_listing_s3}

# download data from S3

aws s3 sync "${s3_prefix}/${batch_id}/images/${plate_id_full}" "${batch_id}/images/${plate_id_full}"
aws s3 sync "${s3_prefix}/${batch_id}/illum/${plate_id}" "${batch_id}/illum/${plate_id}"
aws s3 sync "${s3_prefix}/workspace/analysis/${batch_id}/${plate_id}" "workspace/analysis/${batch_id}/${plate_id}"
aws s3 sync "${s3_prefix}/workspace/backend/${batch_id}/${plate_id}" "workspace/backend/${batch_id}/${plate_id}"

# TODO Do checks to ensure transfer happened after each of the steps above

cd ../../

function process_tar_file {

    tar_file=$1

    file_listing_tar=${tar_file}_file_listing_tar.txt

    tar -tvzf ${tar_file}.tar.gz | \
      awk -F/ '{ if($NF != "") print }' | \
      tr -s " " | \
      cut -f3,6 -d" " | \
      awk '{ print $2 "\t" $1 }' | \
      sed s,${plate_archive_tag}/,,g | \
      sort > \
      ${file_listing_tar}

    # calculate md5

    md5sum ${tar_file}.tar.gz > ${tar_file}.md5

    # copy to S3

    aws s3 cp ${tar_file}.tar.gz ${s3_cold_prefix}/${tar_file}.tar.gz

    # check whether local ETag and remote Etag match
    # https://github.com/antespi/s3md5

    size=$(du -b ${tar_file}.tar.gz | cut -f1)

    # if size is less than or equal to 8Mb, then ETag is same as MD5
    if [ ${size} -le 8388608 ] ; then
        etag_local=$(cat ${tar_file}.md5 | cut -d" " -f1)
    else
        etag_local=$(${script_dir}/s3md5 8 ${tar_file}.tar.gz)
    fi

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

aws s3 cp ${plate_archive_tag}_file_listing_tar.txt ${s3_backup_prefix}/${plate_archive_tag}_file_listing_tar.txt

rm ${plate_archive_tag}_file_listing_tar.txt

aws s3 cp ${plate_archive_tag}_file_listing_s3.txt ${s3_backup_prefix}/${plate_archive_tag}_file_listing_s3.txt

rm ${plate_archive_tag}_file_listing_s3.txt

aws s3 cp ${plate_archive_tag}_file_listing_untrimmed_s3.txt ${s3_cold_prefix}/${plate_archive_tag}_file_listing_untrimmed_s3.txt

rm ${plate_archive_tag}_file_listing_untrimmed_s3.txt

# remove downloaded files

rm -rf ${plate_archive_tag}

# create script to delete files from S3 (but don't actually delete them)

delete_s3=${plate_archive_tag}_delete_s3.sh

rm -rf ${delete_s3}

touch ${delete_s3}

echo aws s3 rm --recursive "\"${s3_prefix}/${batch_id}/images/${plate_id_full}\"" >> ${delete_s3}
echo aws s3 rm --recursive "\"${s3_prefix}/${batch_id}/illum/${plate_id}\"" >> ${delete_s3}
echo aws s3 rm --recursive "\"${s3_prefix}/workspace/analysis/${batch_id}/${plate_id}\"" >> ${delete_s3}
echo aws s3 rm --recursive "\"${s3_prefix}/workspace/backend/${batch_id}/${plate_id}\"" >> ${delete_s3}

aws s3 cp ${delete_s3} ${s3_backup_prefix}/${delete_s3}

rm ${delete_s3}


