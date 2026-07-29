#!/bin/bash
IMAGE_FILE="images.txt"
TARGET_REPO="docker.io/ccxylt/prometheus"

while read -r image
do
    # 跳过空行和注释
    [[ -z "$image" || "$image" =~ ^# ]] && continue

    echo "================================="
    echo "Processing: $image"

    # 提取镜像名
    name=$(echo "$image" | awk -F'[:/]' '{print $(NF-1)}')

    # 提取TAG
    if [[ "$image" == *":"* ]]; then
        tag=${image##*:}
    else
        tag="latest"
    fi

    target="${TARGET_REPO}:${name}-${tag}"

    echo "Pulling   : $image"
    nerdctl pull "$image"

    if [ $? -ne 0 ]; then
        echo "Pull Failed: $image"
        continue
    fi

    echo "Tagging   : $target"
    nerdctl tag "$image" "$target"

    echo "Pushing   : $target"
    nerdctl push "$target"

    if [ $? -eq 0 ]; then
        echo "Push Success!"
    else
        echo "Push Failed!"
    fi

    echo
done < "$IMAGE_FILE"

批量推送镜像
#cat images.txt | xargs -P 5 -I {} ./push_one.sh {}
