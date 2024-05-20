#!/bin/sh

if [[ -z "${NETWORK}" ]]; then
	echo 'Error: $NETWORK must be set'
	exit 1
fi

git remote update
tag=$(git describe --tags --abbrev=0)
diff=$(git diff ${tag} --raw)

if [[ "${NETWORK}" != "localhost" && "${NETWORK}" != "hardhat" && ! -z "${diff}" ]]; then
	echo "$diff"
	echo "Error: repository contents must match tag ${tag}"
	exit 1
fi

npx hardhat deploy:hyperdrive --show-stack-traces --network ${NETWORK}
npx hardhat deploy:verify --show-stack-traces --network ${NETWORK}
