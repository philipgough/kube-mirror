#!/usr/bin/env bash

set -e -x -o pipefail

rm -rf examples
mkdir -p examples

jsonnet -J vendor -m examples "${1-example.jsonnet}" | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml' -- {}

# remove json files
find examples -type f ! -name '*.yaml' -delete

