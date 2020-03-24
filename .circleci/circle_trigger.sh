#!/bin/bash
set -e

# The root directory of packages.
# Use `.` if your packages are located in root.
ROOT="./packages" 
REPOSITORY_TYPE="github"
CIRCLE_API="https://circleci.com/api"

############################################
## 1. Commit SHA of last CI build
############################################
LAST_COMPLETED_BUILD_URL="${CIRCLE_API}/v1.1/project/${REPOSITORY_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/tree/${CIRCLE_BRANCH}?filter=completed&limit=100&shallow=true"
curl -Ss -u ${CIRCLE_TOKEN}: ${LAST_COMPLETED_BUILD_URL} > circle.json
LAST_COMPLETED_BUILD_SHA=`cat circle.json | jq -r '.[0]["vcs_revision"]'`

if  [[ ${LAST_COMPLETED_BUILD_SHA} == "null" ]]; then
  echo -e "\e[93mThere are no completed CI builds in branch ${CIRCLE_BRANCH}.\e[0m"

  # Adapted from https://gist.github.com/joechrysler/6073741
  TREE=$(git show-branch -a 2>/dev/null \
    | grep '\*' \
    | grep -v `git rev-parse --abbrev-ref HEAD` \
    | sed 's/.*\[\(.*\)\].*/\1/' \
    | sed 's/[\^~].*//' \
    | uniq)

  REMOTE_BRANCHES=$(git branch -r | sed 's/\s*origin\///' | tr '\n' ' ')
  PARENT_BRANCH=master
  for BRANCH in ${TREE[@]}
  do
    BRANCH=${BRANCH#"origin/"}
    if [[ " ${REMOTE_BRANCHES[@]} " == *" ${BRANCH} "* ]]; then
        echo "Found the parent branch: ${CIRCLE_BRANCH}..${BRANCH}"
        PARENT_BRANCH=$BRANCH
        break
    fi
  done

  echo "Searching for CI builds in branch '${PARENT_BRANCH}' ..."

  LAST_COMPLETED_BUILD_URL="${CIRCLE_API}/v1.1/project/${REPOSITORY_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/tree/${PARENT_BRANCH}?filter=completed&limit=100&shallow=true"
  LAST_COMPLETED_BUILD_SHA=`curl -Ss -u "${CIRCLE_TOKEN}:" "${LAST_COMPLETED_BUILD_URL}" \
    | jq -r "map(\
      select(.status == \"success\") | select(.workflows.workflow_name != \"ci\") | select(.build_num < ${CIRCLE_BUILD_NUM})) \
    | .[0][\"vcs_revision\"]"`
fi

if [[ ${LAST_COMPLETED_BUILD_SHA} == "null" ]]; then
  echo -e "\e[93mNo CI builds for branch ${PARENT_BRANCH}. Using master.\e[0m"
  LAST_COMPLETED_BUILD_SHA=master
fi

############################################
## 2. Changed packages
############################################
PACKAGES=$(ls ${ROOT} -l | grep ^d | awk '{print $9}')
echo "Searching for changes since commit [${LAST_COMPLETED_BUILD_SHA:0:7}] ..."

## The CircleCI API parameters object
PARAMETERS='"trigger":false'
COUNT=0

# Get the list of workflows in current branch for which the CI is currently in failed state
FAILED_WORKFLOWS=$(cat circle.json \
  | jq -r "map(select(.branch == \"${CIRCLE_BRANCH}\")) \
  | group_by(.workflows.workflow_name) \
  | .[] \
  | {workflow: .[0].workflows.workflow_name, status: .[0].status} \
  | select(.status == \"failed\") \
  | .workflow")

echo "Workflows currently in failed status: (${FAILED_WORKFLOWS[@]})."

for PACKAGE in ${PACKAGES[@]}
do
  PACKAGE_PATH=${ROOT#.}/$PACKAGE
  LATEST_COMMIT_SINCE_LAST_BUILD=$(git log -1 $LAST_COMPLETED_BUILD_SHA..$CIRCLE_SHA1 --format=format:%H --full-diff ${PACKAGE_PATH#/})

  if [[ -z "$LATEST_COMMIT_SINCE_LAST_BUILD" ]]; then
    INCLUDED=0
    for FAILED_BUILD in ${FAILED_WORKFLOWS[@]}
    do
      if [[ "$PACKAGE" == "$FAILED_BUILD" ]]; then
        INCLUDED=1
        PARAMETERS+=", \"$PACKAGE\":true"
        COUNT=$((COUNT + 1))
        echo -e "\e[36m  [+] ${PACKAGE} \e[21m (included because failed since last build)\e[0m"
        break
      fi
    done

    if [[ "$INCLUDED" == "0" ]]; then
      echo -e "\e[90m  [-] $PACKAGE \e[0m"
    fi
  else
    PARAMETERS+=", \"$PACKAGE\":true"
    COUNT=$((COUNT + 1))
    echo -e "\e[36m  [+] ${PACKAGE} \e[21m (changed in [${LATEST_COMMIT_SINCE_LAST_BUILD:0:7}])\e[0m"
  fi
done

if [[ $COUNT -eq 0 ]]; then
  echo -e "\e[93mNo changes detected in packages. Skip triggering workflows.\e[0m"
  exit 0
fi



echo "Changes detected in ${COUNT} package(s)."

############################################
## 3. CicleCI REST API call
############################################
DATA="{ \"branch\": \"$CIRCLE_BRANCH\", \"parameters\": { $PARAMETERS } }"
echo "Triggering pipeline with data:"
echo -e "  $DATA"

URL="${CIRCLE_API}/v2/project/${REPOSITORY_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/pipeline"
HTTP_RESPONSE=$(curl -s -u "${CIRCLE_TOKEN}:" -o response.txt -w "%{http_code}" -X POST --header "Content-Type: application/json" -d "$DATA" "$URL")

if [ "$HTTP_RESPONSE" -ge "200" ] && [ "$HTTP_RESPONSE" -lt "300" ]; then
    echo "API call succeeded."
    echo "Response:"
    cat response.txt
else
    echo -e "\e[93mReceived status code: ${HTTP_RESPONSE}\e[0m"
    echo "Response:"
    cat response.txt
    exit 1
fi
