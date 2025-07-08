#!/bin/sh
set -e

export CDSDK_VERSION="${VERSION:-"^9"}"

. ${NVM_DIR}/nvm.sh

npm i -g @sap/cds-dk@${CDSDK_VERSION}
