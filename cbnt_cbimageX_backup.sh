source_dir=/cbnt/cbimageX/HCS
destination_dir=/imaging/cold/cbnt_cbimageX_backup
subdir=xiaoyunwu
dir_list=`find ${source_dir}/$subdir -maxdepth 1 -mindepth 1 -type d`
mkdir -p ${destination_dir}/${subdir}

for dir in $dir_list;
do
    file=`basename $dir`
    qsub -cwd -o ${destination_dir}/${subdir}/x${file}.log -N x${file} -j y -b y -V "tar cvf - ${dir} | gzip --fast > ${destination_dir}/${subdir}/${file}.tar.gz"
done

