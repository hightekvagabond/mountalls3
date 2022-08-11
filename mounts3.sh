#!/usr/bin/bash

#this script mounts all s3 buckets to your home dir under s3, make sure you have s3fs already installed which is easy on ubuntu: sudo apt-get install s3fs

#you also need to have amazon cli installed and your credentials set up

#get a list of profiles
profiles=$(aws configure list-profiles)

#make sure we have the s3 directory to mount to
mkdir -p ~/s3

for profile in $profiles; do  #itterate through profiles
    #this is hacky but it works since aws cli doesn't have a way to query the secret key that I could find
    access_key=`grep -A 5 -m 1 "[$profile]" ~/.aws/credentials | grep -m 1 aws_access_key_id | awk '{split($0,a," = "); print a[2]}'`
    secret_key=`grep -A 5 -m 1 "[$profile]" ~/.aws/credentials | grep -m 1 aws_secret_access_key | awk '{split($0,a," = "); print a[2]}'`
    #create the password file for mounting
    echo "$access_key:$secret_key" > ~/.aws/passwd-s3fs-$profile
    /usr/bin/chmod 600 ~/.aws/passwd-s3fs-$profile

    #this is hacky too but it gives us a list of buckets for this profile
    buckets=`aws --profile $profile s3api list-buckets --query "Buckets[].Name" | sed ':a;N;$!ba;s/\n/ /g' | tr -s ' ' | sed 's/^...\(.*\)...$/\1/' | sed 's/", "/ /g'`

    for bucket in $buckets; do
        mkdir -p ~/s3/$bucket
        /usr/bin/s3fs $bucket ~/s3/$bucket -o passwd_file=~/.aws/passwd-s3fs-$profile
    done


done

