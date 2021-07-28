import boto3

def bulk_restore(bucket,prefix,filter_in=None,filter_out=None,tier='Standard'):
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
            file_list += [x["Key"] for x in page["Contents"]]
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
    count = 0
    for key in file_list:
        try:
            client.restore_object(Bucket=bucket, Key=key, RestoreRequest={'GlacierJobParameters':{'Tier':tier}})
        except:
            print(f"Could not restore object {key}")
        count += 1
        if count %100 ==0:
            print(f"Sent {count} restore requests")
    print('Sent all restore requests')

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Restore Intelligent-Tiering objects in bulk')
    parser.add_argument('bucket', help='Name of the bucket')
    parser.add_argument('prefix', help='Prefix (aka file or folder) to restore')
    parser.add_argument('--filter_in',default=None,nargs='+',help='One or more strings to specify a subset of objects to restore. If >1, any object with ANY filter will be restored')
    parser.add_argument('--filter_out',default=None,nargs='+',help='One or more strings to specify a subset of objects not to restore. If >1, any object with ANY filter will be removed from the list to restore')
    parser.add_argument('--tier',default='Standard',help='Retrieval tier, only change to Expedited for small numbers of files (<1K) or emergencies')
    args = parser.parse_args()
    
    bulk_restore(args.bucket,args.prefix,args.filter_in,args.filter_out,args.tier)
