#!/usr/bin/bash

#this script mounts all s3 buckets to your home dir under s3, make sure you have s3fs already installed which is easy on ubuntu: sudo apt-get install s3fs

#you also need to have amazon cli installed and your credentials set up

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
    access_key=`grep -A 5 -m 1 "[$profile]" ~/.aws/credentials | grep -m 1 aws_access_key_id | awk '{split($0,a,"\s*=\s*"); print a[2]}'`
    secret_key=`grep -A 5 -m 1 "[$profile]" ~/.aws/credentials | grep -m 1 aws_secret_access_key | awk '{split($0,a,"\s*=\s*"); print a[2]}'`
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
	cmd="/usr/bin/s3fs -o check_cache_dir_exist  $option $bucket $mountbase/$bucket -o passwd_file=~/.aws/passwd-s3fs-$profile "
	#echo "$cmd"
	eval "$cmd" #using eval to create the command in only one place but still show it on the screen
	mountgrep=`mount | grep "s3fs" | grep "$bucket"`
	#echo "mountgrep: $mountgrep"
	if [ -z "$mountgrep" ]; then
		echo "   There seems to have been a problem mounting $bucket to $mountbase/$bucket to troubleshoot run:"
		echo "          $cmd -f"
	else
		echo "   Mounted: $bucket"	
	fi


    done


done

