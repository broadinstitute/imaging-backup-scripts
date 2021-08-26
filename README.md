# imaging-backup-scripts
Scripts to backup and archive data 

## Old approach

We used to [create tarballs and move to a separate bucket]((https://github.com/broadinstitute/imaging-backup-scripts/blob/master/aws_backup.md)) (s3://imaging-platform-cold) that is set to move all contents to Glacier after 7 days. We no longer do this. See instructions for [restoring data from Glacier](https://github.com/broadinstitute/imaging-backup-scripts/blob/master/glacier_restore.md) for tarballs that were archived using this method.

## New approach

Our primary bucket is now in "Intelligent Tiering" mode. See notes [here](https://docs.google.com/document/d/10DcHQuf9lvyzHvbrss83JiH7SLJJFzrmflUjZfWBhmE/edit#bookmark=id.f4htzhqn1ngh) and read more about intelligent tiering [here](https://aws.amazon.com/about-aws/whats-new/2018/11/s3-intelligent-tiering/).

This means that there's no explicit processing for archiving files. They automatically and gradually move into a Glacier'd state after 6 months.

There are two approaches for restoring such files.

1. For restoring individual files, do this

```sh
aws s3api \
  restore-object \
  --bucket BUCKET-NAME \
  --key PREFIX \
  --restore-request GlacierJobParameters={"Tier"="Standard"}
```

Run this to check on status

```sh
aws s3api \
  head-object \
  --bucket BUCKET-NAME \
  --key PREFIX
```

`ongoing-request` will equal `false` when the data is ready to be retrieved

```
{
    "AcceptRanges": "bytes",
    "Restore": "ongoing-request=\"true\"",
    "ArchiveStatus": "ARCHIVE_ACCESS",
    "LastModified": "Thu, 01 Apr 2021 11:24:32 GMT",
    "ContentLength": 4438197,
    "ETag": "\"473ca4d8ad6889a90544f6acff916d31\"",
    "ContentType": "text/csv",
    "Metadata": {},
    "StorageClass": "INTELLIGENT_TIERING"
}
```

2. For restoring a whole folder, use the [restore_intelligent.py](https://github.com/broadinstitute/imaging-backup-scripts/blob/master/restore_intelligent.py) script. See the comments in the script for notes on retrieval cost.

Also see our discussions on Slack
- https://broadinstitute.slack.com/archives/C3QFX04P7/p1627496601111300

> We've now had some data in Intelligent Tiering long enough that it needs to be restored!
Unfortunately, because of the way object stores work, while you can go into the AWS console and restore one file with a point and click, you can't do that with 'folders', because 'folders' in AWS aren't real. Our previous Glacier restore scripts a) were configured to only the file types we typically Glaciered (md5 or .tgz)  b) wouldn't work directly out of the box even so because Intelligent Tiering doesn't restore for just X days and c) weren't super full-featured in terms of only letting us grab subsets of things anyway. I've added a new restoration script to our imaging-backup-scripts repo; right now it only supports Intelligent Tiering restoration but if we think we want to in the future it could pretty easily add more features and/or get it to work on Glacier too. https://github.com/broadinstitute/imaging-backup-scripts/blob/master/restore_intelligent.py


- https://broadinstitute.slack.com/archives/C3QFX04P7/p1627496974114300

> You'll want to do this the night before you need to access any files that have not been used by anyone on AWS in >3 months, since restoration can "on average" take 3-5 hours; if you only need a handful of files you can use the expedited retrieval option, which takes only a few minutes, but in that case you likely want to just use the console anyway.  Expedited retrieval is $300/plate for CellPainting data (vs 0 in standard), so please do use Standard for large data sets unless there is a very good reason not to!

