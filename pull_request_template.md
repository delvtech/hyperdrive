# Resolved Issues

# Description

# Review Checklists

Please check each item **before approving** the pull request. While going
through the checklist, it is recommended to leave comments on items that are
referenced in the checklist to make sure that they are reviewed. If there are
multiple reviewers, copy the checklists into sections titled `## [Reviewer Name]`.
If the PR doesn't touch Solidity and/or Rust, the corresponding checklist can
be removed.

## [[Reviewer Name]]

### Solidity

- [ ] **Tokens**
    - [ ] Do all `approve` calls use `forceApprove`?
    - [ ] Do all `transfer` calls use `safeTransfer`?
    - [ ] Do all `transferFrom` calls use `msg.sender` as the `from` address?
        - [ ] If not, is the function access restricted to prevent unauthorized
              token spend?
- [ ] **Low-level calls (`call`, `delegatecall`, `staticcall`, `transfer`, `send`)**
    - [ ] Is the returned `success` boolean checked to handle failed calls?
    - [ ] If using `delegatecall`, which addresses can be called, and are there
          strict controls over this?
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
    - [ ] Are all `payable` function restricted to avoid stuck ether?
- [ ] **Math**
    - [ ] If `Safe` functions are altered, are potential underflows and
          overflows caught so that a failure flag can be thrown?
    - [ ] Are all of the rounding directions clearly documented?
- [ ] **Testing**
    - [ ] Are there new or updated unit or integration tests?
    - [ ] Do the tests cover the happy paths?
    - [ ] Do the tests cover the unhappy paths?
    - [ ] Are there an adequate number of fuzz tests to ensure that we are
          covering the full input space?

### Rust

- [ ] **Testing**
    - [ ] Are there new or updated unit or integration tests?
    - [ ] Do the tests cover the happy paths?
    - [ ] Do the tests cover the unhappy paths?
    - [ ] Are there an adequate number of fuzz tests to ensure that we are
          covering the full input space?
    - [ ] If matching Solidity behavior, are there differential fuzz tests that
          ensure that Rust matches Solidity?
