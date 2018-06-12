# Backing up projects on S3 using aws_backup.sh

The script `aws_backup.sh` expects the project directories to have a very specific structure. 
See the script documentation for details. 

`aws_backup.sh` creates one set of tarballs for each plate of data. This makes retrieval easy.

Start a large  ec2 instance (e.g. `m4.16xlarge`) because you will need plenty of memory, high network bandwidth. 

Then attach a large EBS volume to the instance. As of June 2018, each 384-well plate of Cell Painting data acquired at the Broad produces about 300Gb of data, of which 230Gb are images. During the archiving process, both, the uncompressed files as well as the tarballs (~250Gb) will reside on the EBS volume. You will need n x 550Gb of disk space on the EBS volume. The maximum allowable size is 16Tb, so you can comfortably process 27 plates of data in parallel given this limit. 

To mount the EBS volume (after attaching via the AWS interface), do the following
```sh
# check the name of the disk
lsblk

#> NAME    MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
#> xvda    202:0    0     8G  0 disk
#> └─xvda1 202:1    0     8G  0 part /
#> xvdf    202:80   0   100G  0 disk

# check if it has a file system
sudo file -s /dev/xvdf
# ...likely not, in which case you get:
#> /dev/xvdf: data

# if no file system, then create it
sudo mkfs -t ext4 /dev/xvdf

# mount it
sudo mount /dev/xvdf /home/ubuntu/ebs_tmp/

# change perm
sudo chmod 777 ~/ebs_tmp/
```

Next define variables and download the scripts.

```
PROJECT_NAME=2013_Gustafsdottir_PLOSONE
BATCH_ID=BBBC022

mkdir ~/ebs_tmp

cd ~/work/software

git clone git@github.com:broadinstitute/imaging-backup-scripts.git

cd imaging-backup-scripts

```

Create a list of plates to be archived. `plate_id_full` is the full name of the plate, as it exists in the `images/` directory. `plate_id` is the shortened name that is used throughout the rest of the profiling workflow. In this example, `plate_id_full` is the same as `plate_id` but that isn't always the case.

```
echo "plate_id,plate_id_full" > plates.csv

echo 20585 20586 20589 20590 20591 20592 20593 20594 20595 20596 20607 20608 20625 20626 20630 20633 20639 20640 20641 20646 | \
  tr " " "\n" |
  awk '{ print $1 "," $1 }' \
  >> plates.csv
```

Create a directory to log results

```
LOGDIR=log/${PROJECT_NAME}_${BATCH_ID}
mkdir -p $LOGDIR
```


Set `MAXPROCS` to be the maximum number of plates to be processed in parallel. This depends on how much space you have allocated and the capacity of the instance.

```
MAXPROCS=10
```

Run the archiving script across all the plates. 

```
parallel \
  -a plates.csv \
  --header ".*\n" \
  -C "," \
  --keep-order \
  --max-procs ${MAXPROCS} \
  --eta \
  --joblog ${LOGDIR}/backup.log \
  --results ${LOGDIR}/backup \
  --files \
  ./aws_backup.sh \
    --project_name "${PROJECT_NAME}" \
    --batch_id "${BATCH_ID}" \
    --plate_id "{1}" \
    --plate_id_full "{2}" \
    --tmpdir ~/ebs_tmp
```

Check whether archiving process succeeded. First, define functions to check whether etags of file listings match. 

```
function etag { 
	aws s3api head-object --bucket imaging-platform --key $1 |jq '.ETag' -|tr -d '"'|tr -d '\\' 
}


function check_plate {
	PLATE_ID=$1

	s3_files=projects/${PROJECT_NAME}/workspace/backup/${PROJECT_NAME}_${BATCH_ID}_${PLATE_ID}_file_listing_s3.txt
	tar_files=projects/${PROJECT_NAME}/workspace/backup/${PROJECT_NAME}_${BATCH_ID}_${PLATE_ID}_file_listing_tar.txt

	if [[ $(etag ${s3_files}) != $(etag ${tar_files}) ]] ; then echo File listings do not match; exit 1; fi
}
```

Now check whether the file listings of the uploaded tarball and that of the S3 directory are identical

```
# export functions and variables so that they are visible inside parallel
export -f etag
export -f check_plate
export PROJECT_NAME
export BATCH_ID

parallel \
  -a plates.csv \
  --header ".*\n" \
  -C "," \
  --keep-order \
  --eta \
  --joblog ${LOGDIR}/backup_check.log \
  --results ${LOGDIR}/backup_check \
  --files \
  check_plate {1}
```

Check whether there are any errors. If they are errors, you'd need to probe further to figure out what's different. Doing a diff on the file listings is a start.

```
find ${LOGDIR}/backup_check -name stderr -exec cat {} \;

cat find ${LOGDIR}/backup_check.log
```

*The next few steps will delete the source files. Be sure that the backup process has been successful before doing so!*

Collate scripts to delete files
```
mkdir delete_s3

parallel \
  -a plates.csv \
  --header ".*\n" \
  -C "," \
  --keep-order \
  aws s3 cp s3://imaging-platform/projects/${PROJECT_NAME}/workspace/backup/${PROJECT_NAME}_${BATCH_ID}_{1}_delete_s3.sh delete_s3/

cat delete_s3/* > delete_s3.sh
```

Delete the files from S3!
```
parallel -a delete_s3.sh
```
