dir_list=`find /cbnt/cbimageX/HCS/xiaoyunwu/ -maxdepth 1 -mindepth 1 -type d`

for dir in $dirlist;
do
	echo tar cvf - ${dir} | gzip > ${dir}.tar.gz
done

