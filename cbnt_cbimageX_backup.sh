# Script to create zipped tarballs 
# Use long queue if any subdirectory is likely to take longer than 2 hours

source_dir=/cbnt/cbimageX/HCS
destination_dir=/imaging/cold/cbnt_cbimageX_backup
subdir=xiaoyunwu
dir_list=`find ${source_dir}/$subdir -maxdepth 1 -mindepth 1 -type d`
mkdir -p ${destination_dir}/${subdir}

# 2 hour limit (as of 2016/11).
QUEUE=short
# No time limit (as of 2016/11)
#QUEUE=long

EXCLUDE_FILE=exclude.txt

for dir in $dir_list;
do
    if `grep -Fxq $dir $EXCLUDE_FILE`
    then
	echo Skipping $dir
    else
	file=`basename $dir`
	echo qsub -q ${QUEUE} -cwd -o ${destination_dir}/${subdir}/x${file}.log -N x${file} -j y -b y -V "tar cvf - ${dir} | gzip --fast > ${destination_dir}/${subdir}/${file}.tar.gz"
    fi
done

