#!/bin/bash

# mmgeturl.sh
#
# Simple script for getting URL of Mattermost
# https://github.com/Creamsand/mattermost-update
#
# License: MIT
# Copyright (c) 2020 Creamsand

# 引数有りの場合,そのバージョン番号からURLを取得。引数なしの場合,バージョン番号を入力後、取得
if [ "$1" = '' ]; then
    echo -n "URLを取得したいバージョン番号を入力:"
    read $1
fi
get_ver=$1

# team edition および enterprise edition を除外したURLを取得
if [ "$get_ver" != '' ]; then
    curl https://docs.mattermost.com/administration/version-archive.html?src=dl 2> /dev/null | \
    sed -e 's/<[^>]*>//g' | \
    grep -E "https?://\S+?\.tar.gz" | \
    sed '/^GPG/d' | \
    grep "${get_ver}" | \
    grep -v -e "team" -e "enterprise"
fi