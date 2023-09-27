#!/bin/bash

set -ex
wasm-pack build --target web

cd pkg
npm pack
rm -f ../example/hyperwasm-*.tgz
mv hyperwasm-*.tgz ../example/

cd ../example
npm uninstall hyperwasm
npm install ./hyperwasm-*.tgz
