# Retrieving data from Glacier

These instructions assume that the project was archived using `aws_backup.sh`. 
This process is best done on an ec2 instance with a large enough volume.

Create a temp directory to unarchive

```sh
mkdir ~/ebs_tmp/
cd ~/ebs_tmp
```

Clone this repo 

```sh
git clone https://github.com/broadinstitute/imaging-backup-scripts.git
```

Define variables

```sh
PROJECT_NAME=2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad
BATCH_ID=2016_04_01_a549_48hr_batch1
```

Create a list of plates to be restored. Here, use the shortened name that is used throughout the rest of the profiling workflow e.g. use `SQ00015147`, not `SQ00015147__2016-05-17T07_49_53-Measurement1`:

```
echo "SQ00015147" > list_of_plates.txt
```

Run the retrieval process. 

In this example, we retrieve only the backend (`--get_backend`). To restore only images, use `--get_images`. To restore both, use both flags.

```
cd imaging-backup-scripts
```

```sh
parallel \
  --results restore \
  -a ../list_of_plates.txt \
  ./glacier_restore.sh \
  --project_name ${PROJECT_NAME} \
  --batch_id ${BATCH_ID} \
  --plate_id {1} \
  --get_backend
```

The retrieval may take several hours. Check status again in a few hours and ensure that all files are available. To do so, run the same command as above but with the `--check_status` flag:

```sh
parallel \
  --results restore \
  -a ../list_of_plates.txt \
  ./glacier_restore.sh \
  --project_name ${PROJECT_NAME} \
  --batch_id ${BATCH_ID} \
  --plate_id {1} \
  --get_backend \
  --check_status
```

This creates an stdout file per plate at `restore/1/<plate_id>/stdout`. 
If a request has been made, you'll receive a response (in `stdout`) similar to the following if the restore is still in progress

```
> "Restore": "ongoing-request=\"true\""
> "StorageClass": "GLACIER"
```

After the restore is complete, the response is similar to the following

```
"Restore": "ongoing-request=\"false\", expiry-date=\"Sun, 13 Aug 2017 00:00:00 GMT\""
```

If no request has been made, "Restore" key will be absent

Once all files have been restored, download the backend files from Glacier.

First, collect the URLs

```
cd ~/ebs_tmp
```

```sh
parallel -a list_of_plates.txt "grep ^Download restore/1/{1}/stdout|sed s,Download:,,1" > url_list.txt
```

Do the same for the MD5 checksum files

```sh
parallel -a list_of_plates.txt "grep MD5Download restore/1/{1}/stdout|sed s,MD5Download:,,1" > md5_url_list.txt
```

Next, download these files

```sh
parallel -a url_list.txt aws s3 cp {1} .
```

```sh
parallel -a md5_url_list.txt aws s3 cp {1} .
```

Uncompress the files

For backend:

```
TARSET=backend
```

For images, illum, and analysis:

```
TARSET=images_illum_analysis
```

```sh
parallel -a list_of_plates.txt tar -xvzf ${PROJECT_NAME}_${BATCH_ID}_{1}_${TARSET}.tar.gz
```


Verify the md5

```sh
parallel -a list_of_plates.txt "md5sum ${PROJECT_NAME}_${BATCH_ID}_{1}_${TARSET}.tar.gz > ${PROJECT_NAME}_${BATCH_ID}_{1}_${TARSET}.md5.local"
```

Sync to S3 bucket (if you want to restore to the original location on `s3://imaging-platform`).


**WARNING: Be cautious because this step overwrites files at the destination**

For backend

```sh
parallel \
  -a list_of_plates.txt \
  aws s3 sync \
  ${PROJECT_NAME}${BATCH_ID}{1}/${PROJECT_NAME}/workspace/backend/${BATCH_ID}/ \
  s3://imaging-platform/projects/${PROJECT_NAME}/workspace/backend/${BATCH_ID}/
```
