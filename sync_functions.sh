#!/bin/bash
# Copyright (C) 2017 Vincent Zvikaramba
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function sync_manifests {
    if [ "x$MANIFEST_NAME" == "x" ]; then
        MANIFEST_NAME=${DISTRIBUTION}-${ver}.xml
    fi
    manifest_dir=${BUILD_TOP}/.repo/local_manifests
    manifest_url="https://git.${arch}.com/Galaxy-${arch^^}/local_manifests.git/plain"
    local_manifest=${manifest_dir}/${MANIFEST_NAME}
    remote_manifest=${manifest_url}/${MANIFEST_NAME}

    logr "Manifest URL is: ${remote_manifest}"

    mkdir -p ${manifest_dir}
    logb "Removing old manifests..."
    rm ${manifest_dir}/*xml

    logb "Syncing manifests..."
    ${CURL} ${remote_manifest} | tee ${local_manifest} > /dev/null

    if [ "${arch}" == "msm8916" ]; then
        gerrit_port=29418
    elif [ "${arch}" == "msm8953" ]; then
        gerrit_port=29419
    fi

    if [ `hostname` == "msm8916.com" ]; then
        sed -i s/fetch=\"https:\\/\\/github.com\"/fetch=\"ssh:\\/\\/jenkins@review.${arch}.com:${gerrit_port}\"/g ${local_manifest}
    fi

    # Sync the substratum manifest
    if [ "x$ver" == "x14.1" ]; then
        logb "Syncing Substratum manifest..."
        mkdir -p ${manifest_dir}
        ${CURL} --output ${manifest_dir}/substratum.xml \
        https://raw.githubusercontent.com/LineageOMS/merge_script/master/substratum.xml
    fi
}

function sync_vendor_trees {
if [ -n "$SYNC_VENDOR" ]; then
    logb "Syncing vendor trees..."
    cd ${BUILD_TOP}

    repos=`cat ${local_manifest} |grep -o 'path="[a-z0-9\_\/\-]*"' | cut -d '=' -f 2 | sed s'/"//'g`

    repo sync $repos --force-sync --no-tags --no-clone-bundle --prune
fi
}

function sync_all_trees {
if [ -n "$SYNC_ALL" ]; then
    logb "Syncing all trees..."
    cd ${BUILD_TOP}

    # sync substratum if we're on LOS 14.1
    if [ "x$ver" == "x14.1" ]; then
        unsync_substratum
    fi

    repo sync --force-sync --no-tags --no-clone-bundle --prune

    # sync substratum if we're on LOS 14.1
    case $ver in
        14*)
            sync_substratum;
        ;;
        15* | oreo )
            REPOPICK_FILE=${BUILD_TEMP}/repopicks-${ver}.sh
            wget https://raw.githubusercontent.com/Galaxy-${arch^^}/repopicks/master/repopicks-${ver}.sh -O $REPOPICK_FILE
            if [ "$?" -eq 0 ]; then
                echoText "Picking Lineage gerrit changes..."
                . $REPOPICK_FILE
            fi
        ;;
    esac

    cd $OLDPWD
fi
}

function sync_script {
    logb "Updating build script..."
    if [ -z "$UPDATE_SCRIPT" ]; then
        ${CURL} ${SCRIPT_REPO_URL}/$(basename $0) | tee $0 > /dev/null
    else
        ${CURL} ${SCRIPT_REPO_URL}/$(basename $0) | tee $0 > /dev/null && exit || exit
    fi
    logb "Done."
}

function apply_repopicks {
    cd ${BUILD_TOP}
    gerrit_url="https://review.${arch}.com"

    #pick local gerrit changes
    [ -n "$LOCAL_REPO_PICKS" ] && repopick -g $gerrit_url -r $LOCAL_REPO_PICKS

    for topic in $LOCAL_REPO_TOPICS; do
        repopick -g $gerrit_url -r -t $topic
    done

    #pick lineage gerrit changes
    [ -n "$LINEAGE_REPO_PICKS" ] && repopick -r $LINEAGE_REPO_PICKS

    for topic in $LINEAGE_REPO_TOPICS; do
        repopick -r -t $topic
    done
}
