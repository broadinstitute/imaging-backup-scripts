```
PROJECT_NAME=2013_Gustafsdottir_PLOSONE
BATCH_ID=BBBC022

mkdir ~/ebs_tmp

cd ~/work/software

git clone git@github.com:broadinstitute/imaging-backup-scripts.git

cd imaging-backup-scripts

```

Create a list of plates

```
echo "plate_id,plate_id_full" > plates.txt

echo 20585 20586 20589 20590 20591 20592 20593 20594 20595 20596 20607 20608 20625 20626 20630 20633 20639 20640 20641 20646 | \
  tr " " "\n" |
  awk '{ print $1 "," $1 }' \
  >> plates.txt
```


```
LOGDIR=log/${PROJECT_NAME}_${BATCH_ID}
mkdir -p $LOGDIR
```

```
parallel \
  -a plates.txt \
  --header ".*\n" \
  -C "," \
  --keep-order \
  --dry-run \
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


Check whether upload was ok. First, defind functions to check whether etags of file listings match. 

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

Now run in parallel 
```
# export functions and variables so that they are visible inside parallel
export -f etag
export -f check_plate
export PROJECT_NAME
export BATCH_ID

parallel \
  -a plates.txt \
  --header ".*\n" \
  -C "," \
  --keep-order \
  --eta \
  --joblog ${LOGDIR}/backup_check.log \
  --results ${LOGDIR}/backup_check \
  --files \
  check_plate {1}
```

Check whether there are any errors

```
find ${LOGDIR}/backup_check -name stderr -exec cat {} \;

cat find ${LOGDIR}/backup_check.log
```


The next few steps will delete the source files. Be sure that the backup process has been successful before doing so!

Collate scripts to delete files
```
mkdir delete_s3

parallel \
  -a plates.txt \
  --header ".*\n" \
  -C "," \
  --keep-order \
  aws s3 cp s3://imaging-platform/projects/${PROJECT_NAME}/workspace/backup/${PROJECT_NAME}_${BATCH_ID}_{1}_delete_s3.sh delete_s3/

cat delete_s3/* > delete_s3.sh
```

```
parallel -a delete_s3.sh
```
