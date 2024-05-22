# Resolved Issues

# Description

# Review Checklists

Please check each item **before approving** the pull request. While going
through the checklist, it is recommended to leave comments on items that are
referenced in the checklist to make sure that they are reviewed. If there are
multiple reviewers, copy the checklists into sections titled `## [Reviewer Name]`.
If the PR doesn't touch Solidity, the corresponding checklist can
be removed.

## [[Reviewer Name]]

- [ ] **Tokens**
    - [ ] Do all `approve` calls use `forceApprove`?
    - [ ] Do all `transfer` calls use `safeTransfer`?
    - [ ] Do all `transferFrom` calls use `msg.sender` as the `from` address?
        - [ ] If not, is the function access restricted to prevent unauthorized
              token spend?
- [ ] **Low-level calls (`call`, `delegatecall`, `staticcall`, `transfer`, `send`)**
    - [ ] Is the returned `success` boolean checked to handle failed calls?
    - [ ] If using `delegatecall`, are there strict access controls on the
          addresses that can be called? It shouldn't be possible to `delegatecall`
          arbitrary addresses, so the list of possible targets should either be
          immutable or tightly controlled by an admin.
- [ ] **Reentrancy**
    - [ ] Are functions that make external calls or transfer ether marked as `nonReentrant`?
        - [ ] If not, is there documentation that explains why reentrancy is
              not a concern or how it's mitigated?
- [ ] **Gas Optimizations**
    - [ ] Is the logic as simple as possible?
    - [ ] Are the storage values that are used repeatedly cached in stack or
          memory variables?
    - [ ] If loops are used, are there guards in place to avoid out-of-gas
          issues?
- [ ] **Visibility**
    - [ ] Are all `payable` functions restricted to avoid stuck ether?
- [ ] **Math**
    - [ ] Is all of the arithmetic checked or guarded by if-statements that will
          catch underflows?
    - [ ] If `Safe` functions are altered, are potential underflows and
          overflows caught so that a failure flag can be thrown?
    - [ ] Are all of the rounding directions clearly documented?
- [ ] **Testing**
    - [ ] Are there new or updated unit or integration tests?
    - [ ] Do the tests cover the happy paths?
    - [ ] Do the tests cover the unhappy paths?
    - [ ] Are there an adequate number of fuzz tests to ensure that we are
          covering the full input space?
