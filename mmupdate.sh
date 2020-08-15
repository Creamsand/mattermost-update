#!/bin/bash

# mmupdate.sh
#
# Simple script for comfortable update of Mattermost
# https://github.com/creamsand/mattermost-update
#
# License: MIT
# Copyright (c) 2020 Creamsand
# Original https://github.com/hobbyquaker/mattermost-update by Sebastian Raff <hq@ccu.io> 

VERSION="2.0.2_custom"

MM_PATH=$1
TARBALL_URL=$2

command -v jq >/dev/null 2>&1 || { echo >&2 "jq がインストールされていません。  処理を中止します。"; exit 1; }
command -v wget >/dev/null 2>&1 || { echo >&2 "wget がインストールされていません。  処理を中止します。"; exit 1; }
command -v sudo >/dev/null 2>&1 || { echo >&2 "sudo がインストールされていません。  処理を中止します。"; exit 1; }

SWD=`pwd`

MM_CONFIG_FILE=${MM_PATH}/config/config.json
if [ ! -f ${MM_CONFIG_FILE} ]; then
    echo "エラー: $MM_CONFIG_FILE が見つかりません。  処理を中止します。"
    exit 1
fi

MM_CONFIG=`cat ${MM_CONFIG_FILE}`
DATA_DIR=`echo ${MM_CONFIG} | jq -r '.FileSettings.Directory' | sed -nr 's/^\.\/(.*)/\1/p'`

MM_USER=`ls -ld ${MM_PATH} | awk '{print $3}'`
MM_GROUP=`ls -ld ${MM_PATH} | awk '{print $4}'`

TARBALL_FILE=`echo ${TARBALL_URL} | sed -r 's#.*\/(.*)$#\1#'`
NEW_BUILD_NUMBER=`echo ${TARBALL_FILE} | sed -r 's/^mattermost-([0-9.]+).*/\1/'`

cd ${MM_PATH}
MM_BUILD_NUMBER=`sudo -u ${MM_USER} ${MM_PATH}/bin/platform version | sed -nr 's/Build Number: ([0-9.]+)/\1/p'`

if [ "$NEW_BUILD_NUMBER" == "$MM_BUILD_NUMBER" ]
then
    echo >&2 "Build $MM_BUILD_NUMBER は既にインストールされています。 処理を中止します。"
    exit 1
fi

BACKUP_TMP_PATH=/tmp/mattermost.backup.${MM_BUILD_NUMBER}
NEW_TMP_PATH=/tmp/mattermost.update.${NEW_BUILD_NUMBER}
mkdir ${BACKUP_TMP_PATH} 2> /dev/null
rm -r ${NEW_TMP_PATH} 2> /dev/null
mkdir ${NEW_TMP_PATH} 2> /dev/null

echo "   ダウンロード中... $TARBALL_URL"
cd ${NEW_TMP_PATH}
wget -q ${TARBALL_URL} || { echo >&2 "エラー: ダウンロード に失敗しました。  処理を中止します。"; exit 1; }
echo "   解凍しています... $TARBALL_FILE"
tar -xzf ${TARBALL_FILE} || { echo >&2 "エラー: 解凍 に失敗しました。  処理を中止します。"; exit 1; }
cd ${SWD}

function abort {
    echo "   tmpフォルダをクリーンアップ中..."
    rm -r ${NEW_TMP_PATH}
    rm -r ${BACKUP_TMP_PATH}

    echo "   Mattermostを起動中..."
    service mattermost start
    exit 1
}

echo "   Mattermostを停止中..."
service mattermost stop || { echo >&2 "処理を中止します。"; exit 1; }
BACKUP_FINAL_PATH=${MM_PATH}/backup/`date +%Y%m%d%H%M`_${MM_BUILD_NUMBER}

SQL_SETTINGS=`echo ${MM_CONFIG} | jq -r '.SqlSettings'`
DRIVER_NAME=`echo ${SQL_SETTINGS} | jq -r '.DriverName'`

if [ ${DRIVER_NAME} == "postgres" ]; then
    DATA_SOURCE=`echo ${SQL_SETTINGS} | jq -r '.DataSource'`
    DB_NAME=`echo ${DATA_SOURCE} | sed -r 's#.*\/\/([^?]+).*#\1#'`
    DB_DUMP_FILE=${BACKUP_TMP_PATH}/${DB_NAME}.pgdump.gz

    echo "   Dumping $DRIVER_NAME Database $DB_NAME to $DB_DUMP_FILE"
    cd ${MM_PATH}
    sudo -u ${MM_USER} pg_dump ${DB_NAME} | gzip > ${DB_DUMP_FILE} || { echo >&2 "エラー: Database dump に失敗しました。  処理を中止します。"; abort; }

elif [ ${DRIVER_NAME} == "mysql" ]; then # MySQL,MariaDBはこれ
    DATA_SOURCE=`echo ${SQL_SETTINGS} | jq -r '.DataSource'`
    DB_NAME=`echo ${DATA_SOURCE} | sed -r 's#.*\/\/([^?]+).*#\1#'`
    DB_DUMP_FILE=${BACKUP_TMP_PATH}/${DB_NAME}.pgdump.gz

    echo "   Dumping $DRIVER_NAME Database $DB_NAME to $DB_DUMP_FILE"
    cd ${MM_PATH}
    sudo mysqldump --single-transaction -u ${MM_USER} -p ${DB_NAME} | gzip > ${DB_DUMP_FILE} || { echo >&2 "エラー: Database dump に失敗しました。  処理を中止します。"; abort; }
else
    echo "エラー: 不明なデータベースドライバです。 $DRIVER_NAME"
    exit 1
fi

echo "   設定ファイル config.json を $BACKUP_TMP_PATH/config.json にバックアップ中..." || { echo >&2 "エラー: config.json バックアップ に失敗しました。  処理を中止します。"; abort; }
cp ${MM_PATH}/config/config.json ${BACKUP_TMP_PATH}/

echo "   ディレクトリ ${MM_PATH}/$DATA_DIR を $BACKUP_TMP_PATH/data.tar.gz にバックアップ中..."  || { echo >&2 "エラー: data バックアップ に失敗しました。  処理を中止します。"; abort; }
cd ${MM_PATH}
tar -acf ${BACKUP_TMP_PATH}/data.tar.gz ${DATA_DIR} # tar.gz以外にも対応させるためオプションを acf に変更
cd ${SWD}

echo "   $NEW_BUILD_NUMBER を $MM_PATH へコピー中..."
cp -r ${NEW_TMP_PATH}/mattermost/* ${MM_PATH}/

echo "   復元中... config.json"
cp ${BACKUP_TMP_PATH}/config.json ${MM_PATH}/config/

echo "   ${BACKUP_FINAL_PATH} へバックアップ中..."
mkdir -p ${BACKUP_FINAL_PATH} 2> /dev/null
cp -r ${BACKUP_TMP_PATH}/* ${BACKUP_FINAL_PATH}/

echo "   $MM_PATH の所有権を $MM_USER:$MM_GROUP に変更します。"
chown -R ${MM_USER}:${MM_GROUP} ${MM_PATH}

echo "   Mattermostを起動中..."
service mattermost start

echo "   tmpフォルダをクリーンアップ中..."
rm -r ${NEW_TMP_PATH}
rm -r ${BACKUP_TMP_PATH}

echo "完了しました。"
