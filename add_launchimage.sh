#!/bin/bash

#1.Read input information
#2.upload the source image to cloud storage and creat imagelist
#3.Launch instance
#4.Genertate NAT ip


if [[ $# -lt 2 ]] ; then
   echo "Usage: $0 <image timestamp> <image.json>"
   echo "The timestamp can be any unique string defined by your self"
   echo "The image.json is the base json file for orchestration"
   echo "Example: $0 1025_511 linux.json"
   exit 1
fi

#1.read input parameters
source ./imagetool/common.config

echo -n "Please enter the source image link, such as http://***.tar.gz: (<enter> for default): "
read INPUT_BASE_IMAGE_URL

if [ ! -n "$INPUT_BASE_IMAGE_URL" ];then
   echo "You have no input a source image, will use default one"
   echo "Current source image is :  $BASE_IMAGE_URL"
else
   echo "You input a new source image link,modify common.config"
   line="BASE_IMAGE_URL=$INPUT_BASE_IMAGE_URL"
   sed -i "1d" ./imagetool/common.config
   sed -i "1 i$line" ./imagetool/common.config
fi

echo -n "Please enter the OS Type:windows,linux. <enter> for default windows: "
read OS_TYPE

if [ ! -n "$OS_TYPE" ];then
   echo "You have not input the OS type, user default one: windows"
   OS_TYPE=windows
fi

set -ex
set -o nounset

source ./imagetool/common.config
#2.Upload image to cloud storage and add imagelist

function curl_multipart() {
    local arg="$1"
    shift
    local localfile=""
    local lastoption=""
    local cmdline=()
    local url=""
    local chunksize=32768
    local size_threshold=$(($chunksize*65536))
    while [ ! -z "$arg" ]; do
        if [[ "$arg" =~ ^- ]]; then
            lastoption="$arg"
            if [ "$arg" != "-T" ]; then
                cmdline[${#cmdline[@]}]="$arg"
            fi
        else
            if [ -z "$lastoption" ]; then
                # standalone option
                url="$arg"
            else
                if [ "$lastoption" = "-T" ]; then
                    localfile="$arg"
                else
                    cmdline[${#cmdline[@]}]="$arg"
                fi
                lastoption=""
            fi
        fi
        arg=${1-}
        shift || true
    done
    if [ -z "$localfile" -o -z "$url" ]; then
        echo "Error: malformed curl command.  localfile='$localfile', url='$url'" 1>&2
        exit 2
    fi
    local manifest_path=$(echo "$url" | perl -wne 'chomp; m,https?://[^/]+/[^/]+/[^/]+/(.+), && print "$1/\n"')
    if [ -z "$manifest_path" ]; then
        echo "Error: Storage service url in unexpected format: '$url'" 1>&2
        exit 1
    fi
    filesize=$(stat -c%s "$localfile")
    if [ $filesize -lt $size_threshold ]; then
        curl "${cmdline[@]}" -T "$localfile" "$url"
        return
    fi
    local skip=0
    local part=1
    while [ $skip -lt $filesize ]; do
        local part_str=$(printf "%8.8i" $part)
        local tmpfile=$(mktemp)
        dd if="$localfile" bs=$chunksize count=$(($size_threshold/$chunksize)) skip=$(($skip/$chunksize)) > $tmpfile
        curl "${cmdline[@]}" -T $tmpfile "$url/$part_str" --data-binary "$part"
        rm -f $tmpfile
        part=$(($part+1))
        skip=$(($skip+$size_threshold))
    done
    curl "${cmdline[@]}" -H "X-Object-Manifest: $manifest_path" $url --data-binary ''
}


function upload_baseimage_to_storage() {
    local LOCALFILE=$1
    local TIME_TO_LIVE=604800
    curl_multipart -f --header "X-Delete-After:$TIME_TO_LIVE" --noproxy storage.oraclecorp.com -u Storageadmin:P9q84imX -X PUT -T ${LOCALFILE} "${IMAGE_PIPELINE_CONTAINER_URL}/${LOCALFILE}" -v
}



function napi() {
    nimbula-api -a $NIMBULA_API -u $NIMBULA_API_USER -p $API_PASSWORDFILE "$@"
}

BUILD_TIME_STAMP=$1

BASE_IMAGE_FILENAME=$(basename $BASE_IMAGE_URL)
BASE_IMAGE_TEMP_FILENAME=${BASE_IMAGE_FILENAME}_${BUILD_TIME_STAMP}
BASE_MACHINEIMAGE_NAME=${MACHINE_IMAGES_FOLDER}/${BASE_IMAGE_FILENAME}_${BUILD_TIME_STAMP}
BASE_IMAGELIST_NAME=/${BASE_MACHINEIMAGE_NAME}_imagelist
MID_MACHINEIMAGE_NAME=${MACHINE_IMAGES_FOLDER}/${BASE_IMAGE_FILENAME}_${BUILD_TIME_STAMP}_mid


wget --progress=dot:giga --no-proxy -O $BASE_IMAGE_FILENAME $BASE_IMAGE_URL
mv -fv $BASE_IMAGE_FILENAME ${BASE_IMAGE_TEMP_FILENAME}
upload_baseimage_to_storage ${BASE_IMAGE_TEMP_FILENAME}
rm -f ${BASE_IMAGE_TEMP_FILENAME}

if [ "$OS_TYPE" == "windows" ]; then
    napi add machineimage ${BASE_MACHINEIMAGE_NAME} ${BASE_IMAGE_TEMP_FILENAME} --no_upload --account ${NIMBULA_API_ADD_MACHINEIMAGE_ACCOUNT} --attributes '{"windows_kms": "kms-dev1.usdv1.oraclecloud.com"}' --platform ${OS_TYPE}
else
    napi add machineimage ${BASE_MACHINEIMAGE_NAME} ${BASE_IMAGE_TEMP_FILENAME} --no_upload --account ${NIMBULA_API_ADD_MACHINEIMAGE_ACCOUNT} --platform ${OS_TYPE}
fi
napi add imagelist ${BASE_IMAGELIST_NAME} "imagelist for ${BASE_IMAGE_TEMP_FILENAME}"

napi add imagelistentry ${BASE_IMAGELIST_NAME} ${BASE_MACHINEIMAGE_NAME} 1

#3. Launch instance
echo "Start to launch instance"

#read base jsonfile and change imagelist,then generate new tmp jsonfile for test
cp $2 tmpimage.json
line=`cat $2 |sed -n '/imagelist/='`
newimagelist='"imagelist"':'"'${BASE_IMAGELIST_NAME}'"'
sed -i "$line d" tmpimage.json 
sed -i "$line i$newimagelist," tmpimage.json

orchestration_name=`cat $2 | grep name | head -n 1 | awk -F ":" '{print $2}'|sed 's/\"//g'|sed 's/\,//g'`

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
napi add orchestration tmpimage.json -F name

napi start orchestration $orchestration_name -F name,status

sleep 30

new_image_status=`napi list orchestration $orchestration_name -F status | tail -n 1`
while [[ $new_image_status != "ready" ]]
do
      new_image_status=`napi list orchestration $orchestration_name -F status | tail -n 1`
done

napi delete machineimage ${BASE_MACHINEIMAGE_NAME}
napi delete imagelist ${BASE_IMAGELIST_NAME}

instance=`napi list orchestration $orchestration_name -f json | grep name |head -n 1 | awk -F : '{print $2}'|sed 's/\"//g'|sed 's/\,//g'`

echo $instance

vcableid=`napi list vcable /imagepipeline -F id,instance | grep $instance |awk '{print $1}'`

ipassociation=`napi add ipassociation $vcableid ippool:/oracle/public/ippool1 -F name,ip`

napi list ipassociation / -F name,vcable,ip | grep $vcableid

echo "The instance status is ready now, you can login it by NAT ip"
