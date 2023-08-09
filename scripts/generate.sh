#!/usr/bin/env bash

DEBUG=${DEBUG-false}
if [[ "$DEBUG" = "true" ]] || [[ "$DEBUG" = "1" ]]; then
    set -x
fi

function getTags() {
    TEMP=$(mktemp -d)
    FILTER=$1

    # Get the official image config, split them into separate temp files
    SOURCE="${SOURCE:-https://raw.githubusercontent.com/docker-library/official-images/master/library/${NAME}}"
    curl --silent --location --fail --retry 3 "${SOURCE}" | \
        awk -v TEMP="$TEMP" -v RS= '{ print > (TEMP"/image" ++CNT) }'

    # Parse each image definition individually.
    for FILE in "$TEMP"/*; do
        grep '^Tags\|^SharedTags' "${FILE}" |
            tr '\n' ';' |
            perl -pe 's/;SharedTags:/,/g;' -e 's/;/\n/g' |
            sort |
            sed 's/^.*Tags: //g' |
            grep -v -e alpine -e slim -e onbuild -e windows -e wheezy -e nanoserver -e alpha -e beta |
            ${FILTER} |
            sed 's/, /,/g'
    done

    # Clean up
    rm -rf "${TEMP}"
}

DIR="services/$1"

if [ -e "${DIR}/manifest" ]; then
    source "${DIR}/manifest"
fi

NAME=${NAME:-$1}
FROM=${FROM:-$NAME}
SERVICE=${SERVICE:-$NAME}
FILTER=${FILTER:-cat}
TEMPLATE=${TEMPLATE:-apt}
GETTAGS=${GETTAGS:-getTags}

SERVICEDIR="images/${SERVICE}"
mkdir -p "${SERVICEDIR}"

for TAGS in $($GETTAGS "${FILTER}"); do
    TAG=$(echo "${TAGS}" | cut -d, -f1)
    IMGDIR="${SERVICEDIR}/${TAG}"
    IMAGE="${FROM}:${TAG}"

    mkdir -p "${IMGDIR}"

    RUN=""
    if [ -e "${DIR}/run" ]; then
        cp "${DIR}/run" "${IMGDIR}/run"
        chmod 755 "${IMGDIR}/run"
        RUN="RUN mkdir -p /etc/service/${SERVICE}\nCOPY run /etc/service/${SERVICE}/run"
    fi

    DOCKERFILE=/dev/null
    if [ -e "${DIR}/Dockerfile" ]; then
        DOCKERFILE="${DIR}/Dockerfile"
    fi

    cp -r "${DIR}/../../share" "${IMGDIR}/"
    if [ -e "${DIR}/files" ]; then
        cp -r "${DIR}/files" "${IMGDIR}/"
    fi

    cat "templates/Dockerfile.${TEMPLATE}.template" | \
        sed "s|{{FROM}}|${IMAGE}|g" | \
        sed "/{{DOCKERFILE}}/ r ${DOCKERFILE}" | \
        sed "/{{DOCKERFILE}}/d" | \
        perl -pe "s|\{\{RUN\}\}|${RUN}|g" \
        > "${IMGDIR}/Dockerfile"

    echo "${TAGS}" | tr ',' ' ' > "${IMGDIR}/TAGS"
    echo "${NAME}" > "${IMGDIR}/NAME"
done
