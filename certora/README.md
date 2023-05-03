# Running the certora verification tool

These instructions detail the process for running Certora Prover.

Documentation for Certora Prover and the specification language are available
[here](https://docs.certora.com/en/latest/)

## Running the verification

The scripts in the `certora/scripts` directory are used to submit verification
jobs to the Certora verification service. These scripts should be run from the
root directory; for example by running

```sh
sh certora/scripts/verifyExampleContract.sh <arguments>
```

TODO: update example above, and add any special information for this customer's
setup

After the job is complete, the results will be available on
[the staging Certora portal](prover.certora.com) (by default, the
scripts run on our staging cloud).
