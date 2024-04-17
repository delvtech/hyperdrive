#!/bin/bash
rm -rf coverage_report
rm lcov.info
FOUNDRY_PROFILE=lite FOUNDRY_FUZZ_RUNS=100 forge coverage --report lcov
lcov --remove lcov.info  -o lcov.info 'test/*' 'script/*'
cat lcov.info | sed '/.*\/test\/.*/,/TN:/d' > tmp.info && mv tmp.info lcov.info
genhtml lcov.info -o coverage_report
google-chrome --headless --window-size=1200,800 --screenshot="coverage_report/coverage.png" "coverage_report/index.html"
