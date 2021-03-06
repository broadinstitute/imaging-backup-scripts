# Check sizes of project directories in s3://imaging-platform/projects/
# NOTE: This can consume a lot of memory and is very slow
parallel \
  s3cmd du s3://imaging-platform/projects/{1} ::: \
  `aws s3 ls s3://imaging-platform/projects/ | grep PRE | tr -s " " |cut -d" " -f3 | cut -d"/" -f1` | \
  sort -nr | \
  awk '{ print $2 "," $1 }' | \
  cut -d"/" -f5 > \
  imaging-platform_project_sizes.csv
