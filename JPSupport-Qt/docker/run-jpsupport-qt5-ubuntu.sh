#!/bin/bash
# run-jpsupport-qt5-ubuntu.sh
#
# Ubuntu 24.04ベースの、Qt5版Lazarus(ソースビルド済み)環境を起動します。
# Dockerfile.ubuntu 側で全ビルドが完了しているため、このスクリプトは
# 起動するだけです(初回の docker build だけ時間がかかります)。
#
# どこから実行しても動くよう、スクリプト自身の場所からプロジェクト
# ルート(JPSupport-Qt/、このスクリプトの一段上)を自動計算します。
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_NAME="jpsupport-qt5-ubuntu"
CONTAINER_NAME="jpsupport-qt5-ubuntu"
USER_UID="$(id -u)"
USER_GID="$(id -g)"
USER_NAME="$(id -un)"

mkdir -p "${PROJECT_ROOT}/workspace"
xhost +local:docker >/dev/null 2>&1 || true

echo "[1/2] Building image ${IMAGE_NAME} (初回は時間がかかります) ..."
docker build \
    -f "${SCRIPT_DIR}/Dockerfile.ubuntu" \
    --build-arg USER_UID="${USER_UID}" \
    --build-arg USER_GID="${USER_GID}" \
    --build-arg USER_NAME="${USER_NAME}" \
    -t "${IMAGE_NAME}" \
    "${PROJECT_ROOT}"

echo "[2/2] Starting container ${CONTAINER_NAME} ..."
docker run -it --rm \
    --name "${CONTAINER_NAME}" \
    -e DISPLAY="${DISPLAY}" \
    -e QT_IM_MODULE=fcitx5 \
    -e GTK_IM_MODULE=fcitx5 \
    -e XMODIFIERS="@im=fcitx5" \
    -e XDG_RUNTIME_DIR="/run/user/${USER_UID}" \
    -e DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_UID}/bus" \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "/run/user/${USER_UID}/bus:/run/user/${USER_UID}/bus:rw" \
    -v "${PROJECT_ROOT}/workspace:/home/${USER_NAME}/workspace:rw" \
    --device /dev/dri:/dev/dri \
    "${IMAGE_NAME}"
