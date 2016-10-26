# imagetool
Some userful working tool for image launching

There are 3 shell scripts and 1 config file in the folder
When you use the any tool in them, please make sure the common.config is in same path

1. common.config
   Base configuration parameter, including NIMBULA_API, NIMBULA_PASSWORD,etc, you can
   modify them accorind to your env.

2. addimage.sh
   Upload a new source image tar file to cloud storage
   add machineimage
   add imagelist

   Usage: ./addimage.sh <image_timestamp>

3. launchinstance.sh
   When the imagelist is already available, you can use this tool to launch instance and get NAT ip
   An orchestration jsonfile should be the input parameter
   ./launchinstance.sh <orchestration.json>
   You should modify the imagelist in orchestration json file

3. add_launchimage.sh
   Integrate the functionality of addimage.sh and launchinstance.sh
   Usage: ./add_launchimage.sh <image_timestamp> <orchestration.json>
   You have no need to modify imagelist of <orchestration.json>
