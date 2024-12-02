#!/bin/bash
# Copyright 2024 Apache Software Foundation (ASF)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

SCRIPT_DIR=$(dirname "${0}")

mkdir -p "${KN_WORK_DIR}"
cd "${KN_WORK_DIR}"

cp -v "${SCRIPT_DIR}/added/LICENSE" .

wget -q -P "${KN_WORK_DIR}" "${KN_ARTIFACT_URL}/amd64/linux/kn-workflow-linux-amd64"
wget -q -P "${KN_WORK_DIR}" "${KN_ARTIFACT_URL}/arm64/linux/kn-workflow-linux-arm64"
wget -q -P "${KN_WORK_DIR}" "${KN_ARTIFACT_URL}/amd64/windows/kn-workflow-windows-amd64.exe"
wget -q -P "${KN_WORK_DIR}" "${KN_ARTIFACT_URL}/amd64/macos/kn-workflow-darwin-amd64"
wget -q -P "${KN_WORK_DIR}" "${KN_ARTIFACT_URL}/arm64/macos/kn-workflow-darwin-arm64"

chmod +x kn-workflow-linux-amd64 kn-workflow-linux-arm64 kn-workflow-windows-amd64.exe kn-workflow-darwin-amd64 kn-workflow-darwin-arm64

tar --transform='flags=r;s|kn-workflow-linux-amd64|kn|' -zcf kn-workflow-linux-amd64.tar.gz kn-workflow-linux-amd64 LICENSE
tar --transform='flags=r;s|kn-workflow-linux-arm64|kn|' -zcf kn-workflow-linux-arm64.tar.gz kn-workflow-linux-arm64 LICENSE
tar --transform='flags=r;s|kn-workflow-darwin-amd64|kn|' -zcf kn-workflow-macos-amd64.tar.gz kn-workflow-darwin-amd64 LICENSE
tar --transform='flags=r;s|kn-workflow-darwin-arm64|kn|' -zcf kn-workflow-macos-arm64.tar.gz kn-workflow-darwin-arm64 LICENSE

mkdir "${KN_WORK_DIR}/windows" && mv kn-workflow-windows-amd64.exe "${KN_WORK_DIR}/windows/kn.exe" && cp LICENSE "${KN_WORK_DIR}/windows/" && zip -jrq kn-workflow-windows-amd64.zip "${KN_WORK_DIR}/windows"