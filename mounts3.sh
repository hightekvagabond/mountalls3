#!/usr/bin/bash

#this script mounts all s3 buckets to your home dir under s3, make sure you have s3fs already installed which is easy on ubuntu: sudo apt-get install s3fs

#you also need to have amazon cli installed and your credentials set up

#it was written to run on my kbuntu instances so if you are running it somewhere else you might have to fix some pathing on things.


#get a list of profiles
profiles=$(aws configure list-profiles)

mountbase="$HOME/s3"


#unmount everything to start fresh
IFS=$'\n' #to split on newline
for line in $(mount | grep "s3fs");do
	#example line:  s3fs on /home/gypsy/s3/imaginationguild-devshare type fuse.s3fs (rw,nosuid,nodev,relatime,user_id=1000,group_id=1000)
	mountpoint="$(cut -d' ' -f3 <<<\"$line\" )"
	if [[ $line =~ "$mountbase"* ]]; then
		echo "unmounting $mountpoint"
		`umount $mountpoint`
	fi
done
unset IFS #reset to default split



#delete unused dirs
#echo "delete time"
`rm -r  $mountbase`
#make sure we have the s3 directory to mount to
mkdir -p $mountbase


#itterate through the list of profiles
for profile in $profiles; do  #itterate through profiles
    echo "Mounting buckets from $profile:"
    #this is hacky but it works since aws cli doesn't have a way to query the secret key that I could find
    #TODO: should probably grep out comments and empty lines to make sure that the -A5 has a better chance of working but this is working for me for now
    access_key=`grep -A 5 -m 1 "\[$profile\]" ~/.aws/credentials | grep -m 1 aws_access_key_id | awk '{split($0,a,"\s*=\s*"); print a[2]}' | tr -d ' '`
    secret_key=`grep -A 5 -m 1 "\[$profile\]" ~/.aws/credentials | grep -m 1 aws_secret_access_key | awk '{split($0,a,"\s*=\s*"); print a[2]}' | tr -d ' '`
    #create the password file for mounting
    echo "$access_key:$secret_key" > ~/.aws/passwd-s3fs-$profile
    /usr/bin/chmod 600 ~/.aws/passwd-s3fs-$profile

    #this is hacky too but it gives us a list of buckets for this profile
    buckets=`aws --profile $profile s3api list-buckets --query "Buckets[].Name" | sed ':a;N;$!ba;s/\n/ /g' | tr -s ' ' | sed 's/^...\(.*\)...$/\1/' | sed 's/", "/ /g'`

    for bucket in $buckets; do
	#if it has a dot add this flag: -o use_path_request_style
	option=""
	if [[ $bucket =~ "." ]]; then
		option=" -o use_path_request_style "
	fi
	mkdir -p $mountbase/$bucket

	#manage endpoint to get around defaults
	locationinfo="$(aws s3api get-bucket-location --profile=$profile --bucket $bucket)"
	reg='\"LocationConstraint\": \"(.*?)\"'
	[[ "$locationinfo" =~ $reg ]] 
	location="${BASH_REMATCH[1]}"
	if [[ ! -z $location ]]; then
		option="$option  -o url=https://s3-$location.amazonaws.com "
	fi


	cmd="/usr/bin/s3fs -o check_cache_dir_exist  $option $bucket $mountbase/$bucket -o passwd_file=~/.aws/passwd-s3fs-$profile "
	#echo "$cmd"
	eval "$cmd" #using eval to create the command in only one place but still show it on the screen

	#check to see if it mounted
	processing=true
	while [[ (! ("$(mountpoint $mountbase/$bucket)" == *"is a mountpoint"*)) && "$processing" == true ]]; do
		echo "$bucket is not a mount point yet"
		mountgrep=`mount | grep "s3fs" | grep "$bucket"`
		if [ -z "$mountgrep" ]; then
			echo "  There seems to have been a problem mounting $bucket to $mountbase/$bucket to troubleshoot run:"
			echo "    $cmd -o dbglevel=info -f"
			processing=false
		else
			echo "Looks like we are still trying to mount $bucket, waiting 5 seconds"
			sleep 5
		fi
	done
	if [[ "$processing" == true ]]; then
		echo "   Mounted: $bucket"   
	fi
    done
done
