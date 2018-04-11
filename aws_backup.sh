# This script create a single tarball for each plate of data. The tarball contains
# - images (typically ~230Gb)
# - illumination functions (tiny)
# - CellProfiler measurements as CSV files (typically ~30Gb)
# - SQLite backend created by ingesting the CSV files (typically ~24Gb)
#
# The tar ball is stored at this location
#
# s3://imaging-platform-cold/imaging_analysis/<PROJECT_NAME>/plates/<PROJECT_NAME>_<BATCH_ID>_<PLATE_ID>.tar.gz
# 
# e.g.
# .
# └── imaging-platform-cold
#     └── imaging_analysis
#         └── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad
#             └── plates
#                 ├── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092655.tar.gz
#                 ├── ...
#                 └── 2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad_2017_12_05_Batch2_BR00092789.tar.gz


BUCKET=imaging-platform
PROJECT_NAME=2015_10_05_DrugRepurposing_AravindSubramanian_GolubLab_Broad
BATCH_ID=2017_12_05_Batch2
PLATE_ID_FULL="BR00092655__2017-12-10T12_48_16-Measurement 1"
PLATE_ID=BR00092655
COLD_BUCKET=imaging-platform-cold

S3_PREFIX=s3://${BUCKET}/projects/${PROJECT_NAME}
S3_COLD_PREFIX=s3://${COLD_BUCKET}/imaging_analysis/${PROJECT_NAME}/plates/
PLATE_ARCHIVE_DIR=${PROJECT_NAME}_${BATCH_ID}_${PLATE_ID}

# report sizes
# s3cmd du "${S3_PREFIX}/${BATCH_ID}/images/${PLATE_ID_FULL}"
# s3cmd du "${S3_PREFIX}/${BATCH_ID}/illum/${PLATE_ID}"
# s3cmd du "${S3_PREFIX}/workspace/analysis/${BATCH_ID}/${PLATE_ID}"
# s3cmd du "${S3_PREFIX}/workspace/backend/${BATCH_ID}/${PLATE_ID}"

# create staging directory

cd /tmp

mkdir ${PLATE_ARCHIVE_DIR}

cd ${PLATE_ARCHIVE_DIR}

# create subdirectories 

mkdir -p "${PROJECT_NAME}/${BATCH_ID}/images/${PLATE_ID_FULL}"
mkdir -p "${PROJECT_NAME}/${BATCH_ID}/illum/${PLATE_ID}"
mkdir -p "${PROJECT_NAME}/workspace/analysis/${BATCH_ID}/${PLATE_ID}"
mkdir -p "${PROJECT_NAME}/workspace/backend/${BATCH_ID}/${PLATE_ID}"

# download data from S3

cd ${PROJECT_NAME}

aws s3 sync "${S3_PREFIX}/${BATCH_ID}/images/${PLATE_ID_FULL}" "${BATCH_ID}/images/${PLATE_ID_FULL}"
aws s3 sync "${S3_PREFIX}/${BATCH_ID}/illum/${PLATE_ID}" "${BATCH_ID}/illum/${PLATE_ID}"
aws s3 sync "${S3_PREFIX}/workspace/analysis/${BATCH_ID}/${PLATE_ID}" "workspace/analysis/${BATCH_ID}/${PLATE_ID}"
aws s3 sync "${S3_PREFIX}/workspace/analysis/${BATCH_ID}/${PLATE_ID}" "workspace/analysis/${BATCH_ID}/${PLATE_ID}"

# create tarball

cd ../../

tar -czf ${PLATE_ARCHIVE_DIR} ${PLATE_ARCHIVE_DIR}.tar.gz

aws s3 sync ${PLATE_ARCHIVE_DIR}.tar.gz ${S3_COLD_PREFIX}

rm -rf ${PLATE_ARCHIVE_DIR} ${PLATE_ARCHIVE_DIR}.tar.gz


