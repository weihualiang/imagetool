#!/bin/bash

#1.Read input information
#2.upload the source image to cloud storage and creat imagelist
#3.Launch instance
#4.Genertate NAT ip


if [[ $# -lt 1 ]] ; then
   echo "Usage: $0 <image.json>"
   echo "The image.json is the base json file for orchestration"
   echo "Example: $0 linux.json"
   exit 1
fi

#1.read input parameters

#echo -n "Please enter the imagelist you will use: "
#read BASE_IMAGELIST_NAME

#if [ ! -n "$BASE_IMAGELIST_NAME" ];then
   #echo "You have no input a imagelist, use default one"
   #BASE_IMAGELIST_NAME=/imagepipeline/machine_images/OL_6.6_20GB_x11-1.3.0-20160409-041817.tar.gz_1025_522_imagelist
#fi

echo -n "Please enter the OS Type:windows,linux. <enter> for default windows: "
read OS_TYPE

if [ ! -n "$OS_TYPE" ];then
   echo "You have not input the OS type, user default one: windows"
   OS_TYPE=windows
fi

set -ex
set -o nounset

#2.Upload image to cloud storage and add imagelist

source ./imagetool/common.config

# Use Site C API endpoint

function napi() {
    nimbula-api -a $NIMBULA_API -u $NIMBULA_API_USER -p $API_PASSWORDFILE "$@"
}

#3. Launch instance
echo "Start to launch instance"

#read base jsonfile and change imagelist,then generate new tmp jsonfile for test
#cp $2 tmpimage.json
#line=`cat $2 |sed -n '/imagelist/='`
#newimagelist='"imagelist"':'"'${BASE_IMAGELIST_NAME}'"'
#sed -i "$line d" tmpimage.json 
#sed -i "$line i$newimagelist," tmpimage.json

orchestration_name=`cat $1 | grep name | head -n 1 | awk -F ":" '{print $2}'|sed 's/\"//g'|sed 's/\,//g'`

#If the orchestration is already there, stop and delete it.
image_exist=`napi list orchestration $orchestration_name`
if [ -n $image_exist ]; then
   echo " $orchestration_name is not found "
else
   image_status=`napi list orchestration $orchestration_name -F status | tail -n 1`
   if [ $image_status != "stopped" ]; then
      napi stop orchestration $orchestration_name --force
   fi
   stop_status="stopping"
   while [[ $stop_status != "stopped" ]]
   do
      stop_status=`napi list orchestration $orchestration_name -F status | tail -n 1`
   done
   napi delete orchestration $orchestration_name
fi

#Add orchestration and start it.
napi add orchestration $1 -F name

napi start orchestration $orchestration_name -F name,status

sleep 30

new_image_status=`napi list orchestration $orchestration_name -F status | tail -n 1`
while [[ $new_image_status != "ready" ]]
do
      new_image_status=`napi list orchestration $orchestration_name -F status | tail -n 1`
done


instance=`napi list orchestration $orchestration_name -f json | grep name |head -n 1 | awk -F : '{print $2}'|sed 's/\"//g'|sed 's/\,//g'`

echo $instance

vcableid=`napi list vcable /imagepipeline -F id,instance | grep $instance |awk '{print $1}'`

ipassociation=`napi add ipassociation $vcableid ippool:/oracle/public/ippool1 -F name,ip`

napi list ipassociation / -F name,vcable,ip | grep $vcableid

echo "The instance status is ready now, you can login it by NAT ip"
