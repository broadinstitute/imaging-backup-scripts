# Archiving projects to Glacier

The script `aws_backup.sh` expects the project directories to have a very specific structure.
See the script documentation for details.

`aws_backup.sh` creates one set of tarballs for each plate of data. This makes retrieval easy.

Start a large  ec2 instance (e.g. `m4.16xlarge`) because you will need plenty of memory, high network bandwidth.

Then attach a large EBS volume to the instance. As of June 2018, each 384-well plate of Cell Painting data acquired at the Broad produces about 300Gb of data, of which 230Gb are images. During the archiving process, both, the uncompressed files as well as the tarballs (about 250Gb) will reside on the EBS volume. You will need n x 550Gb of disk space on the EBS volume. The maximum allowable size is 16Tb, so you can comfortably process 27 plates of data in parallel given this limit.

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
PROJECT_NAME=2015_Bray_GigaScience
BATCH_ID=CDRP

mkdir ~/ebs_tmp

cd ~/work/software

git clone git@github.com:broadinstitute/imaging-backup-scripts.git

cd imaging-backup-scripts

```

Create a list of plates to be archived. `plate_id_full` is the full name of the plate, as it exists in the `images/` directory. `plate_id` is the shortened name that is used throughout the rest of the profiling workflow. In this example, `plate_id_full` is the same as `plate_id` but that isn't always the case.

```
echo "plate_id,plate_id_full" > plates.csv

echo 24277 24278 24279 | \
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

Run the archiving script across all the plates. This step can also been run in parallel on remote servers using SSH (see alternate workflow for this step below).

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

find ${LOGDIR}/backup_check -name stdout -exec cat {} \;

cat ${LOGDIR}/backup_check.log

```

*The next few steps will delete the source files. Be sure that the backup process has been successful before doing so!*

Collate scripts to delete files
```
rm -rf delete_s3 && mkdir delete_s3

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

Note: This process will be slow until this is address https://github.com/aws/aws-cli/issues/3163

If you've followed the workflow below using ssh, you may choose to use the fleet to delete files:

```
parallel \
  -a delete_s3.sh \
  --no-run-if-empty \
  --sshloginfile nodes.txt \
  --env PATH \
  --max-procs 1 \
  --eta \
  --joblog ${LOGDIR}/delete_s3.log \
  --results ${LOGDIR}/delete_s3 \
  --keep-order \
  --files

```

If you've followed the workflow below using ssh, be sure to delete the fleet to avoid racking up a huge bill!

## Alternate workflow using parallel with ssh

Fire up many machines. Configure `config.json` appropriately before launching.

Set `TargetCapacity` to be number of machines to run in parallel. If the number of plate is less than 30, set this to the number of plates. If the number of plate is greater than 30, set this so that there are not too many idle machines sitting around towards the end. E.g. For, say, 65 plates, set `TargetCapacity` to 22. Here's one way to compute `TargetCapacity` for a batch with large number of plates.

```
n = 136 # e.g. number of plates
k_max = 30 # max no. of machine to launch
w_max = 3 # max no. of machines that should be idle in the final iteration

k = k_max

while (n % k > w_max):
    k = k - 1

print k # TargetCapacity
```

You may need to run `aws configure` before requesting the fleet.

```
aws ec2 request-spot-fleet --spot-fleet-request-config file://config.json

```

Set up key to access the machines. The key should be the same as the `KeyName` specified in `config.json`

```
mkdir -p ~/.ssh

# copy pem file to ~/.ssh/CellProfiler.pem

eval "$(ssh-agent -s)"

PEMFILE=~/.ssh/CellProfiler.pem

ssh-add ${PEMFILE}

```

Get list of machines

```
HOSTS=`aws ec2 describe-instances --filters "Name=tag:Name,Values=imaging-backup" --query "Reservations[].Instances[].PublicDnsName" --region "us-east-1" | jq -r .[]`

```

Log in to each machine after turning off host key checking so that it is entered into known hosts

```

rm -f ~/.ssh/known_hosts

echo -n $HOSTS | \
  parallel   --delay 1 \
  --max-procs 1 \
  -v \
  --gnu -d " " \
  -I HOST \
  "ssh -o StrictHostKeyChecking=no -l ubuntu HOST 'exit'"

```

Make a list of all the nodes

```
echo -n $HOSTS | parallel -d " " echo ubuntu@{1} > nodes.txt
```

Clear contents of `tmp` directory in each node.

```
parallel  \
  --no-run-if-empty \
  --sshloginfile nodes.txt \
  --max-procs 1 \
  --nonall \
  "rm -rf /tmp/*"

```

The `imaging-backup-scripts` repo is private, so upload the zipped version to some location, and set the variable `REPO`.

```
REPO="https://imaging-platform.s3.amazonaws.com/tmp/imaging-backup-scripts-master.zip"
```

Initialize environment on each node.

```
INIT_ENV="rm -rf ~/ebs_tmp && mkdir -p ~/ebs_tmp && cd ~/ebs_tmp && wget ${REPO} && unzip imaging-backup-scripts-master.zip"

parallel  \
  --delay 1 \
  --no-run-if-empty \
  --sshloginfile nodes.txt \
  --results init_env \
  --files \
  --env PATH \
  --nonall \
  ${INIT_ENV}

```

Check whether there is enough space.

```
parallel  \
  --delay 1 \
  --no-run-if-empty \
  --sshloginfile nodes.txt \
  --nonall \
  "df -h|grep /dev/xvda1"

```

Check whether the repo has been downloaded correctly.

```
parallel  \
  --delay 1 \
  --no-run-if-empty \
  --sshloginfile nodes.txt \
  --nonall \
  "ls ~/ebs_tmp/imaging-backup-scripts-master"

```

Run the archiving script across all the plates. Note that `max-procs` refers to the number of processes *per machine*. So `max-procs 1` means that each node on the fleet will run one process.

```
parallel \
  --delay 1 \
  --no-run-if-empty \
  --sshloginfile nodes.txt \
  --env PATH \
  --max-procs 1 \
  --eta \
  --joblog ${LOGDIR}/backup.log \
  --results ${LOGDIR}/backup \
  -a plates.csv \
  --header ".*\n" \
  -C "," \
  --keep-order \
  --files \
  "cd ~/ebs_tmp/imaging-backup-scripts-master && ./aws_backup.sh --project_name \"${PROJECT_NAME}\" --batch_id \"${BATCH_ID}\" --plate_id \"{1}\" --plate_id_full \"{2}\" --tmpdir ~/ebs_tmp"

```

Now continue with the regular workflow ("Check whether archiving process succeeded...")
