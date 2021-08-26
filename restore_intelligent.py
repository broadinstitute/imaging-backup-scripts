import csv
import json
import time
from functools import partial
import boto3
from tqdm.contrib.concurrent import thread_map

def restore_object(key, bucket, tier):
    """
    Check Object status before requesting the restoration.
    returns a dict with key and the status of the request. If there is an error
    message and object metadata is also included in the response.
    """
    client = boto3.session.Session().client("s3")  
    metadata = client.head_object(Bucket=bucket, Key=key)
    headers = metadata["ResponseMetadata"]["HTTPHeaders"]
    if "x-amz-archive-status" not in headers:
        return {"key": key, "status": "RESTORED"}
    if "Restore" in metadata:
        restore_tag = metadata["Restore"]
        if "expiry-date" in restore_tag:
            return {"key": key, "status": "RESTORED"}
        if 'ongoing-request="true"' in restore_tag:
            return {"key": key, "status": "IN_PROGRESS"}
    try:
        client.restore_object(Bucket=bucket, Key=key, RestoreRequest={'GlacierJobParameters':{'Tier':tier}})
        return {"key": key, "status": "REQUESTED"}
    except Exception as ex:
        return {"key": key,
                "status": "ERROR",
                "message": {str(ex)},
                "metadata": json.dumps(metadata, default=str)}

def bulk_restore(bucket,prefix,filter_in=None,filter_out=None,tier='Standard',max_workers=8,logfile='output.csv'):
    """
    Bulk restore a bunch of things in S3 that are in the IntelligentTiering class.
    You need to pass in a bucket and a prefix (aka file OR folder).
    If your prefix is a folder, you can optionally then also pass some filters to subset the data.
    filter_in and filter_out can both take either strings or lists.
    If a list in filter_in, it will keep any object that has ANY filter.
    If a list in filter_out, it will remove any object that has ANY filter. 
    You should always use tier=Standard for large requests unless it is a very severe emergency, 
    (A standard cell painting plate is ~$300 to restore in Expedited but free in Standard)
    but if it IS an emergency or it's only a couple files, you can pass tier='Expedited' instead)
    To call at the command line, use `python restore_intelligent.py bucketname folder --filter_in ch1 ch2 --filter_out .txt .csv`
    """
    client = boto3.client('s3')
    paginator = client.get_paginator("list_objects_v2")
    pages = paginator.paginate(Bucket=bucket, Prefix=prefix)
    file_list = []
    try:
        for page in pages:
            file_list += [x["Key"] for x in page["Contents"] if x["StorageClass"] == "INTELLIGENT_TIERING"]
    except KeyError:
        print ("No files in prefix given.")
        return
    print(f"{len(file_list)} total files found pre-filtering")
    if filter_in:
        if type(filter_in) == str:
            file_list = [x for x in file_list if filter_in in x]
        elif type(filter_in) == list:
            masterlist = []
            for eachfilter in filter_in:
                filtered_list = [x for x in file_list if eachfilter in x]
                masterlist += filtered_list
            file_list = list(set(masterlist))
    if filter_out:
        if type(filter_out) == str:
            file_list = [x for x in file_list if filter_out not in x]
        elif type(filter_out) == list:
            for eachfilter in filter_out:
                file_list = [x for x in file_list if eachfilter not in x]
    print(f"{len(file_list)} total files remain post-filtering")
    outputs = thread_map(partial(restore_object, tier=tier, bucket=bucket),
                         file_list, max_workers=max_workers)
    counts = {'REQUESTED': 0, 'IN_PROGRESS': 0, 'RESTORED': 0, 'ERROR': 0}
    with open(logfile, 'w', newline='') as csvfile:
        writer = csv.DictWriter(
                csvfile, fieldnames=["key", "status", "message", "metadata"])
        writer.writeheader()
        for output in outputs:
            counts[output["status"]] += 1
            writer.writerow(output)

    for status, count in counts.items():
        print(f'{status:<14} {count}')
    print(f'For more info check {logfile}')

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Restore Intelligent-Tiering objects in bulk')
    parser.add_argument('bucket', help='Name of the bucket')
    parser.add_argument('prefix', help='Prefix (aka file or folder) to restore')
    parser.add_argument('--filter_in',default=None,nargs='+',help='One or more strings to specify a subset of objects to restore. If >1, any object with ANY filter will be restored')
    parser.add_argument('--filter_out',default=None,nargs='+',help='One or more strings to specify a subset of objects not to restore. If >1, any object with ANY filter will be removed from the list to restore')
    parser.add_argument('--tier',default='Standard',help='Retrieval tier, only change to Expedited for small numbers of files (<1K) or emergencies')
    parser.add_argument('--max_workers',default=8,help='Number of parallel AWS requests', type=int)
    parser.add_argument('--logfile',default='output.csv',help='Path to save the status log in csv format')
    args = parser.parse_args()
    
    bulk_restore(args.bucket,args.prefix,args.filter_in,args.filter_out,
                 args.tier,args.max_workers,args.logfile)
