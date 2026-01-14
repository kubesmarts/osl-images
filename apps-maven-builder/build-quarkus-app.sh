#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

# Parameters:
#   1 - Image name
#   2 - Quarkus platform group id
#   3 - Quarkus platform version
#   4 - Kogito version
#   5 - GAV of maven plugins to be injected in the plugin management section
#   6 - Properties to be replaced in the pom by the new versions
#   7 - Extra dependencies required for offline mode
# Note that all parameters are required and can't be empty

# fast fail
set -e
set -o pipefail

# Read entries before sourcing
image_name="${1}"
quarkus_platform_groupid="${2}"
quarkus_platform_version="${3}"
kogito_version="${KOGITO_VERSION:-${4}}"
maven_plugins_gav="${5}"
properties_with_versions="${6}"
quarkus_extensions_extra_deps="${7}"
quarkus_version="${8:-${quarkus_platform_version}}"

# common extensions used by the osl-swf-builder and osl-swf-devmode
quarkus_extensions="smallrye-health,org.apache.kie.sonataflow:sonataflow-quarkus:${kogito_version},org.kie:kie-addons-quarkus-knative-eventing:${kogito_version},org.kie:kogito-addons-quarkus-microprofile-config-service-catalog:${kogito_version},org.kie:kie-addons-quarkus-kubernetes:${kogito_version},org.kie:kogito-addons-quarkus-knative-serving:${kogito_version},org.kie:kie-addons-quarkus-process-management:${kogito_version},org.kie:kie-addons-quarkus-source-files:${kogito_version},org.kie:kie-addons-quarkus-monitoring-prometheus:${kogito_version},org.kie:kie-addons-quarkus-monitoring-sonataflow:${kogito_version}"
# dev mode purpose extensions used only by the osl-swf-devmode
osl_swf_devmode_extensions="org.apache.kie.sonataflow:sonataflow-quarkus-devui:${kogito_version},org.kie:kogito-addons-quarkus-jobs-service-embedded:${kogito_version},org.kie:kogito-addons-quarkus-data-index-inmemory:${kogito_version}"
# builder/prod extensions used only by the osl-swf-builder
osl_swf_builder_extensions="org.kie:kie-addons-quarkus-events-process:${kogito_version},org.kie:kogito-addons-quarkus-jobs-knative-eventing:${kogito_version}"

if [ -z ${quarkus_platform_version} ]; then
    echo "Please provide the quarkus version"
    exit 1
fi

case ${image_name} in
    "osl-swf-builder")
        quarkus_extensions="${quarkus_extensions},${osl_swf_builder_extensions},${quarkus_extensions_extra_deps}"
        # additional libraries not meant to be added to pom.xml
        osl_swf_builder_additional_libs="org.kie:kie-addons-quarkus-persistence-jdbc:${kogito_version},org.kie:kie-addons-quarkus-persistence-jdbc-deployment:${kogito_version},io.quarkus:quarkus-jdbc-postgresql:${quarkus_version},io.quarkus:quarkus-jdbc-postgresql-deployment:${quarkus_version}"
        ;;
    "osl-swf-devmode")
        quarkus_extensions="${quarkus_extensions},${osl_swf_devmode_extensions},${quarkus_extensions_extra_deps}"
        ;;
    *)
        echo "${image_name} is not a quarkus app image, exiting..."
        exit 0
        ;;
esac


target_tmp_dir="/tmp/build/${image_name}"
build_target_dir="/tmp/${image_name}"
mvn_local_repo="/tmp/temp_maven/${image_name}"

rm -rf ${target_tmp_dir} && mkdir -p ${target_tmp_dir}
rm -rf ${build_target_dir} && mkdir -p ${build_target_dir}
if [ "${CI}" = "true" ]; then
    # On CI we want to make sure we remove all artifacts from maven repo
    rm -rf ${mvn_local_repo}
