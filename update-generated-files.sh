#! /bin/bash

nix run .#export-typescript-api src/ui/src/generated
nix run .#export-openapi-schema src/openapi/schema.json
