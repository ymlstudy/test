#!/bin/bash
read -p "Enter Your IMAGE: " image
nerdctl pull $image
name=`echo $image|awk -F'[:/]' '{print $(NF-1)}'`
tag=`echo $image|awk -F'[:/]' '{print $NF}'`

nerdctl tag $image docker.io/ccxylt/prometheus:$name-$tag
nerdctl push docker.io/ccxylt/prometheus:$name-$tag