fi
mkdir -p ${mvn_local_repo}

if [ "${NIGHTLY}" = "true" ]; then
    # In case of a nightly, the Kogito/Drools artifacts are not deployed anywhere, so they need to be copied
    # inside the maven repo local folder
    cp -rp ${NIGHTLY_DEPLOY_FOLDER}/* ${mvn_local_repo}
fi

# Setup the quarkus registries before creating the application
mkdir -p "${build_target_dir}/.quarkus"
cat > "${build_target_dir}/.quarkus/config.yaml" <<EOF
registries:
  - registry.quarkus.redhat.com
  - registry.quarkus.io
EOF

set -x
echo "Create quarkus project to path ${build_target_dir}"
cd ${build_target_dir}
mvn -B ${MAVEN_OPTIONS} \
    -Dmaven.repo.local=${mvn_local_repo} \
    -DprojectGroupId="org.acme" \
    -DprojectArtifactId="serverless-workflow-project" \
    -DprojectVersionId="1.0.0-SNAPSHOT" \
    -DplatformVersion="${quarkus_platform_version}" \
    -Dextensions="${quarkus_extensions}" \
    "${quarkus_platform_groupid}":quarkus-maven-plugin:"${quarkus_platform_version}":create

# Fix as we cannot rely on Quarkus platform
# Should be removed once https://issues.redhat.com/browse/KOGITO-9120 is implemented
if [ ! -z ${kogito_version} ]; then
    echo "Replacing Kogito Platform BOM with version ${kogito_version}"
    # [ ]* -> is a regexp pattern to match any number of spaces
    pattern_1="[ ]*<groupId>.*<\/groupId>"
    pattern_2="[ ]*<artifactId>quarkus-kogito-bom<\/artifactId>\n"
    pattern_3="[ ]*<version>.*<\/version>\n"
    complete_pattern="$pattern_1\n$pattern_2$pattern_3"

    replace_1="        <groupId>org.kie.kogito<\/groupId>\n"
    replace_2="        <artifactId>kogito-bom<\/artifactId>\n"
    replace_3="        <version>${kogito_version}<\/version>\n"
    complete_replace="$replace_1$replace_2$replace_3"

    sed -i.bak -e "/$pattern_1/{
        N;N;N
        s/$complete_pattern/$complete_replace/
        }" serverless-workflow-project/pom.xml
fi


# Inject empty plugin management section if not present in the pom.xml
if ! grep -q "<pluginManagement>" "serverless-workflow-project/pom.xml"; then
    echo "Injecting empty plugin Management section as it does not exist in pom"
    pattern_1="[ ]*<build>"
    complete_pattern="$pattern_1"

    replace_1="    <\build>\n"
    replace_2="        <pluginManagement>\n"
    replace_3="            <plugins>\n"
    replace_4="            <\/plugins>\n"
    replace_5="        <\/pluginManagement>"
    complete_replace="$replace_1$replace_2$replace_3$replace_4$replace_5"

    sed -i.bak -e "/$pattern_1/{
        N;N;N
        s/$complete_pattern/$complete_replace/
        }" serverless-workflow-project/pom.xml
fi

# Inject maven plugins into plugin management section
for gav in ${maven_plugins_gav[@]}; do
    group_id=$(echo $gav | cut -f1 -d:)
    artifact_id=$(echo $gav | cut -f2 -d:)
    version=$(echo $gav | cut -f3 -d:)

    echo "Injecting ${gav} in plugin management section"
    pattern_1="[ ]*<pluginManagement>"
    pattern_2="[ ]*<plugins>"
    complete_pattern="$pattern_1\n$pattern_2"

    replace_1="        <pluginManagement>\n"
    replace_2="            <plugins>\n"
    replace_3="                <plugin>\n"
    replace_4="                    <groupId>${group_id}<\/groupId>\n"
    replace_5="                    <artifactId>${artifact_id}<\/artifactId>\n"
    replace_6="                    <version>${version}<\/version>\n"
    replace_7="                <\/plugin>"
    complete_replace="$replace_1$replace_2$replace_3$replace_4$replace_5$replace_6$replace_7"

    sed -i.bak -e "/$pattern_1/{
        N;N;N
        s/$complete_pattern/$complete_replace/
        }" serverless-workflow-project/pom.xml
done

# Replace properties values by new values
for property_with_version in ${properties_with_versions[@]}; do
    property=$(echo $property_with_version | cut -f1 -d:)
    new_version=$(echo $property_with_version | cut -f2 -d:)

    echo "Replacing property ${property} with value ${new_version}"
    complete_pattern="<${property}>.*<\/${property}>"
    complete_replace="<${property}>${new_version}<\/${property}>"
    sed -i.bak "s/$complete_pattern/$complete_replace/g" serverless-workflow-project/pom.xml
done

#remove unnecessary files
rm -rfv serverless-workflow-project/target
# Workaround: Remove only application.properties as the greet.sw.json located in
# resources directory is required to exist for build to pass
rm -rfv serverless-workflow-project/src/main/resources/application.properties
rm -rfv serverless-workflow-project/src/main/docker
rm -rfv serverless-workflow-project/.mvn/wrapper
rm -rfv serverless-workflow-project/mvnw*
rm -rfv serverless-workflow-project/src/test
rm -rfv serverless-workflow-project/*.bak

echo "Build quarkus app"
cd "serverless-workflow-project"
# Quarkus version is enforced if some dependency pulled has older version of Quarkus set.
# This avoids to have, for example, Quarkus BOMs or other artifacts with multiple versions.

cp "pom.xml" "pom.bak"

# additional libraries (supports comma-separated list via xargs)
if [ ! -z "${osl_swf_builder_additional_libs}" ]; then
  echo "Adding additional dependencies (extensions): ${osl_swf_builder_additional_libs}"
  echo "${osl_swf_builder_additional_libs}" | tr ',' '\n' | \
    xargs -n1 -I{} \
      mvn -B ${MAVEN_OPTIONS} \
        -Dmaven.repo.local=${mvn_local_repo} \
        quarkus:add-extension \
        -Dextensions="{}"
fi

# 1) Build + install first (POM’s dependencies get recorded in the local cache)
mvn -B ${MAVEN_OPTIONS} \
   -Dmaven.repo.local=${mvn_local_repo} \
   clean install

# 2) Then let Quarkus finalize its offline cache (Quarkus’s “go-offline” goal)
mvn -B ${MAVEN_OPTIONS} \
   -Dmaven.repo.local=${mvn_local_repo} \
   "${quarkus_platform_groupid}":quarkus-maven-plugin:"${quarkus_platform_version}":go-offline

# 3) Populate transitive dependencies (Maven’s own “go-offline”)
mvn -B ${MAVEN_OPTIONS} \
   -Dmaven.repo.local=${mvn_local_repo} \
   dependency:go-offline

#clean up
mvn -B ${MAVEN_OPTIONS} \
  -nsu \
  -Dmaven.repo.local=${mvn_local_repo} \
  clean

mv "pom.bak" "pom.xml"

cd ${build_target_dir}


# Maven useless files
# Needed to avoid Maven to automatically re-download from original Maven repository ...
find ${mvn_local_repo} -name '_*.repositories' -type f -delete
find ${mvn_local_repo} -name *.lastUpdated -type f -delete

echo "Zip and copy scaffold project"
zip -r ${image_name}-quarkus-app.zip serverless-workflow-project/
cp -v ${image_name}-quarkus-app.zip ${target_tmp_dir}/
echo "Zip and copy maven repo"
cd ${mvn_local_repo}
zip -r ${image_name}-maven-repo.zip *
cp -v ${image_name}-maven-repo.zip ${target_tmp_dir}/