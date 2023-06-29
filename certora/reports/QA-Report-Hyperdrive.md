**Overview**

Risk Rating | Number of issues
--- | ---
Medium Risk | 1
Low Risk | 6
Informational | 23

**Summary**

- [1. Medium Issues](#1-medium-issues)
  - [1.1. Unsafe use of `transfer()`/`transferFrom()` with `IERC20`](#11-unsafe-use-of-transfertransferfrom-with-ierc20)
- [2. Low Issues](#2-low-issues)
  - [2.1. Benign re-entrancy in `StethHyperdrive._deposit()`](#21-benign-re-entrancy-in-stethhyperdrive_deposit)
  - [2.2. Flagging lack of Check-Effect-Interaction-Pattern involving state variables updates](#22-flagging-lack-of-check-effect-interaction-pattern-involving-state-variables-updates)
  - [2.3. Fees can be set to be greater than 100%](#23-fees-can-be-set-to-be-greater-than-100)
  - [2.4. Consider using the existing `SafeCast` library's `toUint128()` and adding a `toUint224()` to prevent unexpected overflows when casting from various type int/uint values](#24-consider-using-the-existing-safecast-librarys-touint128-and-adding-a-touint224-to-prevent-unexpected-overflows-when-casting-from-various-type-intuint-values)
  - [2.5. Missing checks for `address(0)` when assigning values to address state variables](#25-missing-checks-for-address0-when-assigning-values-to-address-state-variables)
  - [2.6. Return values of `transfer()`/`transferFrom()` not checked](#26-return-values-of-transfertransferfrom-not-checked)
- [3. Informational Issues](#3-informational-issues)
  - [3.1. Return values of `approve()` not checked](#31-return-values-of-approve-not-checked)
  - [3.2. `require()` should be used instead of `assert()`](#32-require-should-be-used-instead-of-assert)
  - [3.3. Use `string.concat()` or `bytes.concat()` instead of `abi.encodePacked`](#33-use-stringconcat-or-bytesconcat-instead-of-abiencodepacked)
  - [3.4. Contracts should have full test coverage](#34-contracts-should-have-full-test-coverage)
  - [3.5. Consider using `delete` rather than assigning zero to clear values](#35-consider-using-delete-rather-than-assigning-zero-to-clear-values)
  - [3.6. Function ordering does not follow the Solidity style guide](#36-function-ordering-does-not-follow-the-solidity-style-guide)
  - [3.7. Change uint to uint256](#37-change-uint-to-uint256)
  - [3.8. Lack of checks in setters](#38-lack-of-checks-in-setters)
  - [3.9. `type(uint256).max` should be used instead of `2 ** 256 - 1`](#39-typeuint256max-should-be-used-instead-of-2--256---1)
  - [3.10. Missing Event for critical parameters change](#310-missing-event-for-critical-parameters-change)
  - [3.11. Incomplete NatSpec: `@return` is missing on actually documented functions](#311-incomplete-natspec-return-is-missing-on-actually-documented-functions)
  - [3.12. Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor](#312-use-a-modifier-instead-of-a-requireif-statement-for-a-special-msgsender-actor)
  - [3.13. Constant state variables defined more than once](#313-constant-state-variables-defined-more-than-once)
  - [3.14. Consider using named mappings](#314-consider-using-named-mappings)
  - [3.15. Adding a `return` statement when the function defines a named return variable, is redundant](#315-adding-a-return-statement-when-the-function-defines-a-named-return-variable-is-redundant)
  - [3.16. Take advantage of Custom Error's return value property](#316-take-advantage-of-custom-errors-return-value-property)
  - [3.17. "Unused Return"](#317-unused-return)
  - [3.18. Contract does not follow the Solidity style guide's suggested layout ordering](#318-contract-does-not-follow-the-solidity-style-guides-suggested-layout-ordering)
  - [3.19. Use Underscores for Number Literals (add an underscore every 3 digits)](#319-use-underscores-for-number-literals-add-an-underscore-every-3-digits)
  - [3.20. Internal and private variables and functions names should begin with an underscore](#320-internal-and-private-variables-and-functions-names-should-begin-with-an-underscore)
  - [3.21. Usage of floating `pragma` is not recommended](#321-usage-of-floating-pragma-is-not-recommended)
  - [3.22. Variables need not be initialized to zero](#322-variables-need-not-be-initialized-to-zero)
  - [3.23. The following unchecked statements are not documented](#323-the-following-unchecked-statements-are-not-documented)

## 1. Medium Issues

### 1.1. Unsafe use of `transfer()`/`transferFrom()` with `IERC20`

Sources:

- <https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca>
- <https://code4rena.com/reports/2022-07-juicebox#m-03-use-a-safe-transfer-helper-library-for-erc20-transfers>

Some tokens (like BNB or USDT) do not implement the ERC20 standard properly but are still accepted by most code that accepts ERC20 tokens. For example Tether (USDT)'s `transfer()` and `transferFrom()` functions on L1 do not return booleans as the specification requires, and instead have no return value: <https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7#code#L126>.
When these sorts of tokens are cast to `IERC20`, their function signatures do not match and therefore the calls made, revert.
Consider using OpenZeppelin's `SafeERC20`'s `safeTransfer()`/`safeTransferFrom()` instead as `SafeERC20` ensures consistent handling of ERC20 return values and abstract over inconsistent ERC20 implementations.

- [contracts/src/token/BondWrapper.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/BondWrapper.sol)

```solidity
File: BondWrapper.sol
33:     constructor(
34:         IHyperdrive _hyperdrive,
35:         IERC20 _token, //@audit IERC20
36:         uint256 _mintPercent,
37:         string memory name_,
38:         string memory symbol_
39:     ) ERC20(name_, symbol_, 18) {
...
53:         // Set the immutables
54:         hyperdrive = _hyperdrive;
55:         token = _token; //@audit IERC20
56:         mintPercent = _mintPercent;
57:     }
...
097:     function close(
...
147:         // Transfer the released funds to the user
148:         bool success = token.transfer(destination, userFunds); //@audit will revert with USDT
File: BondWrapper.sol
...
178:     function redeem(uint256 amount) public {
...
183:         bool success = token.transfer(msg.sender, amount); //@audit will revert with USDT
184:         if (!success) revert Errors.TransferFailed();
185:     }
```

Simplified POC:

```solidity
pragma solidity 0.8.19;

interface IERC20 {
  function transfer(address to, uint value) external returns (bool);
}

contract BadERC20 {
    function transfer(address, uint) external pure {
        return;
    }
}

contract Test {
    function testIt() external {
        BadERC20 bad = new BadERC20();
        
        //BadERC20(address(bad)).transfer(address(this), 0); // works
        IERC20(address(bad)).transfer(address(this), 0); // doesn't work - reverts
    }
}
```

## 2. Low Issues

### 2.1. Benign re-entrancy in `StethHyperdrive._deposit()`

**Impact:**

While it's possible to re-enter the function, it seems like the current impact is benign (equivalent to consecutive calls). 
However, giving away the control flow shouldn't be possible. Consider adding a `nonReentrant` modifier on all entrypoints of the system.

Here, `_pricePerShare()` is called after the dangerous call to `payable(msg.sender).call()` which can re-enter, meaning that if a path is found to manipulate `_pricePerShare()`, this re-entrancy's impact could be higher.

**POC:**

The following code makes a benign re-entrancy possible:

```solidity
File: StethHyperdrive.sol
62:     function _deposit(
63:         uint256 _amount,
64:         bool _asUnderlying
65:     ) internal override returns (uint256 shares, uint256 sharePrice) {
66:         if (_asUnderlying) {
67:             // Ensure that sufficient ether was provided and refund any excess.
68:             if (msg.value < _amount) {
69:                 revert Errors.TransferFailed();
70:             }
71:             if (msg.value > _amount) {
72:                 // Return excess ether to the user.
73:                 (bool success, ) = payable(msg.sender).call{ //@audit possible re-entrancy
74:                     value: msg.value - _amount
75:                 }("");
76:                 if (!success) {
77:                     revert Errors.TransferFailed();
78:                 }
79:             }
```

Apply the following code diff for a POC:

```diff
diff --git a/contracts/src/instances/StethHyperdrive.sol b/contracts/src/instances/StethHyperdrive.sol
index 517bc81..3a50ac7 100644
--- a/contracts/src/instances/StethHyperdrive.sol
+++ b/contracts/src/instances/StethHyperdrive.sol
@@ -7,6 +7,7 @@ import { ILido } from "../interfaces/ILido.sol";
 import { IWETH } from "../interfaces/IWETH.sol";
 import { Errors } from "../libraries/Errors.sol";
 import { FixedPointMath } from "../libraries/FixedPointMath.sol";
+import "forge-std/console.sol";
 
 /// @author DELV
 /// @title StethHyperdrive
@@ -69,6 +70,7 @@ contract StethHyperdrive is Hyperdrive {
                 revert Errors.TransferFailed();
             }
             if (msg.value > _amount) {
+                console.log("_pricePerShare() 1: %s", _pricePerShare());
                 // Return excess ether to the user.
                 (bool success, ) = payable(msg.sender).call{
                     value: msg.value - _amount
@@ -86,6 +88,7 @@ contract StethHyperdrive is Hyperdrive {
 
             // Calculate the share price.
             sharePrice = _pricePerShare();
+            console.log("_pricePerShare() 2: %s", _pricePerShare());
         } else {
             // Ensure that the user didn't send ether to the contract.
             if (msg.value > 0) {
@@ -105,7 +108,11 @@ contract StethHyperdrive is Hyperdrive {
             // Calculate the share price and the amount of shares deposited.
             sharePrice = _pricePerShare();
             shares = _amount.divDown(sharePrice);
+                console.log("_pricePerShare() 3: %s", _pricePerShare());
+                console.log("shares() 3: %s", shares);
+
         }
+         console.log("return (shares = %s, sharePrice = %s)", shares, sharePrice);
 
         return (shares, sharePrice);
     }

diff --git a/test/integrations/StethHyperdrive.t.sol b/test/integrations/StethHyperdrive.t.sol
index 4d346e3..7407bda 100644
--- a/test/integrations/StethHyperdrive.t.sol
+++ b/test/integrations/StethHyperdrive.t.sol
@@ -16,6 +16,60 @@ import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
 import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
 import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
 import { Lib } from "test/utils/Lib.sol";
+import "forge-std/console.sol";
+
+contract AttackerContract {
+    StethHyperdrive public instance;
+    uint256 reentrancyCounter;
+    bool shouldAttack = true;
+
+    constructor(address _instance) {
+        instance = StethHyperdrive(_instance);
+        console.log(
+            "\n# Deployed Attacker contract with instance: %s #\n",
+            _instance
+        );
+    }
+
+    function attack() public returns (uint) {
+        console.log("\n# Starting the Attack #\n");
+        instance.openLong{ value: 1.1 ether }(1 ether, 0, address(this), true);
+        console.log("\n# Finished the Attack #\n");
+    }
+
+    function normalLoop() public returns (uint) {
+        console.log("\n# Opening Several Long Positions #\n");
+        shouldAttack = false;
+        instance.openLong{ value: 1.1 ether }(1 ether, 0, address(this), true);
+        for (uint i = 0; i < 5; ++i) {
+            console.log("Loop index: %s", i);
+            instance.openLong(1 ether, 0, address(this), false);
+            instance.openLong{ value: 1.1 ether }(
+                1 ether,
+                0,
+                address(this),
+                true
+            );
+        }
+        shouldAttack = true;
+        console.log("\n# Finished Opening Several Long Positions #\n");
+    }
+
+    fallback(bytes calldata _data) external payable returns (bytes memory) {
+        if (reentrancyCounter < 5 && shouldAttack) {
+            console.log("\n# Inside Attacker's Fallback #\n");
+            console.log("Attacking.reentrancyCounter: %s", reentrancyCounter);
+            ++reentrancyCounter;
+            instance.openLong(1 ether, 0, address(this), false);
+            instance.openLong{ value: 1.1 ether }(
+                1 ether,
+                0,
+                address(this),
+                true
+            );
+        }
+    }
+}
 
 contract StethHyperdriveTest is HyperdriveTest {
     using FixedPointMath for uint256;
@@ -33,6 +87,7 @@ contract StethHyperdriveTest is HyperdriveTest {
 
     address internal STETH_WHALE = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
     address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
+    address payable internal ATTACKER;
 
     function setUp() public override __mainnet_fork(17_376_154) {
         super.setUp();
@@ -88,12 +143,34 @@ contract StethHyperdriveTest is HyperdriveTest {
             1e5
         );
 
+        // Deploy Attacker
+        ATTACKER = payable(new AttackerContract(address(hyperdrive)));
+
         // Fund the test accounts with stETH and ETH.
-        address[] memory accounts = new address[](3);
+        address[] memory accounts = new address[](4);
         accounts[0] = alice;
         accounts[1] = bob;
         accounts[2] = celine;
+        accounts[3] = ATTACKER;
         fundAccounts(address(hyperdrive), IERC20(LIDO), STETH_WHALE, accounts);
+        deal(ATTACKER, 10_000_000 ether);
+    }
+
+    function test_reentrancy_open_long_with_ETH() external {
+        console.log(
+            "Initial Lido balance from Attacker: %s",
+            LIDO.balanceOf(ATTACKER)
+        );
+        console.log(
+            "Initial Ether balance from Attacker: %s",
+            ATTACKER.balance
+        );
+        uint256 snapshotId = vm.snapshot();
+
+        AttackerContract(ATTACKER).normalLoop();
+        vm.revertTo(snapshotId);
+
+        AttackerContract(ATTACKER).attack();
     }
```

Which will output the following logs on `forge test --mt test_reentrancy_open_long_with_ETH -vv`:

```
Running 1 test for test/integrations/StethHyperdrive.t.sol:StethHyperdriveTest
[PASS] test_reentrancy_open_long_with_ETH() (gas: 2319279)
Logs:
  _pricePerShare() 2: 1126467900855209627
  return (shares = 8877305773567131948929, sharePrice = 1126467900855209627)
  
# Deployed Attacker contract with instance: 0xe987e53ebe3F69D0292d0c410e5912077a5e27B8 #

  Initial Lido balance from Attacker: 239835683389301336443497
  Initial Ether balance from Attacker: 10000000000000000000000000
  
# Opening Several Long Positions #

  _pricePerShare() 1: 1126467900855209627
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  Loop index: 0
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  Loop index: 1
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  Loop index: 2
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  Loop index: 3
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  Loop index: 4
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  
# Finished Opening Several Long Positions #

  
# Starting the Attack #

  _pricePerShare() 1: 1126467900855209627
  
# Inside Attacker's Fallback #

  Attacking.reentrancyCounter: 0
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  
# Inside Attacker's Fallback #

  Attacking.reentrancyCounter: 1
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  
# Inside Attacker's Fallback #

  Attacking.reentrancyCounter: 2
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  
# Inside Attacker's Fallback #

  Attacking.reentrancyCounter: 3
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  
# Inside Attacker's Fallback #

  Attacking.reentrancyCounter: 4
  _pricePerShare() 3: 1126467900855209627
  shares() 3: 887730577356713195
  return (shares = 887730577356713195, sharePrice = 1126467900855209627)
  _pricePerShare() 1: 1126467900855209627
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  _pricePerShare() 2: 1126467900855209627
  return (shares = 887730577356713194, sharePrice = 1126467900855209627)
  
# Finished the Attack #


Test result: ok. 1 passed; 0 failed; finished in 3.54s
```

### 2.2. Flagging lack of Check-Effect-Interaction-Pattern involving state variables updates

- [DsrHyperdrive.totalShares](contracts/src/instances/DsrHyperdrive.sol#16) can be used in cross function reentrancies
  - [DsrHyperdrive._deposit()](contracts/src/instances/DsrHyperdrive.sol#61-96) updates `totalShares` after the following external calls:

```solidity
70:         bool success = _baseToken.transferFrom( //@audit ext call
71:             msg.sender,
72:             address(this),
73:             amount
74:         );
...
80:         uint256 totalBase = dsrManager.daiBalance(address(this)); //@audit ext call
...
83:         dsrManager.join(address(this), amount); //@audit ext call
...
88:             totalShares = amount;//@audit updated after ext call 
...
93:             totalShares += newShares;//@audit updated after ext call 
```

- [DsrHyperdrive._withdraw()](contracts/src/instances/DsrHyperdrive.sol#104-135) updates `totalShares` after the following external calls:

```solidity
File: DsrHyperdrive.sol
123:         uint256 totalBase = dsrManager.daiBalance(address(this)); //@audit ext call
...
129:         totalShares -= shares; //@audit updated after ext call 
```

- [AaveHyperdrive._deposit()](contracts/src/instances/AaveHyperdrive.sol#54-88):

```solidity
    uint256 assets = aToken.balanceOf(address(this)); //@audit ext call

    if (asUnderlying) {
        // Transfer from user
        bool success = _baseToken.transferFrom( //@audit ext call
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert Errors.TransferFailed();
        }
        // Supply for the user
        pool.supply(address(_baseToken), amount, address(this), 0); //@audit ext call
    } else {
        // aTokens are known to be revert on failed transfer tokens
        aToken.transferFrom(msg.sender, address(this), amount); //@audit ext call
    }

    // Do share calculations
    uint256 totalShares_ = totalShares;
    if (totalShares_ == 0) {
        totalShares = amount; //@audit updated after ext call 
        return (amount, FixedPointMath.ONE_18);
    } else {
        uint256 newShares = totalShares_.mulDivDown(amount, assets);
        totalShares += newShares; //@audit updated after ext call 
        return (newShares, _pricePerShare()); 
    }
```

- [AaveHyperdrive._withdraw()](contracts/src/instances/AaveHyperdrive.sol#110-120)

```solidity
110:         uint256 assets = aToken.balanceOf(address(this)); // @audit External call
             uint256 withdrawValue = assets != 0
                 ? shares.mulDown(assets.divDown(totalShares_))
                 : 0;
     
             if (withdrawValue == 0) {
                 revert Errors.NoAssetsToWithdraw();
             }
     
             // Remove the shares from the total share supply
             totalShares -= shares; // @audit State update without CEIP
```

- [BondWrapper.close()](contracts/src/token/BondWrapper.sol#97-150):

```solidity
            // Close the bond [selling if earlier than the expiration]
            receivedAmount = hyperdrive.closeLong( //@audit ext call
                maturityTime,
                amount,
                0,
                address(this),
                true
            );
        } else {
            // Sell all assets
            sweep(maturityTime); //@audit ext call
            // Sweep guarantees 1 to 1 conversion so the user gets exactly the amount they are closing
            receivedAmount = amount;
        }
        // Update the user balances
        deposits[msg.sender][assetId] -= amount;//@audit updated after ext call 
...
        // If the user would also like to burn the erc20 from their wallet
        if (andBurn) {
            _burn(msg.sender, mintedFromBonds);//@audit updated after ext call 
            userFunds += mintedFromBonds;
        }
...
    function sweep(uint256 maturityTime) public {
...
        if (balance != 0) {
            hyperdrive.closeLong( //@audit ext call
                maturityTime,
                balance,
                balance,
                address(this),
                true
            );
        }
    }
```

- [AaveHyperdriveFactory.deployAndInitialize()](contracts/src/factory/AaveHyperdriveFactory.sol#55-92):

```solidity
File: AaveHyperdriveFactory.sol
55:     function deployAndInitialize(
...
71:         IPool pool = IAaveDeployer(address(hyperdriveDeployer)).pool(); //@audit ext call
72:         address aToken = pool
73:             .getReserveData(address(_config.baseToken)) //@audit ext call
74:             .aTokenAddress;
...
83:         return
84:             super.deployAndInitialize(//@audit updated after ext call 
85:                 _config,
86:                 _linkerCodeHash,
87:                 _linkerFactory,
88:                 extraData,
89:                 _contribution,
90:                 _apr
91:             );
92:     }

```

- [HyperdriveFactory.deployAndInitialize()](contracts/src/factory/HyperdriveFactory.sol#134-201):

```solidity
File: HyperdriveFactory.sol
134:     function deployAndInitialize(
...
157:         IHyperdrive hyperdrive = IHyperdrive(
158:             hyperdriveDeployer.deploy( //@audit ext call
159:                 _config,
160:                 dataProvider,
161:                 _linkerCodeHash,
162:                 _linkerFactory,
163:                 _extraData
164:             )
165:         );
166: 
167:         // We only do ERC20 transfers when we deploy an ERC20 pool
168:         if (address(_config.baseToken) != ETH) {
169:             // Initialize the Hyperdrive instance.
170:             _config.baseToken.transferFrom( //@audit ext call
171:                 msg.sender,
172:                 address(this),
173:                 _contribution
174:             );
175:             _config.baseToken.approve(address(hyperdrive), type(uint256).max); //@audit ext call
176:             hyperdrive.initialize(_contribution, _apr, msg.sender, true); //@audit ext call
177:         } else {
178:             // Require the caller sent value
179:             if (msg.value != _contribution) {
180:                 revert Errors.TransferFailed();
181:             }
182:             hyperdrive.initialize{ value: _contribution }( //@audit ext call sending eth
183:                 _contribution,
184:                 _apr,
185:                 msg.sender,
186:                 true
187:             );
188:         }
189: 
190:         // Setup the pausers roles from the default array
191:         for (uint256 i = 0; i < defaultPausers.length; i++) {
192:             hyperdrive.setPauser(defaultPausers[i], true); //@audit ext call updating an external state var
193:         }
194:         // Reset governance to be the default one
195:         hyperdrive.setGovernance(hyperdriveGovernance); //@audit ext call updating an external state var
196: 
197:         // Mark as a version
198:         isOfficial[address(hyperdrive)] = versionCounter; //@audit updated after ext call 
199: 
200:         return (hyperdrive);
201:     }
```

- [BondWrapper.mint()](contracts/src/token/BondWrapper.sol#63-86):

```solidity
63:     function mint(
...
77:         // Transfer from the user
78:         hyperdrive.transferFrom(assetId, msg.sender, address(this), amount); //@audit ext call
79: 
80:         // Mint them the tokens for their deposit
81:         uint256 mintAmount = (amount * mintPercent) / 10000;
82:         _mint(destination, mintAmount);//@audit updated after ext call 
83: 
84:         // Add this to the deposited amount
85:         deposits[destination][assetId] += amount;//@audit updated after ext call 
86:     }
```

### 2.3. Fees can be set to be greater than 100%

There should be an upper limit to reasonable fees.
A malicious owner can keep the fee rate at zero, but if a large value transfer enters the mempool, the owner can jack the rate up to the maximum and sandwich attack a user.

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: HyperdriveFactory.sol
106:     /// @notice Allows governance to change the fee schedule for the newly deployed factories
107:     /// @param newFees The fees for all newly deployed contracts
108:     function updateFees(
109:         IHyperdrive.Fees calldata newFees
110:     ) external onlyGovernance {
111:         // Update the fee struct
112:         fees = newFees;
113:     }
```

### 2.4. Consider using the existing `SafeCast` library's `toUint128()` and adding a `toUint224()` to prevent unexpected overflows when casting from various type int/uint values

The existing `SafeCast` library has a `toUint128()` function:

```solidity
File: SafeCast.sol
08:     function toUint128(uint256 x) internal pure returns (uint128 y) {
09:         require(x < 1 << 128);
10: 
11:         y = uint128(x);
12:     }
```

The unsafe casting instances that aren't using it:

- [contracts/src/HyperdriveLP.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveLP.sol)

```solidity
File: contracts/src/HyperdriveLP.sol

320:         _withdrawPool.readyToWithdraw -= uint128(_shares);

321:         _withdrawPool.proceeds -= uint128(shareProceeds);

532:         _withdrawPool.readyToWithdraw += uint128(sharesReleased);

533:         _withdrawPool.proceeds += uint128(withdrawalPoolProceeds);
```

- [contracts/src/HyperdriveTWAP.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveTWAP.sol)
*Note: uint32 is safe until year 2106*

```solidity
File: contracts/src/HyperdriveTWAP.sol

48:         _buffer[toUpdate] = OracleData(uint32(block.timestamp), uint224(sum));

50:             uint128(toUpdate),
```

### 2.5. Missing checks for `address(0)` when assigning values to address state variables

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: HyperdriveFactory.sol
56:         governance = _governance;
57:         hyperdriveDeployer = _deployer;
59:         hyperdriveGovernance = _hyperdriveGovernance;
60:         feeCollector = _feeCollector;

85:         governance = newGovernance;

94:         hyperdriveGovernance = newGovernance;

103:         feeCollector = newFeeCollector;
```

- [contracts/src/HyperdriveBase.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveBase.sol)

```solidity
File: HyperdriveBase.sol
158:     function setGovernance(address who) external {
159:         if (msg.sender != _governance) revert Errors.Unauthorized();
160:         _governance = who;
161:     }
```

- [contracts/src/token/MultiTokenStorage.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/MultiTokenStorage.sol)

```solidity
File: MultiTokenStorage.sol
44:         _factory = _factory_;
```

- [contracts/src/DataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/DataProvider.sol)

```solidity
File: DataProvider.sol
19:         dataProvider = _dataProvider;
```

### 2.6. Return values of `transfer()`/`transferFrom()` not checked

While [`AToken`s](https://github.com/aave/aave-protocol/blob/master/contracts/tokenization/AToken.sol) seem to indeed revert when there's a failure in `transfer()`/`transferFrom()`, the function signature still has a `boolean` return value that indicates that everything went well. To avoid any potential silent failure, it's best to check that `success == true`

- [contracts/src/instances/AaveHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/AaveHyperdrive.sol)

```solidity
File: contracts/src/instances/AaveHyperdrive.sol

75:             aToken.transferFrom(msg.sender, address(this), amount);

128:             aToken.transfer(destination, withdrawValue);
```

Note that this is indeed done elsewhere in the codebase:

- [contracts/src/instances/ERC4626Hyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/ERC4626Hyperdrive.sol)

```solidity
File: contracts/src/instances/ERC4626Hyperdrive.sol

86:             bool success = IERC20(address(pool)).transferFrom(

115:             bool success = IERC20(address(pool)).transfer(destination, shares);
```

- [contracts/src/token/BondWrapper.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/BondWrapper.sol)

```solidity
File: contracts/src/token/BondWrapper.sol

148:         bool success = token.transfer(destination, userFunds);

183:         bool success = token.transfer(msg.sender, amount);
```

## 3. Informational Issues

### 3.1. Return values of `approve()` not checked

Not all IERC20 implementations `revert()` when there's a failure in `approve()`. The function signature has a boolean return value and they indicate errors that way instead. By not checking the return value, operations that should have marked as failed, may potentially go through without actually approving anything

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

175:             _config.baseToken.approve(address(hyperdrive), type(uint256).max);
```

- [contracts/src/instances/AaveHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/AaveHyperdrive.sol)

```solidity
File: contracts/src/instances/AaveHyperdrive.sol

45:         _config.baseToken.approve(address(pool), type(uint256).max);
```

- [contracts/src/instances/DsrHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdrive.sol)

```solidity
File: contracts/src/instances/DsrHyperdrive.sol

52:         _baseToken.approve(address(dsrManager), type(uint256).max);
```

- [contracts/src/instances/ERC4626Hyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/ERC4626Hyperdrive.sol)

```solidity
File: contracts/src/instances/ERC4626Hyperdrive.sol

51:         _config.baseToken.approve(address(pool), type(uint256).max);
```

### 3.2. `require()` should be used instead of `assert()`

Prior to solidity version 0.8.0, hitting an assert consumes the **remainder of the transaction's available gas** rather than returning it, as `require()`/`revert()` do. `assert()` should be avoided even past solidity version 0.8.0 as its [documentation](https://docs.soliditylang.org/en/v0.8.14/control-structures.html#panic-via-assert-and-error-via-require) states that "The assert function creates an error of type Panic(uint256). ... Properly functioning code should never create a Panic, not even on invalid external input. If this happens, then there is a bug in your contract which you should fix". Additionally, a require statement (or a custom error) are more friendly in terms of understanding what happened.

- [contracts/src/token/ForwarderFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/ForwarderFactory.sol)

```solidity
File: contracts/src/token/ForwarderFactory.sol

49:         assert(address(deployed) == getForwarder(token, tokenId));
```

### 3.3. Use `string.concat()` or `bytes.concat()` instead of `abi.encodePacked`

Solidity version 0.8.4 introduces `bytes.concat()` (vs `abi.encodePacked(<bytes>,<bytes>)`)

Solidity version 0.8.12 introduces `string.concat()` (vs `abi.encodePacked(<str>,<str>)`)

- [contracts/src/token/ERC20Forwarder.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/ERC20Forwarder.sol)

```solidity
File: contracts/src/token/ERC20Forwarder.sol

202:             abi.encodePacked(
```

- [contracts/src/token/ForwarderFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/ForwarderFactory.sol)

```solidity
File: contracts/src/token/ForwarderFactory.sol

74:             abi.encodePacked(bytes1(0xff), address(this), salt, ERC20LINK_HASH)
```

- [contracts/src/token/MultiToken.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/MultiToken.sol)

```solidity
File: contracts/src/token/MultiToken.sol

77:             abi.encodePacked(bytes1(0xff), _factory, salt, _linkerCodeHash)

293:             abi.encodePacked(
```

### 3.4. Contracts should have full test coverage

While 100% code coverage does not guarantee that there are no bugs, it often will catch easy-to-find bugs, and will ensure that there are fewer regressions when the code invariably has to be modified. Furthermore, in order to get full coverage, code authors will often have to re-organize their code so that it is more modular, so that each component can be tested separately, which reduces interdependencies between modules and layers, and makes for code that is easier to reason about and audit.

```solidity
| File                                                    | % Lines           | % Statements       | % Branches       | % Funcs          |
|---------------------------------------------------------|-------------------|--------------------|------------------|------------------|
| contracts/src/DataProvider.sol                          | 100.00% (8/8)     | 100.00% (9/9)      | 100.00% (4/4)    | 100.00% (1/1)    |
| contracts/src/Hyperdrive.sol                            | 100.00% (25/25)   | 100.00% (26/26)    | 100.00% (16/16)  | 100.00% (2/2)    |
| contracts/src/HyperdriveBase.sol                        | 97.14% (34/35)    | 95.24% (40/42)     | 80.00% (8/10)    | 100.00% (11/11)  |
| contracts/src/HyperdriveDataProvider.sol                | 100.00% (27/27)   | 97.44% (38/39)     | 50.00% (2/4)     | 100.00% (6/6)    |
| contracts/src/HyperdriveLP.sol                          | 99.01% (100/101)  | 98.45% (127/129)   | 90.00% (27/30)   | 100.00% (8/8)    |
| contracts/src/HyperdriveLong.sol                        | 100.00% (75/75)   | 97.78% (88/90)     | 87.50% (14/16)   | 100.00% (6/6)    |
| contracts/src/HyperdriveShort.sol                       | 98.82% (84/85)    | 98.08% (102/104)   | 90.00% (18/20)   | 100.00% (6/6)    |
| contracts/src/HyperdriveTWAP.sol                        | 100.00% (12/12)   | 100.00% (18/18)    | 100.00% (2/2)    | 100.00% (1/1)    |
| contracts/src/factory/AaveHyperdriveDeployer.sol        | 100.00% (2/2)     | 100.00% (3/3)      | 100.00% (0/0)    | 100.00% (1/1)    |
| contracts/src/factory/AaveHyperdriveFactory.sol         | 90.91% (10/11)    | 92.86% (13/14)     | 75.00% (3/4)     | 100.00% (2/2)    |
| contracts/src/factory/DsrHyperdriveDeployer.sol         | 100.00% (1/1)     | 100.00% (1/1)      | 100.00% (0/0)    | 100.00% (1/1)    |
| contracts/src/factory/DsrHyperdriveFactory.sol          | 100.00% (1/1)     | 100.00% (1/1)      | 100.00% (0/0)    | 100.00% (1/1)    |
| contracts/src/factory/ERC4626HyperdriveDeployer.sol     | 100.00% (1/1)     | 100.00% (1/1)      | 100.00% (0/0)    | 100.00% (1/1)    |
| contracts/src/factory/ERC4626HyperdriveFactory.sol      | 100.00% (1/1)     | 100.00% (1/1)      | 100.00% (0/0)    | 100.00% (1/1)    |
| contracts/src/factory/HyperdriveFactory.sol             | 88.00% (22/25)    | 86.67% (26/30)     | 33.33% (2/6)     | 100.00% (7/7)    |
| contracts/src/factory/StethHyperdriveDeployer.sol       | 0.00% (0/3)       | 0.00% (0/3)        | 0.00% (0/2)      | 0.00% (0/1)      |
| contracts/src/factory/StethHyperdriveFactory.sol        | 0.00% (0/1)       | 0.00% (0/1)        | 100.00% (0/0)    | 0.00% (0/1)      |
| contracts/src/instances/AaveHyperdrive.sol              | 29.03% (9/31)     | 28.57% (10/35)     | 21.43% (3/14)    | 33.33% (1/3)     |
| contracts/src/instances/AaveHyperdriveDataProvider.sol  | 0.00% (0/6)       | 0.00% (0/7)        | 100.00% (0/0)    | 0.00% (0/4)      |
| contracts/src/instances/DsrHyperdrive.sol               | 91.18% (31/34)    | 93.02% (40/43)     | 75.00% (9/12)    | 100.00% (5/5)    |
| contracts/src/instances/DsrHyperdriveDataProvider.sol   | 10.00% (1/10)     | 6.67% (1/15)       | 100.00% (0/0)    | 16.67% (1/6)     |
| contracts/src/instances/ERC4626DataProvider.sol         | 0.00% (0/4)       | 0.00% (0/5)        | 100.00% (0/0)    | 0.00% (0/2)      |
| contracts/src/instances/ERC4626Hyperdrive.sol           | 85.71% (18/21)    | 88.00% (22/25)     | 50.00% (5/10)    | 100.00% (3/3)    |
| contracts/src/instances/StethHyperdrive.sol             | 72.73% (16/22)    | 72.73% (16/22)     | 57.14% (8/14)    | 100.00% (4/4)    |
| contracts/src/instances/StethHyperdriveDataProvider.sol | 50.00% (1/2)      | 50.00% (1/2)       | 100.00% (0/0)    | 50.00% (1/2)     |
| contracts/src/libraries/AssetId.sol                     | 100.00% (5/5)     | 100.00% (5/5)      | 100.00% (2/2)    | 100.00% (2/2)    |
| contracts/src/libraries/FixedPointMath.sol              | 100.00% (80/80)   | 97.87% (92/94)     | 90.91% (20/22)   | 100.00% (13/13)  |
| contracts/src/libraries/HyperdriveMath.sol              | 100.00% (66/66)   | 100.00% (85/85)    | 100.00% (24/24)  | 100.00% (13/13)  |
| contracts/src/libraries/SafeCast.sol                    | 100.00% (2/2)     | 100.00% (2/2)      | 100.00% (2/2)    | 100.00% (1/1)    |
| contracts/src/libraries/YieldSpaceMath.sol              | 100.00% (30/30)   | 100.00% (46/46)    | 100.00% (0/0)    | 100.00% (6/6)    |
| contracts/src/token/BondWrapper.sol                     | 100.00% (33/33)   | 91.84% (45/49)     | 66.67% (12/18)   | 80.00% (4/5)     |
| contracts/src/token/ERC20Forwarder.sol                  | 100.00% (25/25)   | 100.00% (30/30)    | 100.00% (8/8)    | 100.00% (10/10)  |
| contracts/src/token/ForwarderFactory.sol                | 100.00% (12/12)   | 100.00% (16/16)    | 50.00% (1/2)     | 100.00% (3/3)    |
| contracts/src/token/MultiToken.sol                      | 100.00% (39/39)   | 97.92% (47/48)     | 93.75% (15/16)   | 100.00% (12/12)  |
| contracts/src/token/MultiTokenDataProvider.sol          | 100.00% (10/10)   | 100.00% (10/10)    | 100.00% (0/0)    | 100.00% (10/10)  |
```

### 3.5. Consider using `delete` rather than assigning zero to clear values

The `delete` keyword more closely matches the semantics of what is being done, and draws more attention to the changing of state, which may lead to a more thorough audit of its associated logic

- [contracts/src/HyperdriveBase.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveBase.sol)

```solidity
File: contracts/src/HyperdriveBase.sol

204:         _governanceFeesAccrued = 0;
```

- [contracts/src/HyperdriveLP.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveLP.sol)

```solidity
File: contracts/src/HyperdriveLP.sol

447:             withdrawalShares = 0;
```

### 3.6. Function ordering does not follow the Solidity style guide

According to the [Solidity style guide](https://docs.soliditylang.org/en/v0.8.17/style-guide.html#order-of-functions), functions should be laid out in the following order :`constructor()`, `receive()`, `fallback()`, `external`, `public`, `internal`, `private`, but the cases below do not follow this pattern

- [contracts/src/HyperdriveBase.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveBase.sol)

```solidity
File: contracts/src/HyperdriveBase.sol

1: Current order:
   internal _checkMessageValue
   internal _deposit
   internal _withdraw
   internal _pricePerShare
   external setPauser
   external setGovernance
   external pause
   public checkpoint
   internal _applyCheckpoint
   external collectGovernanceFee
   internal _calculateTimeRemaining
   internal _calculateTimeRemainingScaled
   internal _latestCheckpoint
   internal _calculateFeesOutGivenSharesIn
   internal _calculateFeesOutGivenBondsIn
   internal _calculateFeesInGivenBondsOut
   
   Suggested order:
   external setPauser
   external setGovernance
   external pause
   external collectGovernanceFee
   public checkpoint
   internal _checkMessageValue
   internal _deposit
   internal _withdraw
   internal _pricePerShare
   internal _applyCheckpoint
   internal _calculateTimeRemaining
   internal _calculateTimeRemainingScaled
   internal _latestCheckpoint
   internal _calculateFeesOutGivenSharesIn
   internal _calculateFeesOutGivenBondsIn
   internal _calculateFeesInGivenBondsOut
```

- [contracts/src/HyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveDataProvider.sol)

```solidity
File: contracts/src/HyperdriveDataProvider.sol

1: Current order:
   internal _pricePerShare
   external baseToken
   external getCheckpoint
   external getPoolConfig
   external getPoolInfo
   external load
   external query
   
   Suggested order:
   external baseToken
   external getCheckpoint
   external getPoolConfig
   external getPoolInfo
   external load
   external query
   internal _pricePerShare
```

- [contracts/src/factory/AaveHyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/AaveHyperdriveFactory.sol)

```solidity
File: contracts/src/factory/AaveHyperdriveFactory.sol

1: Current order:
   public deployAndInitialize
   internal deployDataProvider
   external pool
   
   Suggested order:
   external pool
   public deployAndInitialize
   internal deployDataProvider
```

- [contracts/src/instances/AaveHyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/AaveHyperdriveDataProvider.sol)

```solidity
File: contracts/src/instances/AaveHyperdriveDataProvider.sol

1: Current order:
   internal _pricePerShare
   external aToken
   external pool
   external totalShares
   
   Suggested order:
   external aToken
   external pool
   external totalShares
   internal _pricePerShare
```

- [contracts/src/instances/ERC4626DataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/ERC4626DataProvider.sol)

```solidity
File: contracts/src/instances/ERC4626DataProvider.sol

1: Current order:
   internal _pricePerShare
   external pool
   
   Suggested order:
   external pool
   internal _pricePerShare
```

- [contracts/src/instances/StethHyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/StethHyperdriveDataProvider.sol)

```solidity
File: contracts/src/instances/StethHyperdriveDataProvider.sol

1: Current order:
   internal _pricePerShare
   external lido
   
   Suggested order:
   external lido
   internal _pricePerShare
```

- [contracts/src/libraries/FixedPointMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/FixedPointMath.sol)

```solidity
File: contracts/src/libraries/FixedPointMath.sol

1: Current order:
   internal add
   internal sub
   internal mulDivDown
   internal mulDown
   internal divDown
   internal mulDivUp
   internal mulUp
   internal divUp
   internal pow
   internal exp
   internal ln
   private _ln
   internal updateWeightedAverage
   
   Suggested order:
   internal add
   internal sub
   internal mulDivDown
   internal mulDown
   internal divDown
   internal mulDivUp
   internal mulUp
   internal divUp
   internal pow
   internal exp
   internal ln
   internal updateWeightedAverage
   private _ln
```

- [contracts/src/token/BondWrapper.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/BondWrapper.sol)

```solidity
File: contracts/src/token/BondWrapper.sol

1: Current order:
   external mint
   external close
   public sweep
   public redeem
   external sweepAndRedeem
   
   Suggested order:
   external mint
   external close
   external sweepAndRedeem
   public sweep
   public redeem
```

- [contracts/src/token/MultiToken.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/MultiToken.sol)

```solidity
File: contracts/src/token/MultiToken.sol

1: Current order:
   internal _deriveForwarderAddress
   external transferFrom
   external transferFromBridge
   internal _transferFrom
   external setApprovalForAll
   external setApproval
   external setApprovalBridge
   internal _setApproval
   internal _mint
   internal _burn
   external batchTransferFrom
   external permitForAll
   
   Suggested order:
   external transferFrom
   external transferFromBridge
   external setApprovalForAll
   external setApproval
   external setApprovalBridge
   external batchTransferFrom
   external permitForAll
   internal _deriveForwarderAddress
   internal _transferFrom
   internal _setApproval
   internal _mint
   internal _burn
```

### 3.7. Change uint to uint256

Throughout the code base, some variables are declared as `uint`. To favor explicitness, consider changing all instances of `uint` to `uint256`

- [contracts/src/instances/DsrHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdrive.sol)

```solidity
File: contracts/src/instances/DsrHyperdrive.sol

182:     function _rpow(uint x, uint n, uint base) internal pure returns (uint z) {
```

- [contracts/src/instances/DsrHyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdriveDataProvider.sol)

```solidity
File: contracts/src/instances/DsrHyperdriveDataProvider.sol

115:     function _rpow(uint x, uint n, uint base) internal pure returns (uint z) {
```

### 3.8. Lack of checks in setters

Be it sanity checks (like checks against `0`-values) or initial setting checks: it's best for Setter functions needs to have them

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

73:     function updateImplementation(
            IHyperdriveDeployer newDeployer
        ) external onlyGovernance {
            // Update version and increment the counter
            hyperdriveDeployer = newDeployer;
            versionCounter++;

83:     function updateGovernance(address newGovernance) external onlyGovernance {
            // Update governance
            governance = newGovernance;

90:     function updateHyperdriveGovernance(
            address newGovernance
        ) external onlyGovernance {
            // Update hyperdrive governance
            hyperdriveGovernance = newGovernance;

99:     function updateFeeCollector(
            address newFeeCollector
        ) external onlyGovernance {
            // Update fee collector
            feeCollector = newFeeCollector;

108:     function updateFees(
             IHyperdrive.Fees calldata newFees
         ) external onlyGovernance {
             // Update the fee struct
             fees = newFees;

117:     function updateDefaultPausers(
             address[] calldata newDefaults
         ) external onlyGovernance {
             // Update the default pausers
             defaultPausers = newDefaults;
```

- [contracts/src/token/MultiToken.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/MultiToken.sol)

```solidity
File: contracts/src/token/MultiToken.sol

156:     function setApprovalForAll(
             address operator,
             bool approved
         ) external override {
             // set the appropriate state
             _isApprovedForAll[msg.sender][operator] = approved;
             // Emit an event to track approval
             emit ApprovalForAll(msg.sender, operator, approved);

171:     function setApproval(
             uint256 tokenID,
             address operator,
             uint256 amount
         ) external override {
             _setApproval(tokenID, operator, amount, msg.sender);

185:     function setApprovalBridge(
             uint256 tokenID,
             address operator,
             uint256 amount,
             address caller
         ) external override onlyLinker(tokenID) {
             _setApproval(tokenID, operator, amount, caller);

200:     function _setApproval(
             uint256 tokenID,
             address operator,
             uint256 amount,
             address caller
         ) internal {
             _perTokenApprovals[tokenID][caller][operator] = amount;
             // Emit an event to track approval
             emit Approval(caller, operator, amount);
```

### 3.9. `type(uint256).max` should be used instead of `2 ** 256 - 1`

- [contracts/src/libraries/FixedPointMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/FixedPointMath.sol)

```solidity
File: contracts/src/libraries/FixedPointMath.sol

16:     uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;
```

### 3.10. Missing Event for critical parameters change

Events help non-contract tools to track changes, and events prevent users from being surprised by changes.

- [contracts/src/HyperdriveBase.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveBase.sol)

```solidity
File: contracts/src/HyperdriveBase.sol

151:     function setPauser(address who, bool status) external {
             if (msg.sender != _governance) revert Errors.Unauthorized();
             _pausers[who] = status;

158:     function setGovernance(address who) external {
             if (msg.sender != _governance) revert Errors.Unauthorized();
             _governance = who;
```

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

73:     function updateImplementation(
            IHyperdriveDeployer newDeployer
        ) external onlyGovernance {
            // Update version and increment the counter
            hyperdriveDeployer = newDeployer;
            versionCounter++;

83:     function updateGovernance(address newGovernance) external onlyGovernance {
            // Update governance
            governance = newGovernance;

90:     function updateHyperdriveGovernance(
            address newGovernance
        ) external onlyGovernance {
            // Update hyperdrive governance
            hyperdriveGovernance = newGovernance;

99:     function updateFeeCollector(
            address newFeeCollector
        ) external onlyGovernance {
            // Update fee collector
            feeCollector = newFeeCollector;

108:     function updateFees(
             IHyperdrive.Fees calldata newFees
         ) external onlyGovernance {
             // Update the fee struct
             fees = newFees;

117:     function updateDefaultPausers(
             address[] calldata newDefaults
         ) external onlyGovernance {
             // Update the default pausers
             defaultPausers = newDefaults;
```

### 3.11. Incomplete NatSpec: `@return` is missing on actually documented functions

The following functions are missing `@return` NatSpec comments.

- [contracts/src/factory/AaveHyperdriveDeployer.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/AaveHyperdriveDeployer.sol)

```solidity
File: contracts/src/factory/AaveHyperdriveDeployer.sol

27:     /// @notice Deploys a copy of hyperdrive with the given params.
        /// @param _config The configuration of the Hyperdrive pool.
        /// @param _dataProvider The address of the data provider.
        /// @param _linkerCodeHash The hash of the ERC20 linker contract's
        ///        constructor code.
        /// @param _linkerFactory The address of the factory which is used to deploy
        ///        the ERC20 linker contracts.
        /// @param _extraData This extra data contains the address of the aToken.
        function deploy(
            IHyperdrive.PoolConfig memory _config,
            address _dataProvider,
            bytes32 _linkerCodeHash,
            address _linkerFactory,
            bytes32[] calldata _extraData
        ) external override returns (address) {
```

- [contracts/src/factory/DsrHyperdriveDeployer.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/DsrHyperdriveDeployer.sol)

```solidity
File: contracts/src/factory/DsrHyperdriveDeployer.sol

25:     /// @notice Deploys a copy of hyperdrive with the given params.
        /// @param _config The configuration of the Hyperdrive pool.
        /// @param _dataProvider The address of the data provider.
        /// @param _linkerCodeHash The hash of the ERC20 linker contract's
        ///        constructor code.
        /// @param _linkerFactory The address of the factory which is used to deploy
        ///        the ERC20 linker contracts.
        function deploy(
            IHyperdrive.PoolConfig memory _config,
            address _dataProvider,
            bytes32 _linkerCodeHash,
            address _linkerFactory,
            bytes32[] calldata
        ) external override returns (address) {
```

- [contracts/src/factory/ERC4626HyperdriveDeployer.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/ERC4626HyperdriveDeployer.sol)

```solidity
File: contracts/src/factory/ERC4626HyperdriveDeployer.sol

25:     /// @notice Deploys a copy of hyperdrive with the given params.
        /// @param _config The configuration of the Hyperdrive pool.
        /// @param _dataProvider The address of the data provider.
        /// @param _linkerCodeHash The hash of the ERC20 linker contract's
        ///        constructor code.
        /// @param _linkerFactory The address of the factory which is used to deploy
        ///        the ERC20 linker contracts.
        function deploy(
            IHyperdrive.PoolConfig memory _config,
            address _dataProvider,
            bytes32 _linkerCodeHash,
            address _linkerFactory,
            bytes32[] calldata
        ) external override returns (address) {
```

- [contracts/src/factory/StethHyperdriveDeployer.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/StethHyperdriveDeployer.sol)

```solidity
File: contracts/src/factory/StethHyperdriveDeployer.sol

34:     /// @notice Deploys a copy of hyperdrive with the given params.
        /// @param _config The configuration of the Hyperdrive pool.
        /// @param _dataProvider The address of the data provider.
        /// @param _linkerCodeHash The hash of the ERC20 linker contract's
        ///        constructor code.
        /// @param _linkerFactory The address of the factory which is used to deploy
        ///        the ERC20 linker contracts.
        function deploy(
            IHyperdrive.PoolConfig memory _config,
            address _dataProvider,
            bytes32 _linkerCodeHash,
            address _linkerFactory,
            bytes32[] calldata
        ) external override returns (address) {
```

### 3.12. Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor

If a function is supposed to be access-controlled, a `modifier` should be used instead of a `require/if` statement for more readability.

- [contracts/src/HyperdriveBase.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveBase.sol)

```solidity
File: contracts/src/HyperdriveBase.sol

152:         if (msg.sender != _governance) revert Errors.Unauthorized();

159:         if (msg.sender != _governance) revert Errors.Unauthorized();

166:         if (!_pausers[msg.sender]) revert Errors.Unauthorized();
```

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

67:         if (msg.sender != governance) revert Errors.Unauthorized();
```

- [contracts/src/token/MultiToken.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/MultiToken.sol)

```solidity
File: contracts/src/token/MultiToken.sol

60:         if (msg.sender != _deriveForwarderAddress(tokenID)) {
```

### 3.13. Constant state variables defined more than once

Rather than redefining state variable constant, consider using a library to store all constants as this will prevent data redundancy

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

39:     address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
```

- [contracts/src/factory/StethHyperdriveDeployer.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/StethHyperdriveDeployer.sol)

```solidity
File: contracts/src/factory/StethHyperdriveDeployer.sol

26:     address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
```

- [contracts/src/instances/DsrHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdrive.sol)

```solidity
File: contracts/src/instances/DsrHyperdrive.sol

25:     uint256 internal constant RAY = 1e27;
```

- [contracts/src/instances/DsrHyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdriveDataProvider.sol)

```solidity
File: contracts/src/instances/DsrHyperdriveDataProvider.sol

29:     uint256 internal constant RAY = 1e27;
```

### 3.14. Consider using named mappings

Consider using [named mappings](https://ethereum.stackexchange.com/questions/51629/how-to-name-the-arguments-in-mapping/145555#145555) to make it easier to understand the purpose of each mapping

- [contracts/src/HyperdriveStorage.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveStorage.sol)

```solidity
File: contracts/src/HyperdriveStorage.sol

55:     mapping(uint256 => IHyperdrive.Checkpoint) internal _checkpoints;

59:     mapping(address => bool) internal _pausers;
```

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

23:     mapping(address => uint256) public isOfficial;
```

- [contracts/src/token/BondWrapper.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/BondWrapper.sol)

```solidity
File: contracts/src/token/BondWrapper.sol

25:     mapping(address => mapping(uint256 => uint256)) public deposits;
```

- [contracts/src/token/ERC20Forwarder.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/ERC20Forwarder.sol)

```solidity
File: contracts/src/token/ERC20Forwarder.sol

27:     mapping(address => uint256) public nonces;
```

- [contracts/src/token/MultiTokenStorage.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/MultiTokenStorage.sol)

```solidity
File: contracts/src/token/MultiTokenStorage.sol

19:     mapping(uint256 => mapping(address => uint256)) internal _balanceOf;

22:     mapping(uint256 => uint256) internal _totalSupply;

25:     mapping(address => mapping(address => bool)) internal _isApprovedForAll;

29:     mapping(uint256 => mapping(address => mapping(address => uint256)))

33:     mapping(uint256 => string) internal _name;

34:     mapping(uint256 => string) internal _symbol;

37:     mapping(address => uint256) internal _nonces;
```

### 3.15. Adding a `return` statement when the function defines a named return variable, is redundant

- [contracts/src/Hyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/Hyperdrive.sol)

```solidity
File: contracts/src/Hyperdrive.sol

85:     /// @dev Creates a new checkpoint if necessary.
        /// @param _checkpointTime The time of the checkpoint to create.
        /// @param _sharePrice The current share price.
        /// @return openSharePrice The open share price of the latest checkpoint.
        function _applyCheckpoint(
            uint256 _checkpointTime,
            uint256 _sharePrice
        ) internal override returns (uint256 openSharePrice) {
            // Return early if the checkpoint has already been updated.
            if (
                _checkpoints[_checkpointTime].sharePrice != 0 ||
                _checkpointTime > block.timestamp
            ) {
                return _checkpoints[_checkpointTime].sharePrice;

85:     /// @dev Creates a new checkpoint if necessary.
        /// @param _checkpointTime The time of the checkpoint to create.
        /// @param _sharePrice The current share price.
        /// @return openSharePrice The open share price of the latest checkpoint.
        function _applyCheckpoint(
            uint256 _checkpointTime,
            uint256 _sharePrice
        ) internal override returns (uint256 openSharePrice) {
            // Return early if the checkpoint has already been updated.
            if (
                _checkpoints[_checkpointTime].sharePrice != 0 ||
                _checkpointTime > block.timestamp
            ) {
                return _checkpoints[_checkpointTime].sharePrice;
            }
    
            // Create the share price checkpoint.
            _checkpoints[_checkpointTime].sharePrice = _sharePrice.toUint128();
    
            // Pay out the long withdrawal pool for longs that have matured.
            uint256 maturedLongsAmount = _totalSupply[
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _checkpointTime)
            ];
            if (maturedLongsAmount > 0) {
                _applyCloseLong(
                    maturedLongsAmount,
                    0,
                    maturedLongsAmount.divDown(_sharePrice),
                    0,
                    _checkpointTime,
                    _sharePrice
                );
            }
    
            // Pay out the short withdrawal pool for shorts that have matured.
            uint256 maturedShortsAmount = _totalSupply[
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _checkpointTime)
            ];
            if (maturedShortsAmount > 0) {
                _applyCloseShort(
                    maturedShortsAmount,
                    0,
                    maturedShortsAmount.divDown(_sharePrice),
                    0,
                    _checkpointTime,
                    _sharePrice
                );
            }
    
            return _checkpoints[_checkpointTime].sharePrice;
```

- [contracts/src/HyperdriveLP.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveLP.sol)

```solidity
File: contracts/src/HyperdriveLP.sol

365:     /// @dev Removes liquidity from the pool and calculates the amount of
         ///      withdrawal shares that should be minted.
         /// @param _shares The amount of shares to remove.
         /// @param _sharePrice The current price of a share.
         /// @param _totalLpSupply The total amount of LP shares.
         /// @param _totalActiveLpSupply The total amount of active LP shares.
         /// @param _withdrawalSharesOutstanding The total amount of withdrawal
         ///        shares outstanding.
         /// @return shareProceeds The share proceeds that will be paid to the LP.
         /// @return The amount of withdrawal shares that should be minted.
         function _applyRemoveLiquidity(
             uint256 _shares,
             uint256 _sharePrice,
             uint256 _totalLpSupply,
             uint256 _totalActiveLpSupply,
             uint256 _withdrawalSharesOutstanding
         ) internal returns (uint256 shareProceeds, uint256) {
             // Calculate the starting present value of the pool.
             HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                 .PresentValueParams({
                     shareReserves: _marketState.shareReserves,
                     bondReserves: _marketState.bondReserves,
                     sharePrice: _sharePrice,
                     initialSharePrice: _initialSharePrice,
                     timeStretch: _timeStretch,
                     longsOutstanding: _marketState.longsOutstanding,
                     longAverageTimeRemaining: _calculateTimeRemainingScaled(
                         _marketState.longAverageMaturityTime
                     ),
                     shortsOutstanding: _marketState.shortsOutstanding,
                     shortAverageTimeRemaining: _calculateTimeRemainingScaled(
                         _marketState.shortAverageMaturityTime
                     ),
                     shortBaseVolume: _marketState.shortBaseVolume
                 });
             uint256 startingPresentValue = HyperdriveMath.calculatePresentValue(
                 params
             );
     
             // The LP is given their share of the idle capital in the pool. This
             // is removed from the pool's reserves and paid out immediately. We use
             // the average opening share price of longs to avoid double counting
             // the variable rate interest accrued on long positions. The idle amount
             // is given by:
             //
             // idle = (z - (o_l / c_0)) * (dl / l_a)
             shareProceeds = _marketState.shareReserves;
             if (_marketState.longsOutstanding > 0) {
                 shareProceeds -= uint256(_marketState.longsOutstanding).divDown(
                     _marketState.longOpenSharePrice
                 );
             }
             shareProceeds = shareProceeds.mulDivDown(_shares, _totalActiveLpSupply);
             _updateLiquidity(-int256(shareProceeds));
             params.shareReserves = _marketState.shareReserves;
             params.bondReserves = _marketState.bondReserves;
             uint256 endingPresentValue = HyperdriveMath.calculatePresentValue(
                 params
             );
     
             // Calculate the amount of withdrawal shares that should be minted. We
             // solve for this value by solving the present value equation as
             // follows:
             //
             // PV0 / l0 = PV1 / (l0 - dl + dw) => dw = (PV1 / PV0) * l0 - (l0 - dl)
             int256 withdrawalShares = int256(
                 _totalLpSupply.mulDivDown(endingPresentValue, startingPresentValue)
             );
             withdrawalShares -= int256(_totalLpSupply) - int256(_shares);
             if (withdrawalShares < 0) {
                 // We backtrack by calculating the amount of the idle that should
                 // be returned to the pool using the original present value ratio.
                 uint256 overestimatedProceeds = startingPresentValue.mulDivDown(
                     uint256(-withdrawalShares),
                     _totalLpSupply
                 );
                 _updateLiquidity(int256(overestimatedProceeds));
                 _applyWithdrawalProceeds(
                     overestimatedProceeds,
                     _withdrawalSharesOutstanding,
                     _sharePrice
                 );
                 withdrawalShares = 0;
             }
     
             return (shareProceeds, uint256(withdrawalShares));
```

- [contracts/src/HyperdriveLong.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveLong.sol)

```solidity
File: contracts/src/HyperdriveLong.sol

349:     /// @dev Calculate the pool reserve and trader deltas that result from
         ///      opening a long. This calculation includes trading fees.
         /// @param _shareAmount The amount of shares being paid to open the long.
         /// @param _sharePrice The current share price.
         /// @param _timeRemaining The time remaining in the position.
         /// @return shareReservesDelta The change in the share reserves.
         /// @return bondReservesDelta The change in the bond reserves.
         /// @return bondProceeds The proceeds in bonds.
         /// @return totalGovernanceFee The governance fee in shares.
         function _calculateOpenLong(
             uint256 _shareAmount,
             uint256 _sharePrice,
             uint256 _timeRemaining
         )
             internal
             returns (
                 uint256 shareReservesDelta,
                 uint256 bondReservesDelta,
                 uint256 bondProceeds,
                 uint256 totalGovernanceFee
             )
         {
             // Calculate the effect that opening the long should have on the pool's
             // reserves as well as the amount of bond the trader receives.
             bondReservesDelta = HyperdriveMath.calculateOpenLong(
                 _marketState.shareReserves,
                 _marketState.bondReserves,
                 _shareAmount, // amountIn
                 _timeStretch,
                 _sharePrice,
                 _initialSharePrice
             );
     
             // Calculate the fees charged on the curve and flat parts of the trade.
             // Since we calculate the amount of bonds received given shares in, we
             // subtract the fee from the bond deltas so that the trader receives
             // less bonds.
             uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
                 _marketState.shareReserves,
                 _marketState.bondReserves,
                 _initialSharePrice,
                 _timeRemaining,
                 _timeStretch
             );
     
             // Record an oracle update
             recordPrice(spotPrice);
     
             (
                 uint256 totalCurveFee,
                 uint256 governanceCurveFee
             ) = _calculateFeesOutGivenSharesIn(
                     _shareAmount, // amountIn
                     bondReservesDelta, // amountOut
                     spotPrice,
                     _sharePrice
                 );
             bondProceeds = bondReservesDelta - totalCurveFee;
             bondReservesDelta -= totalCurveFee - governanceCurveFee;
     
             // Calculate the fees owed to governance in shares.
             shareReservesDelta =
                 _shareAmount -
                 governanceCurveFee.divDown(_sharePrice);
             totalGovernanceFee = governanceCurveFee.divDown(_sharePrice);
     
             return (

423:     /// @dev Calculate the pool reserve and trader deltas that result from
         ///      closing a long. This calculation includes trading fees.
         /// @param _bondAmount The amount of bonds being purchased to close the short.
         /// @param _sharePrice The current share price.
         /// @param _maturityTime The maturity time of the short position.
         /// @return shareReservesDelta The change in the share reserves.
         /// @return bondReservesDelta The change in the bond reserves.
         /// @return shareProceeds The proceeds in shares of selling the bonds.
         /// @return totalGovernanceFee The governance fee in shares.
         function _calculateCloseLong(
             uint256 _bondAmount,
             uint256 _sharePrice,
             uint256 _maturityTime
         )
             internal
             returns (
                 uint256 shareReservesDelta,
                 uint256 bondReservesDelta,
                 uint256 shareProceeds,
                 uint256 totalGovernanceFee
             )
         {
             // Calculate the effect that closing the long should have on the pool's
             // reserves as well as the amount of shares the trader receives for
             // selling the bonds at the market price.
             // NOTE: We calculate the time remaining from the latest checkpoint to ensure that
             // opening/closing a position doesn't result in immediate profit.
             uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
             uint256 closeSharePrice = block.timestamp < _maturityTime
                 ? _sharePrice
                 : _checkpoints[_maturityTime].sharePrice;
             (shareReservesDelta, bondReservesDelta, shareProceeds) = HyperdriveMath
                 .calculateCloseLong(
                     _marketState.shareReserves,
                     _marketState.bondReserves,
                     _bondAmount,
                     timeRemaining,
                     _timeStretch,
                     closeSharePrice,
                     _sharePrice,
                     _initialSharePrice
                 );
     
             // Calculate the fees charged on the curve and flat parts of the trade.
             // Since we calculate the amount of shares received given bonds in, we
             // subtract the fee from the share deltas so that the trader receives
             // less shares.
             uint256 spotPrice = _marketState.bondReserves > 0
                 ? HyperdriveMath.calculateSpotPrice(
                     _marketState.shareReserves,
                     _marketState.bondReserves,
                     _initialSharePrice,
                     timeRemaining,
                     _timeStretch
                 )
                 : FixedPointMath.ONE_18;
     
             // Record an oracle update
             recordPrice(spotPrice);
     
             uint256 totalCurveFee;
             uint256 totalFlatFee;
             (
                 totalCurveFee,
                 totalFlatFee,
                 totalGovernanceFee
             ) = _calculateFeesOutGivenBondsIn(
                 _bondAmount, // amountIn
                 timeRemaining,
                 spotPrice,
                 _sharePrice
             );
             shareReservesDelta -= totalCurveFee;
             shareProceeds -= totalCurveFee + totalFlatFee;
     
             return (
```

- [contracts/src/HyperdriveShort.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveShort.sol)

```solidity
File: contracts/src/HyperdriveShort.sol

22:     /// @notice Opens a short position.
        /// @param _bondAmount The amount of bonds to short.
        /// @param _maxDeposit The most the user expects to deposit for this trade
        /// @param _destination The address which gets credited with share tokens
        /// @param _asUnderlying If true the user is charged in underlying if false
        ///                      the contract transfers in yield source directly.
        ///                      Note - for some paths one choice may be disabled or blocked.
        /// @return maturityTime The maturity time of the short.
        /// @return traderDeposit The amount the user deposited for this trade.
        function openShort(
            uint256 _bondAmount,
            uint256 _maxDeposit,
            address _destination,
            bool _asUnderlying
        )
            external
            payable
            isNotPaused
            returns (uint256 maturityTime, uint256 traderDeposit)
        {
            // Check that the message value and base amount are valid.
            _checkMessageValue();
            if (_bondAmount == 0) {
                revert Errors.ZeroAmount();
            }
    
            // Perform a checkpoint and compute the amount of interest the short
            // would have received if they opened at the beginning of the checkpoint.
            // Since the short will receive interest from the beginning of the
            // checkpoint, they will receive this backdated interest back at closing.
            uint256 sharePrice = _pricePerShare();
            uint256 openSharePrice = _applyCheckpoint(
                _latestCheckpoint(),
                sharePrice
            );
    
            // Calculate the pool and user deltas using the trading function. We
            // backdate the bonds sold to the beginning of the checkpoint.
            maturityTime = _latestCheckpoint() + _positionDuration;
            uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
            uint256 shareReservesDelta;
            {
                uint256 totalGovernanceFee;
                (shareReservesDelta, totalGovernanceFee) = _calculateOpenShort(
                    _bondAmount,
                    sharePrice,
                    timeRemaining
                );
    
                // Attribute the governance fees.
                _governanceFeesAccrued += totalGovernanceFee;
            }
    
            // Take custody of the trader's deposit and ensure that the trader
            // doesn't pay more than their max deposit. The trader's deposit is
            // equal to the proceeds that they would receive if they closed
            // immediately (without fees).
            traderDeposit = HyperdriveMath
                .calculateShortProceeds(
                    _bondAmount,
                    shareReservesDelta,
                    openSharePrice,
                    sharePrice,
                    sharePrice
                )
                .mulDown(sharePrice);
            if (_maxDeposit < traderDeposit) revert Errors.OutputLimit();
            _deposit(traderDeposit, _asUnderlying);
    
            // Apply the state updates caused by opening the short.
            _applyOpenShort(
                _bondAmount,
                shareReservesDelta,
                sharePrice,
                openSharePrice,
                timeRemaining,
                maturityTime
            );
    
            // Mint the short tokens to the trader. The ID is a concatenation of the
            // current share price and the maturity time of the shorts.
            uint256 assetId = AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Short,
                maturityTime
            );
            _mint(assetId, _destination, _bondAmount);
    
            // Emit an OpenShort event.
            uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
            emit OpenShort(
                _destination,
                assetId,
                maturityTime,
                traderDeposit,
                bondAmount
            );
    
            return (maturityTime, traderDeposit);

378:     /// @dev Calculate the pool reserve and trader deltas that result from
         ///      opening a short. This calculation includes trading fees.
         /// @param _bondAmount The amount of bonds being sold to open the short.
         /// @param _sharePrice The current share price.
         /// @param _timeRemaining The time remaining in the position.
         /// @return shareReservesDelta The change in the share reserves.
         /// @return totalGovernanceFee The governance fee in shares.
         function _calculateOpenShort(
             uint256 _bondAmount,
             uint256 _sharePrice,
             uint256 _timeRemaining
         )
             internal
             returns (uint256 shareReservesDelta, uint256 totalGovernanceFee)
         {
             // Calculate the effect that opening the short should have on the pool's
             // reserves as well as the amount of shares the trader receives from
             // selling the shorted bonds at the market price.
             shareReservesDelta = HyperdriveMath.calculateOpenShort(
                 _marketState.shareReserves,
                 _marketState.bondReserves,
                 _bondAmount,
                 _timeStretch,
                 _sharePrice,
                 _initialSharePrice
             );
     
             // If the base proceeds of selling the bonds is greater than the bond
             // amount, then the trade occurred in the negative interest domain. We
             // revert in these pathological cases.
             if (shareReservesDelta.mulDown(_sharePrice) > _bondAmount)
                 revert Errors.NegativeInterest();
     
             // Calculate the fees charged on the curve and flat parts of the trade.
             // Since we calculate the amount of shares received given bonds in, we
             // subtract the fee from the share deltas so that the trader receives
             // less shares.
             uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
                 _marketState.shareReserves,
                 _marketState.bondReserves,
                 _initialSharePrice,
                 _timeRemaining,
                 _timeStretch
             );
             // Add the spot price to the oracle if an oracle update is required
             recordPrice(spotPrice);
     
             uint256 totalCurveFee;
             (
                 totalCurveFee, // there is no flat fee on opening shorts
                 ,
                 totalGovernanceFee
             ) = _calculateFeesOutGivenBondsIn(
                 _bondAmount, // amountIn
                 _timeRemaining,
                 spotPrice,
                 _sharePrice
             );
             shareReservesDelta -= totalCurveFee;
             return (shareReservesDelta, totalGovernanceFee);

440:     /// @dev Calculate the pool reserve and trader deltas that result from
         ///      closing a short. This calculation includes trading fees.
         /// @param _bondAmount The amount of bonds being purchased to close the short.
         /// @param _sharePrice The current share price.
         /// @param _maturityTime The maturity time of the short position.
         /// @return shareReservesDelta The change in the share reserves.
         /// @return bondReservesDelta The change in the bond reserves.
         /// @return sharePayment The cost in shares of buying the bonds.
         /// @return totalGovernanceFee The governance fee in shares.
         function _calculateCloseShort(
             uint256 _bondAmount,
             uint256 _sharePrice,
             uint256 _maturityTime
         )
             internal
             returns (
                 uint256 shareReservesDelta,
                 uint256 bondReservesDelta,
                 uint256 sharePayment,
                 uint256 totalGovernanceFee
             )
         {
             // Calculate the effect that closing the short should have on the pool's
             // reserves as well as the amount of shares the trader needs to pay to
             // purchase the shorted bonds at the market price.
             // NOTE: We calculate the time remaining from the latest checkpoint to ensure that
             // opening/closing a position doesn't result in immediate profit.
             uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
             (shareReservesDelta, bondReservesDelta, sharePayment) = HyperdriveMath
                 .calculateCloseShort(
                     _marketState.shareReserves,
                     _marketState.bondReserves,
                     _bondAmount,
                     timeRemaining,
                     _timeStretch,
                     _sharePrice,
                     _initialSharePrice
                 );
     
             // Calculate the fees charged on the curve and flat parts of the trade.
             // Since we calculate the amount of shares paid given bonds out, we add
             // the fee from the share deltas so that the trader pays less shares.
             uint256 spotPrice = _marketState.bondReserves > 0
                 ? HyperdriveMath.calculateSpotPrice(
                     _marketState.shareReserves,
                     _marketState.bondReserves,
                     _initialSharePrice,
                     timeRemaining,
                     _timeStretch
                 )
                 : FixedPointMath.ONE_18;
     
             // Record an oracle update
             recordPrice(spotPrice);
     
             (
                 uint256 totalCurveFee,
                 uint256 totalFlatFee,
                 uint256 governanceCurveFee,
                 uint256 governanceFlatFee
             ) = _calculateFeesInGivenBondsOut(
                     _bondAmount, // amountOut
                     timeRemaining,
                     spotPrice,
                     _sharePrice
                 );
             shareReservesDelta += totalCurveFee - governanceCurveFee;
             sharePayment += totalCurveFee + totalFlatFee;
     
             return (
```

- [contracts/src/instances/AaveHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/AaveHyperdrive.sol)

```solidity
File: contracts/src/instances/AaveHyperdrive.sol

48:     ///@notice Transfers amount of 'token' from the user and commits it to the yield source.
        ///@param amount The amount of token to transfer
        /// @param asUnderlying If true the yield source will transfer underlying tokens
        ///                     if false it will transfer the yielding asset directly
        ///@return sharesMinted The shares this deposit creates
        ///@return sharePrice The share price at time of deposit
        function _deposit(
            uint256 amount,
            bool asUnderlying
        ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
            // Load the balance of this pool
            uint256 assets = aToken.balanceOf(address(this));
    
            if (asUnderlying) {
                // Transfer from user
                bool success = _baseToken.transferFrom(
                    msg.sender,
                    address(this),
                    amount
                );
                if (!success) {
                    revert Errors.TransferFailed();
                }
                // Supply for the user
                pool.supply(address(_baseToken), amount, address(this), 0);
            } else {
                // aTokens are known to be revert on failed transfer tokens
                aToken.transferFrom(msg.sender, address(this), amount);
            }
    
            // Do share calculations
            uint256 totalShares_ = totalShares;
            if (totalShares_ == 0) {
                totalShares = amount;
                return (amount, FixedPointMath.ONE_18);
            } else {
                uint256 newShares = totalShares_.mulDivDown(amount, assets);
                totalShares += newShares;
                return (newShares, _pricePerShare());

48:     ///@notice Transfers amount of 'token' from the user and commits it to the yield source.
        ///@param amount The amount of token to transfer
        /// @param asUnderlying If true the yield source will transfer underlying tokens
        ///                     if false it will transfer the yielding asset directly
        ///@return sharesMinted The shares this deposit creates
        ///@return sharePrice The share price at time of deposit
        function _deposit(
            uint256 amount,
            bool asUnderlying
        ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
            // Load the balance of this pool
            uint256 assets = aToken.balanceOf(address(this));
    
            if (asUnderlying) {
                // Transfer from user
                bool success = _baseToken.transferFrom(
                    msg.sender,
                    address(this),
                    amount
                );
                if (!success) {
                    revert Errors.TransferFailed();
                }
                // Supply for the user
                pool.supply(address(_baseToken), amount, address(this), 0);
            } else {
                // aTokens are known to be revert on failed transfer tokens
                aToken.transferFrom(msg.sender, address(this), amount);
            }
    
            // Do share calculations
            uint256 totalShares_ = totalShares;
            if (totalShares_ == 0) {
                totalShares = amount;
                return (amount, FixedPointMath.ONE_18);

90:     ///@notice Withdraws shares from the yield source and sends the resulting tokens to the destination
        ///@param shares The shares to withdraw from the yield source
        /// @param asUnderlying If true the yield source will transfer underlying tokens
        ///                     if false it will transfer the yielding asset directly
        ///@param destination The address which is where to send the resulting tokens
        ///@return amountWithdrawn the amount of 'token' produced by this withdraw
        function _withdraw(
            uint256 shares,
            address destination,
            bool asUnderlying
        ) internal override returns (uint256 amountWithdrawn) {
            // The withdrawer receives a proportional amount of the assets held by
            // the contract to the amount of shares that they are redeeming. Small
            // numerical errors can result in the shares value being slightly larger
            // than the total shares, so we clamp the shares to the total shares to
            // avoid reverts.
            uint256 totalShares_ = totalShares;
            if (shares > totalShares_) {
                shares = totalShares_;
            }
            uint256 assets = aToken.balanceOf(address(this));
            uint256 withdrawValue = assets != 0
                ? shares.mulDown(assets.divDown(totalShares_))
                : 0;
    
            if (withdrawValue == 0) {
                revert Errors.NoAssetsToWithdraw();
            }
    
            // Remove the shares from the total share supply
            totalShares -= shares;
    
            // If the user wants underlying we withdraw for them otherwise send the base
            if (asUnderlying) {
                // Now we call aave to fulfill this withdraw for the user
                pool.withdraw(address(_baseToken), withdrawValue, destination);
            } else {
                // Otherwise we simply transfer to them
                aToken.transfer(destination, withdrawValue);
            }
    
            return withdrawValue;
```

- [contracts/src/instances/AaveHyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/AaveHyperdriveDataProvider.sol)

```solidity
File: contracts/src/instances/AaveHyperdriveDataProvider.sol

52:     ///@notice Loads the share price from the yield source.
        ///@return sharePrice The current share price.
        ///@dev must remain consistent with the impl inside of the HyperdriveInstance
        function _pricePerShare()
            internal
            view
            override
            returns (uint256 sharePrice)
        {
            uint256 assets = _aToken.balanceOf(address(this));
            sharePrice = _totalShares != 0 ? assets.divDown(_totalShares) : 0;
            return sharePrice;
```

- [contracts/src/instances/DsrHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdrive.sol)

```solidity
File: contracts/src/instances/DsrHyperdrive.sol

55:     /// @notice Transfers base or shares from the user and commits it to the yield source.
        /// @param amount The amount of base tokens to deposit.
        /// @param asUnderlying The DSR yield source only supports depositing the
        ///        underlying token. If this is false, the transaction will revert.
        /// @return sharesMinted The shares this deposit creates.
        /// @return sharePrice The share price at time of deposit.
        function _deposit(
            uint256 amount,
            bool asUnderlying
        ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
            if (!asUnderlying) {
                revert Errors.UnsupportedToken();
            }
    
            // Transfer the base token from the user to this contract
            bool success = _baseToken.transferFrom(
                msg.sender,
                address(this),
                amount
            );
            if (!success) {
                revert Errors.TransferFailed();
            }
    
            // Get total invested balance of pool, deposits + interest
            uint256 totalBase = dsrManager.daiBalance(address(this));
    
            // Deposit the base tokens into the dsr
            dsrManager.join(address(this), amount);
    
            // Do share calculations
            uint256 totalShares_ = totalShares;
            if (totalShares_ == 0) {
                totalShares = amount;
                // Initial deposits are always 1:1
                return (amount, FixedPointMath.ONE_18);
            } else {
                uint256 newShares = totalShares_.mulDivDown(amount, totalBase);
                totalShares += newShares;
                return (newShares, _pricePerShare());

55:     /// @notice Transfers base or shares from the user and commits it to the yield source.
        /// @param amount The amount of base tokens to deposit.
        /// @param asUnderlying The DSR yield source only supports depositing the
        ///        underlying token. If this is false, the transaction will revert.
        /// @return sharesMinted The shares this deposit creates.
        /// @return sharePrice The share price at time of deposit.
        function _deposit(
            uint256 amount,
            bool asUnderlying
        ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
            if (!asUnderlying) {
                revert Errors.UnsupportedToken();
            }
    
            // Transfer the base token from the user to this contract
            bool success = _baseToken.transferFrom(
                msg.sender,
                address(this),
                amount
            );
            if (!success) {
                revert Errors.TransferFailed();
            }
    
            // Get total invested balance of pool, deposits + interest
            uint256 totalBase = dsrManager.daiBalance(address(this));
    
            // Deposit the base tokens into the dsr
            dsrManager.join(address(this), amount);
    
            // Do share calculations
            uint256 totalShares_ = totalShares;
            if (totalShares_ == 0) {
                totalShares = amount;
                // Initial deposits are always 1:1
                return (amount, FixedPointMath.ONE_18);

98:     /// @notice Withdraws shares from the yield source and sends the resulting tokens to the destination
        /// @param shares The shares to withdraw from the yield source
        /// @param destination The address which is where to send the resulting tokens
        /// @param asUnderlying The DSR yield source only supports depositing the
        ///        underlying token. If this is false, the transaction will revert.
        /// @return amountWithdrawn the amount of 'token' produced by this withdraw
        function _withdraw(
            uint256 shares,
            address destination,
            bool asUnderlying
        ) internal override returns (uint256 amountWithdrawn) {
            if (!asUnderlying) {
                revert Errors.UnsupportedToken();
            }
    
            // Small numerical errors can result in the shares value being slightly
            // larger than the total shares, so we clamp the shares to the total
            // shares to avoid reverts.
            uint256 totalShares_ = totalShares;
            if (shares > totalShares_) {
                shares = totalShares_;
            }
    
            // Load the balance of this contract - this calls drip internally so
            // this is real deposits + interest accrued at point in time
            uint256 totalBase = dsrManager.daiBalance(address(this));
    
            // The withdraw is the percent of shares the user has times the total assets
            amountWithdrawn = totalBase.mulDivDown(shares, totalShares_);
    
            // Remove shares from the total supply
            totalShares -= shares;
    
            // Withdraw pro-rata share of underlying to user
            dsrManager.exit(destination, amountWithdrawn);
    
            return amountWithdrawn;

137:     /// @notice Loads the share price from the yield source.
         /// @return sharePrice The current share price.
         ///@dev must remain consistent with the impl inside of the DataProvider
         function _pricePerShare()
             internal
             view
             override
             returns (uint256 sharePrice)
         {
             uint256 pie = dsrManager.pieOf(address(this));
             uint256 totalBase = pie.mulDivDown(chi(), RAY);
             // The share price is assets divided by shares
             uint256 totalShares_ = totalShares;
             if (totalShares_ != 0) {
                 return (totalBase.divDown(totalShares_));

137:     /// @notice Loads the share price from the yield source.
         /// @return sharePrice The current share price.
         ///@dev must remain consistent with the impl inside of the DataProvider
         function _pricePerShare()
             internal
             view
             override
             returns (uint256 sharePrice)
         {
             uint256 pie = dsrManager.pieOf(address(this));
             uint256 totalBase = pie.mulDivDown(chi(), RAY);
             // The share price is assets divided by shares
             uint256 totalShares_ = totalShares;
             if (totalShares_ != 0) {
                 return (totalBase.divDown(totalShares_));
             }
             return 0;
```

- [contracts/src/instances/DsrHyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdriveDataProvider.sol)

```solidity
File: contracts/src/instances/DsrHyperdriveDataProvider.sol

71:     /// @notice Loads the share price from the yield source.
        /// @return sharePrice The current share price.
        ///@dev must remain consistent with the impl inside of the HyperdriveInstance
        function _pricePerShare()
            internal
            view
            override
            returns (uint256 sharePrice)
        {
            // The normalized DAI amount owned by this contract
            uint256 pie = _dsrManager.pieOf(address(this));
            // Load the balance of this contract
            uint256 totalBase = pie.mulDivDown(chi(), RAY);
            // The share price is assets divided by shares
            return (totalBase.divDown(_totalShares));
```

- [contracts/src/instances/ERC4626DataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/ERC4626DataProvider.sol)

```solidity
File: contracts/src/instances/ERC4626DataProvider.sol

41:     /// @notice Loads the share price from the yield source.
        /// @return sharePrice The current share price.
        ///@dev must remain consistent with the impl inside of the HyperdriveInstance
        function _pricePerShare()
            internal
            view
            override
            returns (uint256 sharePrice)
        {
            uint256 shareEstimate = _pool.convertToShares(FixedPointMath.ONE_18);
            sharePrice = shareEstimate.divDown(FixedPointMath.ONE_18);
            return (sharePrice);
```

- [contracts/src/instances/StethHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/StethHyperdrive.sol)

```solidity
File: contracts/src/instances/StethHyperdrive.sol

56:     /// @dev Accepts a transfer from the user in base or the yield source token.
        /// @param _amount The amount to deposit.
        /// @param _asUnderlying A flag indicating that the deposit is paid in ETH
        ///        if true and in stETH if false. If ETH msg.value must equal amount
        /// @return shares The amount of shares that represents the amount deposited.
        /// @return sharePrice The current share price.
        function _deposit(
            uint256 _amount,
            bool _asUnderlying
        ) internal override returns (uint256 shares, uint256 sharePrice) {
            if (_asUnderlying) {
                // Ensure that sufficient ether was provided and refund any excess.
                if (msg.value < _amount) {
                    revert Errors.TransferFailed();
                }
                if (msg.value > _amount) {
                    // Return excess ether to the user.
                    (bool success, ) = payable(msg.sender).call{
                        value: msg.value - _amount
                    }("");
                    if (!success) {
                        revert Errors.TransferFailed();
                    }
                }
    
                // Submit the provided ether to Lido to be deposited. The fee
                // collector address is passed as the referral address; however,
                // users can specify whatever referrer they'd like by depositing
                // stETH instead of WETH.
                shares = lido.submit{ value: _amount }(_feeCollector);
    
                // Calculate the share price.
                sharePrice = _pricePerShare();
            } else {
                // Ensure that the user didn't send ether to the contract.
                if (msg.value > 0) {
                    revert Errors.NotPayable();
                }
    
                // Transfer stETH into the contract.
                bool success = lido.transferFrom(
                    msg.sender,
                    address(this),
                    _amount
                );
                if (!success) {
                    revert Errors.TransferFailed();
                }
    
                // Calculate the share price and the amount of shares deposited.
                sharePrice = _pricePerShare();
                shares = _amount.divDown(sharePrice);
            }
    
            return (shares, sharePrice);

113:     /// @dev Withdraws stETH to the destination address.
         /// @param _shares The amount of shares to withdraw.
         /// @param _destination The recipient of the withdrawal.
         /// @param _asUnderlying This must be false since stETH withdrawals aren't
         ///        processed instantaneously. Users that want to withdraw can manage
         ///        their withdrawal separately.
         /// @return amountWithdrawn The amount of stETH withdrawn.
         function _withdraw(
             uint256 _shares,
             address _destination,
             bool _asUnderlying
         ) internal override returns (uint256 amountWithdrawn) {
             // At the time of writing there's no stETH -> eth withdraw path
             if (_asUnderlying) {
                 revert Errors.UnsupportedToken();
             }
     
             // Transfer stETH to the destination.
             amountWithdrawn = lido.transferShares(_destination, _shares);
     
             return amountWithdrawn;

136:     /// @dev Returns the current share price. We simply use Lido's share price.
         /// @return price The current share price.
         ///@dev must remain consistent with the impl inside of the DataProvider
         function _pricePerShare() internal view override returns (uint256 price) {
             return lido.getTotalPooledEther().divDown(lido.getTotalShares());
```

- [contracts/src/instances/StethHyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/StethHyperdriveDataProvider.sol)

```solidity
File: contracts/src/instances/StethHyperdriveDataProvider.sol

45:     /// @dev Returns the current share price. We simply use Lido's share price.
        /// @return price The current share price.
        ///@dev must remain consistent with the impl inside of the HyperdriveInstance
        function _pricePerShare() internal view override returns (uint256 price) {
            return _lido.getTotalPooledEther().divDown(_lido.getTotalShares());
```

- [contracts/src/libraries/FixedPointMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/FixedPointMath.sol)

```solidity
File: contracts/src/libraries/FixedPointMath.sol

160:     /// @dev Computes e^x in 1e18 fixed point.
         /// @dev Credit to Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/SignedWadMath.sol)
         /// @param x Fixed point number in 1e18 format.
         /// @return r The result of e^x.
         function exp(int256 x) internal pure returns (int256 r) {
             unchecked {
                 // When the result is < 0.5 we return zero. This happens when
                 // x <= floor(log(0.5e18) * 1e18) ~ -42e18
                 if (x <= -42139678854452767551) return 0;

317:     /// @dev Updates a weighted average by adding or removing a weighted delta.
         /// @param _totalWeight The total weight before the update.
         /// @param _deltaWeight The weight of the new value.
         /// @param _average The weighted average before the update.
         /// @param _delta The new value.
         /// @return average The new weighted average.
         function updateWeightedAverage(
             uint256 _average,
             uint256 _totalWeight,
             uint256 _delta,
             uint256 _deltaWeight,
             bool _isAdding
         ) internal pure returns (uint256 average) {
             if (_isAdding) {
                 average = (_totalWeight.mulDown(_average))
                     .add(_deltaWeight.mulDown(_delta))
                     .divUp(_totalWeight.add(_deltaWeight));
             } else {
                 if (_totalWeight == _deltaWeight) return 0;
```

- [contracts/src/libraries/HyperdriveMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/HyperdriveMath.sol)

```solidity
File: contracts/src/libraries/HyperdriveMath.sol

40:     /// @dev Calculates the APR from the pool's reserves.
        /// @param _shareReserves The pool's share reserves.
        /// @param _bondReserves The pool's bond reserves.
        /// @param _initialSharePrice The pool's initial share price.
        /// @param _positionDuration The amount of time until maturity in seconds.
        /// @param _timeStretch The time stretch parameter.
        /// @return apr The pool's APR.
        function calculateAPRFromReserves(
            uint256 _shareReserves,
            uint256 _bondReserves,
            uint256 _initialSharePrice,
            uint256 _positionDuration,
            uint256 _timeStretch
        ) internal pure returns (uint256 apr) {
            // We are interested calculating the fixed APR for the pool. The rate is calculated by
            // dividing current spot price of the bonds by the position duration time, t.  To get the
            // annual rate, we scale t up to a year.
            uint256 annualizedTime = _positionDuration.divDown(365 days);
    
            uint256 spotPrice = calculateSpotPrice(
                _shareReserves,
                _bondReserves,
                _initialSharePrice,
                // full time remaining of position
                FixedPointMath.ONE_18,
                _timeStretch
            );
    
            // r = (1 - p) / (p * t)
            return

75:     /// @dev Calculates the initial bond reserves assuming that the initial LP
        ///      receives LP shares amounting to c * z + y. Throughout the rest of
        ///      the codebase, the bond reserves used include the LP share
        ///      adjustment specified in YieldSpace. The bond reserves returned by
        ///      this function are unadjusted which makes it easier to calculate the
        ///      initial LP shares.
        /// @param _shareReserves The pool's share reserves.
        /// @param _initialSharePrice The pool's initial share price.
        /// @param _apr The pool's APR.
        /// @param _positionDuration The amount of time until maturity in seconds.
        /// @param _timeStretch The time stretch parameter.
        /// @return bondReserves The bond reserves (without adjustment) that make
        ///         the pool have a specified APR.
        function calculateInitialBondReserves(
            uint256 _shareReserves,
            uint256 _initialSharePrice,
            uint256 _apr,
            uint256 _positionDuration,
            uint256 _timeStretch
        ) internal pure returns (uint256 bondReserves) {
            // NOTE: Using divDown to convert to fixed point format.
            uint256 t = _positionDuration.divDown(365 days);
            uint256 tau = FixedPointMath.ONE_18.mulDown(_timeStretch);
            // mu * z * (1 + apr * t) ** (1 / tau)
            return

293:     /// @dev Calculates the maximum amount of shares a user can spend on buying
         ///      bonds before the spot crosses above a price of 1.
         /// @param _shareReserves The pool's share reserves.
         /// @param _bondReserves The pool's bonds reserves.
         /// @param _longsOutstanding The amount of longs outstanding.
         /// @param _timeStretch The time stretch parameter.
         /// @param _sharePrice The share price.
         /// @param _initialSharePrice The initial share price.
         /// @param _maxIterations The maximum number of iterations to perform before
         ///        returning the result.
         /// @return result The maximum amount of bonds that can be purchased and the
         ///         amount of base that must be spent to purchase them.
         function calculateMaxLong(
             uint256 _shareReserves,
             uint256 _bondReserves,
             uint256 _longsOutstanding,
             uint256 _timeStretch,
             uint256 _sharePrice,
             uint256 _initialSharePrice,
             uint256 _maxIterations
         ) internal pure returns (MaxLongResult memory result) {
             // We first solve for the maximum buy that is possible on the YieldSpace
             // curve. This will give us an upper bound on our maximum buy by giving
             // us the maximum buy that is possible without going into negative
             // interest territory. Hyperdrive has solvency requirements since it
             // mints longs on demand. If the maximum buy satisfies our solvency
             // checks, then we're done. If not, then we need to solve for the
             // maximum trade size iteratively.
             (uint256 dz, uint256 dy) = YieldSpaceMath.calculateMaxBuy(
                 _shareReserves,
                 _bondReserves,
                 FixedPointMath.ONE_18 - _timeStretch,
                 _sharePrice,
                 _initialSharePrice
             );
             if (
                 _shareReserves + dz >= (_longsOutstanding + dy).divDown(_sharePrice)
             ) {
                 result.baseAmount = dz.mulDown(_sharePrice);
                 result.bondAmount = dy;
                 return result;

293:     /// @dev Calculates the maximum amount of shares a user can spend on buying
         ///      bonds before the spot crosses above a price of 1.
         /// @param _shareReserves The pool's share reserves.
         /// @param _bondReserves The pool's bonds reserves.
         /// @param _longsOutstanding The amount of longs outstanding.
         /// @param _timeStretch The time stretch parameter.
         /// @param _sharePrice The share price.
         /// @param _initialSharePrice The initial share price.
         /// @param _maxIterations The maximum number of iterations to perform before
         ///        returning the result.
         /// @return result The maximum amount of bonds that can be purchased and the
         ///         amount of base that must be spent to purchase them.
         function calculateMaxLong(
             uint256 _shareReserves,
             uint256 _bondReserves,
             uint256 _longsOutstanding,
             uint256 _timeStretch,
             uint256 _sharePrice,
             uint256 _initialSharePrice,
             uint256 _maxIterations
         ) internal pure returns (MaxLongResult memory result) {
             // We first solve for the maximum buy that is possible on the YieldSpace
             // curve. This will give us an upper bound on our maximum buy by giving
             // us the maximum buy that is possible without going into negative
             // interest territory. Hyperdrive has solvency requirements since it
             // mints longs on demand. If the maximum buy satisfies our solvency
             // checks, then we're done. If not, then we need to solve for the
             // maximum trade size iteratively.
             (uint256 dz, uint256 dy) = YieldSpaceMath.calculateMaxBuy(
                 _shareReserves,
                 _bondReserves,
                 FixedPointMath.ONE_18 - _timeStretch,
                 _sharePrice,
                 _initialSharePrice
             );
             if (
                 _shareReserves + dz >= (_longsOutstanding + dy).divDown(_sharePrice)
             ) {
                 result.baseAmount = dz.mulDown(_sharePrice);
                 result.bondAmount = dy;
                 return result;
             }
     
             // To make an initial guess for the iterative approximation, we consider
             // the solvency check to be the error that we want to reduce. The amount
             // the long buffer exceeds the share reserves is given by
             // (y_l + dy) / c - (z + dz). Since the error could be large, we'll use
             // the realized price of the trade instead of the spot price to
             // approximate the change in trade output. This gives us dy = c * 1/p * dz.
             // Substituting this into error equation and setting the error equal to
             // zero allows us to solve for the initial guess as:
             //
             // (y_l + c * 1/p * dz) / c - (z + dz) = 0
             //              =>
             // (1/p - 1) * dz = z - y_l/c
             //              =>
             // dz = (z - y_l/c) * (p / (p - 1))
             uint256 p = _sharePrice.mulDivDown(dz, dy);
             dz = (_shareReserves - _longsOutstanding.divDown(_sharePrice))
                 .mulDivDown(p, FixedPointMath.ONE_18 - p);
             dy = YieldSpaceMath.calculateBondsOutGivenSharesIn(
                 _shareReserves,
                 _bondReserves,
                 dz,
                 FixedPointMath.ONE_18 - _timeStretch,
                 _sharePrice,
                 _initialSharePrice
             );
     
             // Our maximum long will be the largest trade size that doesn't fail
             // the solvency check.
             for (uint256 i = 0; i < _maxIterations; i++) {
                 // Even though YieldSpace isn't linear, we can use a linear
                 // approximation to get closer to the optimal solution. Our guess
                 // should bring us close enough to the optimal point that we can
                 // linearly approximate the change in error using the current spot
                 // price.
                 //
                 // We can approximate the change in the trade output with respect to
                 // trade size as dy' = c * (1/p) * dz'. Substituting this into our
                 // error equation and setting the error equation equal to zero
                 // allows us to solve for the trade size update:
                 //
                 // (y_l + dy + c * (1/p) * dz') / c - (z + dz + dz') = 0
                 //                  =>
                 // (1/p - 1) * dz' = (z + dz) - (y_l + dy) / c
                 //                  =>
                 // dz' = ((z + dz) - (y_l + dy) / c) * (p / (p - 1)).
                 p = calculateSpotPrice(
                     _shareReserves + dz,
                     _bondReserves - dy,
                     _initialSharePrice,
                     FixedPointMath.ONE_18,
                     _timeStretch
                 );
                 int256 error = int256((_shareReserves + dz)) -
                     int256((_longsOutstanding + dy).divDown(_sharePrice));
                 if (error < 0) {
                     dz -= uint256(-error).mulDivDown(p, FixedPointMath.ONE_18 - p);
                 } else {
                     if (dz.mulDown(_sharePrice) > result.baseAmount) {
                         result.baseAmount = dz.mulDown(_sharePrice);
                         result.bondAmount = dy;
                     }
                     dz += uint256(error).mulDivDown(p, FixedPointMath.ONE_18 - p);
                 }
                 dy = YieldSpaceMath.calculateBondsOutGivenSharesIn(
                     _shareReserves,
                     _bondReserves,
                     dz,
                     FixedPointMath.ONE_18 - _timeStretch,
                     _sharePrice,
                     _initialSharePrice
                 );
             }
     
             return result;

557:     /// @dev Calculates the proceeds in shares of closing a short position. This
         ///      takes into account the trading profits, the interest that was
         ///      earned by the short, and the amount of margin that was released
         ///      by closing the short. The math for the short's proceeds in base is
         ///      given by:
         ///
         ///      proceeds = dy - c * dz + (c1 - c0) * (dy / c0)
         ///               = dy - c * dz + (c1 / c0) * dy - dy
         ///               = (c1 / c0) * dy - c * dz
         ///
         ///      We convert the proceeds to shares by dividing by the current share
         ///      price. In the event that the interest is negative and outweighs the
         ///      trading profits and margin released, the short's proceeds are
         ///      marked to zero.
         /// @param _bondAmount The amount of bonds underlying the closed short.
         /// @param _shareAmount The amount of shares that it costs to close the
         ///                     short.
         /// @param _openSharePrice The share price at the short's open.
         /// @param _closeSharePrice The share price at the short's close.
         /// @param _sharePrice The current share price.
         /// @return shareProceeds The short proceeds in shares.
         function calculateShortProceeds(
             uint256 _bondAmount,
             uint256 _shareAmount,
             uint256 _openSharePrice,
             uint256 _closeSharePrice,
             uint256 _sharePrice
         ) internal pure returns (uint256 shareProceeds) {
             // If the interest is more negative than the trading profits and margin
             // released, than the short proceeds are marked to zero. Otherwise, we
             // calculate the proceeds as the sum of the trading proceeds, the
             // interest proceeds, and the margin released.
             uint256 bondFactor = _bondAmount.mulDivDown(
                 _closeSharePrice,
                 // We round up here do avoid overestimating the share proceeds.
                 _openSharePrice.mulUp(_sharePrice)
             );
             if (bondFactor > _shareAmount) {
                 // proceeds = (c1 / c0 * c) * dy - dz
                 shareProceeds = bondFactor - _shareAmount;
             }
             return shareProceeds;

632:     /// @dev Calculates the base volume of an open trade given the base amount,
         ///      the bond amount, and the time remaining. Since the base amount
         ///      takes into account backdating, we can't use this as our base
         ///      volume. Since we linearly interpolate between the base volume
         ///      and the bond amount as the time remaining goes from 1 to 0, the
         ///      base volume is can be determined as follows:
         ///
         ///      baseAmount = t * baseVolume + (1 - t) * bondAmount
         ///                               =>
         ///      baseVolume = (baseAmount - (1 - t) * bondAmount) / t
         /// @param _baseAmount The base exchanged in the open trade.
         /// @param _bondAmount The bonds exchanged in the open trade.
         /// @param _timeRemaining The time remaining in the position.
         /// @return baseVolume The calculated base volume.
         function calculateBaseVolume(
             uint256 _baseAmount,
             uint256 _bondAmount,
             uint256 _timeRemaining
         ) internal pure returns (uint256 baseVolume) {
             // If the time remaining is 0, the position has already matured and
             // doesn't have an impact on LP's ability to withdraw. This is a
             // pathological case that should never arise.
             if (_timeRemaining == 0) return 0;
```

### 3.16. Take advantage of Custom Error's return value property

An important feature of Custom Error is that values such as address, tokenID, msg.value can be written inside the () sign, this kind of approach provides a serious advantage in debugging and examining the revert details of dapps such as tenderly.

- [contracts/src/DataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/DataProvider.sol)

```solidity
File: contracts/src/DataProvider.sol

36:             revert Errors.UnexpectedSuccess();
```

- [contracts/src/Hyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/Hyperdrive.sol)

```solidity
File: contracts/src/Hyperdrive.sol

59:             revert Errors.InvalidCheckpointTime();
```

- [contracts/src/HyperdriveBase.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveBase.sol)

```solidity
File: contracts/src/HyperdriveBase.sol

110:             revert Errors.NotPayable();

152:         if (msg.sender != _governance) revert Errors.Unauthorized();

159:         if (msg.sender != _governance) revert Errors.Unauthorized();

166:         if (!_pausers[msg.sender]) revert Errors.Unauthorized();

172:         if (_marketState.isPaused) revert Errors.Paused();

202:         ) revert Errors.Unauthorized();
```

- [contracts/src/HyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveDataProvider.sol)

```solidity
File: contracts/src/HyperdriveDataProvider.sol

155:         if (oldData.timestamp == 0) revert Errors.QueryOutOfRange();
```

- [contracts/src/HyperdriveLP.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveLP.sol)

```solidity
File: contracts/src/HyperdriveLP.sol

38:             revert Errors.ZeroAmount();

43:             revert Errors.PoolAlreadyInitialized();

97:             revert Errors.ZeroAmount();

108:         if (apr < _minApr || apr > _maxApr) revert Errors.InvalidApr();

222:             revert Errors.ZeroAmount();

265:         if (_minOutput > baseProceeds) revert Errors.OutputLimit();

332:             revert Errors.OutputLimit();
```

- [contracts/src/HyperdriveLong.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveLong.sol)

```solidity
File: contracts/src/HyperdriveLong.sol

38:             revert Errors.ZeroAmount();

71:             revert Errors.NegativeInterest();

75:         if (_minOutput > bondProceeds) revert Errors.OutputLimit();

128:             revert Errors.ZeroAmount();

177:         if (_minOutput > baseProceeds) revert Errors.OutputLimit();

269:             revert Errors.BaseBufferExceedsShareReserves();
```

- [contracts/src/HyperdriveShort.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveShort.sol)

```solidity
File: contracts/src/HyperdriveShort.sol

45:             revert Errors.ZeroAmount();

88:         if (_maxDeposit < traderDeposit) revert Errors.OutputLimit();

139:             revert Errors.ZeroAmount();

178:                 revert Errors.NegativeInterest();

221:         if (baseProceeds < _minOutput) revert Errors.OutputLimit();

290:             revert Errors.BaseBufferExceedsShareReserves();

409:             revert Errors.NegativeInterest();
```

- [contracts/src/HyperdriveStorage.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveStorage.sol)

```solidity
File: contracts/src/HyperdriveStorage.sol

98:             revert Errors.InvalidCheckpointDuration();

105:             revert Errors.InvalidPositionDuration();

118:             revert Errors.InvalidFeeAmounts();
```

- [contracts/src/factory/AaveHyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/AaveHyperdriveFactory.sol)

```solidity
File: contracts/src/factory/AaveHyperdriveFactory.sol

66:             revert Errors.NotPayable();

76:             revert Errors.InvalidToken();
```

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

67:         if (msg.sender != governance) revert Errors.Unauthorized();

143:         if (_contribution == 0) revert Errors.InvalidContribution();

180:                 revert Errors.TransferFailed();
```

- [contracts/src/factory/StethHyperdriveDeployer.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/StethHyperdriveDeployer.sol)

```solidity
File: contracts/src/factory/StethHyperdriveDeployer.sol

50:             revert Errors.InvalidBaseToken();
```

- [contracts/src/instances/AaveHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/AaveHyperdrive.sol)

```solidity
File: contracts/src/instances/AaveHyperdrive.sol

40:             revert Errors.InvalidInitialSharePrice();

69:                 revert Errors.TransferFailed();

116:             revert Errors.NoAssetsToWithdraw();
```

- [contracts/src/instances/DsrHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdrive.sol)

```solidity
File: contracts/src/instances/DsrHyperdrive.sol

44:             revert Errors.InvalidBaseToken();

47:             revert Errors.InvalidInitialSharePrice();

66:             revert Errors.UnsupportedToken();

76:             revert Errors.TransferFailed();

110:             revert Errors.UnsupportedToken();
```

- [contracts/src/instances/ERC4626Hyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/ERC4626Hyperdrive.sol)

```solidity
File: contracts/src/instances/ERC4626Hyperdrive.sol

43:             revert Errors.InvalidInitialSharePrice();

46:             revert Errors.InvalidBaseToken();

74:                 revert Errors.TransferFailed();

92:                 revert Errors.TransferFailed();

117:                 revert Errors.TransferFailed();
```

- [contracts/src/instances/StethHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/StethHyperdrive.sol)

```solidity
File: contracts/src/instances/StethHyperdrive.sol

47:             revert Errors.InvalidInitialSharePrice();

69:                 revert Errors.TransferFailed();

77:                     revert Errors.TransferFailed();

92:                 revert Errors.NotPayable();

102:                 revert Errors.TransferFailed();

127:             revert Errors.UnsupportedToken();
```

- [contracts/src/libraries/AssetId.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/AssetId.sol)

```solidity
File: contracts/src/libraries/AssetId.sol

42:             revert Errors.InvalidTimestamp();
```

- [contracts/src/libraries/FixedPointMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/FixedPointMath.sol)

```solidity
File: contracts/src/libraries/FixedPointMath.sol

26:         if (c < a) revert Errors.FixedPointMath_AddOverflow();

37:         if (b > a) revert Errors.FixedPointMath_SubOverflow();

173:                 revert Errors.FixedPointMath_InvalidExponent();

235:         if (x <= 0) revert Errors.FixedPointMath_NegativeOrZeroInput();

244:             if (x < 0) revert Errors.FixedPointMath_NegativeInput();
```

- [contracts/src/token/BondWrapper.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/BondWrapper.sol)

```solidity
File: contracts/src/token/BondWrapper.sol

41:             revert Errors.MintPercentTooHigh();

69:         if (maturityTime <= block.timestamp) revert Errors.BondMatured();

133:         if (receivedAmount < mintedFromBonds) revert Errors.InsufficientPrice();

145:         if (userFunds < minOutput) revert Errors.OutputLimit();

149:         if (!success) revert Errors.TransferFailed();

157:         if (maturityTime > block.timestamp) revert Errors.BondNotMatured();

184:         if (!success) revert Errors.TransferFailed();
```

- [contracts/src/token/ERC20Forwarder.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/ERC20Forwarder.sol)

```solidity
File: contracts/src/token/ERC20Forwarder.sol

197:         if (block.timestamp > deadline) revert Errors.ExpiredDeadline();

199:         if (owner == address(0)) revert Errors.RestrictedZeroAddress();

220:         if (signer != owner) revert Errors.InvalidSignature();
```

- [contracts/src/token/MultiToken.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/MultiToken.sol)

```solidity
File: contracts/src/token/MultiToken.sol

61:             revert Errors.InvalidERC20Bridge();

253:             revert Errors.RestrictedZeroAddress();

257:             revert Errors.BatchInputLengthMismatch();

288:         if (block.timestamp > deadline) revert Errors.ExpiredDeadline();

290:         if (owner == address(0)) revert Errors.RestrictedZeroAddress();

311:         if (signer != owner) revert Errors.InvalidSignature();
```

### 3.17. "Unused Return"

These function calls return a value, but the code isn't checking them.

- [AaveHyperdrive._withdraw()](contracts/src/instances/AaveHyperdrive.sol#96-132) ignores return value by [pool.withdraw()](contracts/src/instances/AaveHyperdrive.sol#125)
- [BondWrapper.sweep()](contracts/src/token/BondWrapper.sol#155-174) ignores return value by [hyperdrive.closeLong()](contracts/src/token/BondWrapper.sol#166-172)

### 3.18. Contract does not follow the Solidity style guide's suggested layout ordering

The [style guide](https://docs.soliditylang.org/en/v0.8.16/style-guide.html#order-of-layout) says that, within a contract, the ordering should be:

1) Type declarations
2) State variables
3) Events
4) Modifiers
5) Functions

However, the contract(s) below do not follow this ordering

- [contracts/src/HyperdriveBase.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveBase.sol)

```solidity
File: contracts/src/HyperdriveBase.sol

1: Current order:
   UsingForDirective.FixedPointMath
   UsingForDirective.SafeCast
   EventDefinition.Initialize
   EventDefinition.AddLiquidity
   EventDefinition.RemoveLiquidity
   EventDefinition.RedeemWithdrawalShares
   EventDefinition.OpenLong
   EventDefinition.OpenShort
   EventDefinition.CloseLong
   EventDefinition.CloseShort
   FunctionDefinition.constructor
   FunctionDefinition._checkMessageValue
   FunctionDefinition._deposit
   FunctionDefinition._withdraw
   FunctionDefinition._pricePerShare
   FunctionDefinition.setPauser
   FunctionDefinition.setGovernance
   FunctionDefinition.pause
   ModifierDefinition.isNotPaused
   FunctionDefinition.checkpoint
   FunctionDefinition._applyCheckpoint
   FunctionDefinition.collectGovernanceFee
   FunctionDefinition._calculateTimeRemaining
   FunctionDefinition._calculateTimeRemainingScaled
   FunctionDefinition._latestCheckpoint
   FunctionDefinition._calculateFeesOutGivenSharesIn
   FunctionDefinition._calculateFeesOutGivenBondsIn
   FunctionDefinition._calculateFeesInGivenBondsOut
   
   Suggested order:
   UsingForDirective.FixedPointMath
   UsingForDirective.SafeCast
   EventDefinition.Initialize
   EventDefinition.AddLiquidity
   EventDefinition.RemoveLiquidity
   EventDefinition.RedeemWithdrawalShares
   EventDefinition.OpenLong
   EventDefinition.OpenShort
   EventDefinition.CloseLong
   EventDefinition.CloseShort
   ModifierDefinition.isNotPaused
   FunctionDefinition.constructor
   FunctionDefinition._checkMessageValue
   FunctionDefinition._deposit
   FunctionDefinition._withdraw
   FunctionDefinition._pricePerShare
   FunctionDefinition.setPauser
   FunctionDefinition.setGovernance
   FunctionDefinition.pause
   FunctionDefinition.checkpoint
   FunctionDefinition._applyCheckpoint
   FunctionDefinition.collectGovernanceFee
   FunctionDefinition._calculateTimeRemaining
   FunctionDefinition._calculateTimeRemainingScaled
   FunctionDefinition._latestCheckpoint
   FunctionDefinition._calculateFeesOutGivenSharesIn
   FunctionDefinition._calculateFeesOutGivenBondsIn
   FunctionDefinition._calculateFeesInGivenBondsOut
```

- [contracts/src/HyperdriveStorage.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveStorage.sol)

```solidity
File: contracts/src/HyperdriveStorage.sol

1: Current order:
   VariableDeclaration._baseToken
   VariableDeclaration._checkpointDuration
   VariableDeclaration._positionDuration
   VariableDeclaration._timeStretch
   VariableDeclaration._initialSharePrice
   VariableDeclaration._marketState
   VariableDeclaration._withdrawPool
   VariableDeclaration._curveFee
   VariableDeclaration._flatFee
   VariableDeclaration._governanceFee
   VariableDeclaration._checkpoints
   VariableDeclaration._pausers
   VariableDeclaration._governanceFeesAccrued
   VariableDeclaration._governance
   VariableDeclaration._feeCollector
   VariableDeclaration._updateGap
   StructDefinition.OracleData
   VariableDeclaration._buffer
   VariableDeclaration._oracle
   FunctionDefinition.constructor
   
   Suggested order:
   StructDefinition.OracleData
   VariableDeclaration._baseToken
   VariableDeclaration._checkpointDuration
   VariableDeclaration._positionDuration
   VariableDeclaration._timeStretch
   VariableDeclaration._initialSharePrice
   VariableDeclaration._marketState
   VariableDeclaration._withdrawPool
   VariableDeclaration._curveFee
   VariableDeclaration._flatFee
   VariableDeclaration._governanceFee
   VariableDeclaration._checkpoints
   VariableDeclaration._pausers
   VariableDeclaration._governanceFeesAccrued
   VariableDeclaration._governance
   VariableDeclaration._feeCollector
   VariableDeclaration._updateGap
   VariableDeclaration._buffer
   VariableDeclaration._oracle
   FunctionDefinition.constructor
```

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

1: Current order:
   VariableDeclaration.hyperdriveDeployer
   VariableDeclaration.governance
   VariableDeclaration.isOfficial
   VariableDeclaration.versionCounter
   VariableDeclaration.hyperdriveGovernance
   VariableDeclaration.feeCollector
   VariableDeclaration.fees
   VariableDeclaration.defaultPausers
   VariableDeclaration.ETH
   FunctionDefinition.constructor
   ModifierDefinition.onlyGovernance
   FunctionDefinition.updateImplementation
   FunctionDefinition.updateGovernance
   FunctionDefinition.updateHyperdriveGovernance
   FunctionDefinition.updateFeeCollector
   FunctionDefinition.updateFees
   FunctionDefinition.updateDefaultPausers
   FunctionDefinition.deployAndInitialize
   FunctionDefinition.deployDataProvider
   
   Suggested order:
   VariableDeclaration.hyperdriveDeployer
   VariableDeclaration.governance
   VariableDeclaration.isOfficial
   VariableDeclaration.versionCounter
   VariableDeclaration.hyperdriveGovernance
   VariableDeclaration.feeCollector
   VariableDeclaration.fees
   VariableDeclaration.defaultPausers
   VariableDeclaration.ETH
   ModifierDefinition.onlyGovernance
   FunctionDefinition.constructor
   FunctionDefinition.updateImplementation
   FunctionDefinition.updateGovernance
   FunctionDefinition.updateHyperdriveGovernance
   FunctionDefinition.updateFeeCollector
   FunctionDefinition.updateFees
   FunctionDefinition.updateDefaultPausers
   FunctionDefinition.deployAndInitialize
   FunctionDefinition.deployDataProvider
```

- [contracts/src/interfaces/IERC20.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/interfaces/IERC20.sol)

```solidity
File: contracts/src/interfaces/IERC20.sol

1: Current order:
   FunctionDefinition.name
   FunctionDefinition.symbol
   FunctionDefinition.decimals
   EventDefinition.Transfer
   EventDefinition.Approval
   FunctionDefinition.totalSupply
   FunctionDefinition.balanceOf
   FunctionDefinition.transfer
   FunctionDefinition.allowance
   FunctionDefinition.approve
   FunctionDefinition.transferFrom
   
   Suggested order:
   EventDefinition.Transfer
   EventDefinition.Approval
   FunctionDefinition.name
   FunctionDefinition.symbol
   FunctionDefinition.decimals
   FunctionDefinition.totalSupply
   FunctionDefinition.balanceOf
   FunctionDefinition.transfer
   FunctionDefinition.allowance
   FunctionDefinition.approve
   FunctionDefinition.transferFrom
```

- [contracts/src/libraries/AssetId.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/AssetId.sol)

```solidity
File: contracts/src/libraries/AssetId.sol

1: Current order:
   VariableDeclaration._LP_ASSET_ID
   VariableDeclaration._WITHDRAWAL_SHARE_ASSET_ID
   EnumDefinition.AssetIdPrefix
   FunctionDefinition.encodeAssetId
   FunctionDefinition.decodeAssetId
   
   Suggested order:
   EnumDefinition.AssetIdPrefix
   VariableDeclaration._LP_ASSET_ID
   VariableDeclaration._WITHDRAWAL_SHARE_ASSET_ID
   FunctionDefinition.encodeAssetId
   FunctionDefinition.decodeAssetId
```

- [contracts/src/libraries/HyperdriveMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/HyperdriveMath.sol)

```solidity
File: contracts/src/libraries/HyperdriveMath.sol

1: Current order:
   UsingForDirective.FixedPointMath
   FunctionDefinition.calculateSpotPrice
   FunctionDefinition.calculateAPRFromReserves
   FunctionDefinition.calculateInitialBondReserves
   FunctionDefinition.calculateOpenLong
   FunctionDefinition.calculateCloseLong
   FunctionDefinition.calculateOpenShort
   FunctionDefinition.calculateCloseShort
   StructDefinition.MaxLongResult
   FunctionDefinition.calculateMaxLong
   FunctionDefinition.calculateMaxShort
   StructDefinition.PresentValueParams
   FunctionDefinition.calculatePresentValue
   FunctionDefinition.calculateShortProceeds
   FunctionDefinition.calculateShortInterest
   FunctionDefinition.calculateBaseVolume
   
   Suggested order:
   UsingForDirective.FixedPointMath
   StructDefinition.MaxLongResult
   StructDefinition.PresentValueParams
   FunctionDefinition.calculateSpotPrice
   FunctionDefinition.calculateAPRFromReserves
   FunctionDefinition.calculateInitialBondReserves
   FunctionDefinition.calculateOpenLong
   FunctionDefinition.calculateCloseLong
   FunctionDefinition.calculateOpenShort
   FunctionDefinition.calculateCloseShort
   FunctionDefinition.calculateMaxLong
   FunctionDefinition.calculateMaxShort
   FunctionDefinition.calculatePresentValue
   FunctionDefinition.calculateShortProceeds
   FunctionDefinition.calculateShortInterest
   FunctionDefinition.calculateBaseVolume
```

- [contracts/src/token/MultiToken.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/MultiToken.sol)

```solidity
File: contracts/src/token/MultiToken.sol

1: Current order:
   VariableDeclaration.DOMAIN_SEPARATOR
   VariableDeclaration.PERMIT_TYPEHASH
   FunctionDefinition.constructor
   ModifierDefinition.onlyLinker
   FunctionDefinition._deriveForwarderAddress
   FunctionDefinition.transferFrom
   FunctionDefinition.transferFromBridge
   FunctionDefinition._transferFrom
   FunctionDefinition.setApprovalForAll
   FunctionDefinition.setApproval
   FunctionDefinition.setApprovalBridge
   FunctionDefinition._setApproval
   FunctionDefinition._mint
   FunctionDefinition._burn
   FunctionDefinition.batchTransferFrom
   FunctionDefinition.permitForAll
   
   Suggested order:
   VariableDeclaration.DOMAIN_SEPARATOR
   VariableDeclaration.PERMIT_TYPEHASH
   ModifierDefinition.onlyLinker
   FunctionDefinition.constructor
   FunctionDefinition._deriveForwarderAddress
   FunctionDefinition.transferFrom
   FunctionDefinition.transferFromBridge
   FunctionDefinition._transferFrom
   FunctionDefinition.setApprovalForAll
   FunctionDefinition.setApproval
   FunctionDefinition.setApprovalBridge
   FunctionDefinition._setApproval
   FunctionDefinition._mint
   FunctionDefinition._burn
   FunctionDefinition.batchTransferFrom
   FunctionDefinition.permitForAll
```

### 3.19. Use Underscores for Number Literals (add an underscore every 3 digits)

- [contracts/src/libraries/FixedPointMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/FixedPointMath.sol)

```solidity
File: contracts/src/libraries/FixedPointMath.sol

172:             if (x >= 135305999368893231589)

183:             int256 k = ((x << 96) / 54916777467707473351141471128 + 2 ** 95) >>

185:             x = x - k * 54916777467707473351141471128;

191:             int256 y = x + 1346386616545796478920950773328;

192:             y = ((y * x) >> 96) + 57155421227552351082224309758442;

193:             int256 p = y + x - 94201549194550492254356042504812;

194:             p = ((p * y) >> 96) + 28719021644029726153956944680412240;

198:             int256 q = x - 2855989394907223263936484059900;

199:             q = ((q * x) >> 96) + 50020603652535783019961831881945;

200:             q = ((q * x) >> 96) - 533845033583426703283633433725380;

201:             q = ((q * x) >> 96) + 3604857256930695427073651918091429;

202:             q = ((q * x) >> 96) - 14423608567350463180887372962807573;

203:             q = ((q * x) >> 96) + 26449188498355588339934803723976023;

223:                     3822833074963236453042738258902158003155416615667) >>

271:             int256 p = x + 3273285459638523848632254066296;

272:             p = ((p * x) >> 96) + 24828157081833163892658089445524;

273:             p = ((p * x) >> 96) + 43456485725739037958740375743393;

274:             p = ((p * x) >> 96) - 11111509109440967052023855526967;

275:             p = ((p * x) >> 96) - 45023709667254063763336534515857;

276:             p = ((p * x) >> 96) - 14706773417378608786704636184526;

281:             int256 q = x + 5573035233440673466300451813936;

282:             q = ((q * x) >> 96) + 71694874799317883764090561454958;

283:             q = ((q * x) >> 96) + 283447036172924575727196451306956;

284:             q = ((q * x) >> 96) + 401686690394027663651624208769553;

285:             q = ((q * x) >> 96) + 204048457590392012362485061816622;

286:             q = ((q * x) >> 96) + 31853899698501571402653359427138;

287:             q = ((q * x) >> 96) + 909429971244387300277376558375;

305:             r *= 1677202110996718588342820967067443963516166;

308:                 16597577552685614221487285958193947469193820559219878177908093499208371 *

311:             r += 600920179829731861736702779321621459595472258049074101567377883020018308;
```

- [contracts/src/token/BondWrapper.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/BondWrapper.sol)

```solidity
File: contracts/src/token/BondWrapper.sol

40:         if (_mintPercent >= 10000) {

81:         uint256 mintAmount = (amount * mintPercent) / 10000;

131:         uint256 mintedFromBonds = (amount * mintPercent) / 10000;
```

### 3.20. Internal and private variables and functions names should begin with an underscore

According to the Solidity Style Guide, Non-`external` variable and function names should begin with an [underscore](https://docs.soliditylang.org/en/latest/style-guide.html#underscore-prefix-for-non-external-functions-and-variables)

- [contracts/src/HyperdriveTWAP.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveTWAP.sol)

```solidity
File: contracts/src/HyperdriveTWAP.sol

23:     function recordPrice(uint256 price) internal {
```

- [contracts/src/factory/AaveHyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/AaveHyperdriveFactory.sol)

```solidity
File: contracts/src/factory/AaveHyperdriveFactory.sol

99:     function deployDataProvider(
```

- [contracts/src/factory/DsrHyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/DsrHyperdriveFactory.sol)

```solidity
File: contracts/src/factory/DsrHyperdriveFactory.sol

54:     function deployDataProvider(
```

- [contracts/src/factory/ERC4626HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/ERC4626HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/ERC4626HyperdriveFactory.sol

54:     function deployDataProvider(
```

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

209:     function deployDataProvider(
```

- [contracts/src/factory/StethHyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/StethHyperdriveFactory.sol)

```solidity
File: contracts/src/factory/StethHyperdriveFactory.sol

56:     function deployDataProvider(
```

- [contracts/src/instances/AaveHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/AaveHyperdrive.sol)

```solidity
File: contracts/src/instances/AaveHyperdrive.sol

19:     uint256 internal totalShares;
```

- [contracts/src/instances/DsrHyperdrive.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdrive.sol)

```solidity
File: contracts/src/instances/DsrHyperdrive.sol

16:     uint256 internal totalShares;

166:     function chi() internal view returns (uint256) {
```

- [contracts/src/instances/DsrHyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/instances/DsrHyperdriveDataProvider.sol)

```solidity
File: contracts/src/instances/DsrHyperdriveDataProvider.sol

99:     function chi() internal view returns (uint256) {
```

- [contracts/src/libraries/AssetId.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/AssetId.sol)

```solidity
File: contracts/src/libraries/AssetId.sol

33:     function encodeAssetId(

54:     function decodeAssetId(
```

- [contracts/src/libraries/FixedPointMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/FixedPointMath.sol)

```solidity
File: contracts/src/libraries/FixedPointMath.sol

22:     function add(uint256 a, uint256 b) internal pure returns (uint256) {

34:     function sub(uint256 a, uint256 b) internal pure returns (uint256) {

47:     function mulDivDown(

70:     function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {

78:     function divDown(uint256 a, uint256 b) internal pure returns (uint256) {

87:     function mulDivUp(

114:     function mulUp(uint256 a, uint256 b) internal pure returns (uint256) {

122:     function divUp(uint256 a, uint256 b) internal pure returns (uint256) {

131:     function pow(uint256 x, uint256 y) internal pure returns (uint256) {

164:     function exp(int256 x) internal pure returns (int256 r) {

234:     function ln(int256 x) internal pure returns (int256) {

323:     function updateWeightedAverage(
```

- [contracts/src/libraries/HyperdriveMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/HyperdriveMath.sol)

```solidity
File: contracts/src/libraries/HyperdriveMath.sol

27:     function calculateSpotPrice(

50:     function calculateAPRFromReserves(

91:     function calculateInitialBondReserves(

118:     function calculateOpenLong(

152:     function calculateCloseLong(

217:     function calculateOpenShort(

248:     function calculateCloseShort(

308:     function calculateMaxLong(

424:     function calculateMaxShort(

475:     function calculatePresentValue(

581:     function calculateShortProceeds(

618:     function calculateShortInterest(

649:     function calculateBaseVolume(
```

- [contracts/src/libraries/SafeCast.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/SafeCast.sol)

```solidity
File: contracts/src/libraries/SafeCast.sol

8:     function toUint128(uint256 x) internal pure returns (uint128 y) {
```

- [contracts/src/libraries/YieldSpaceMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/YieldSpaceMath.sol)

```solidity
File: contracts/src/libraries/YieldSpaceMath.sol

278:     function calculateBondsInGivenSharesOut(

309:     function calculateBondsOutGivenSharesIn(

341:         uint256 z,

374:         uint256 z,

409:         uint256 t,

439:         uint256 mu,
```

### 3.21. Usage of floating `pragma` is not recommended

- [contracts/src/interfaces/IERC20.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/interfaces/IERC20.sol)

```solidity
File: contracts/src/interfaces/IERC20.sol

4: pragma solidity ^0.8.19;
```

- [contracts/src/interfaces/IMultiTokenMetadata.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/interfaces/IMultiTokenMetadata.sol)

```solidity
File: contracts/src/interfaces/IMultiTokenMetadata.sol

2: pragma solidity ^0.8.18;
```

- [contracts/src/libraries/SafeCast.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/SafeCast.sol)

```solidity
File: contracts/src/libraries/SafeCast.sol

2: pragma solidity >=0.8.0;
```

### 3.22. Variables need not be initialized to zero

The default value for variables is zero, so initializing them to zero is superfluous.

- [contracts/src/HyperdriveBase.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveBase.sol)

```solidity
File: contracts/src/HyperdriveBase.sol

99:         for (uint256 i = 0; i < _config.oracleSize; i++) {
```

- [contracts/src/HyperdriveDataProvider.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/HyperdriveDataProvider.sol)

```solidity
File: contracts/src/HyperdriveDataProvider.sol

114:         for (uint256 i = 0; i < _slots.length; i++) {
```

- [contracts/src/factory/HyperdriveFactory.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/factory/HyperdriveFactory.sol)

```solidity
File: contracts/src/factory/HyperdriveFactory.sol

191:         for (uint256 i = 0; i < defaultPausers.length; i++) {
```

- [contracts/src/libraries/HyperdriveMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/HyperdriveMath.sol)

```solidity
File: contracts/src/libraries/HyperdriveMath.sol

364:         for (uint256 i = 0; i < _maxIterations; i++) {
```

- [contracts/src/token/BondWrapper.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/BondWrapper.sol)

```solidity
File: contracts/src/token/BondWrapper.sol

195:         for (uint256 i = 0; i < maturityTimes.length; i++) {
```

- [contracts/src/token/MultiToken.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/token/MultiToken.sol)

```solidity
File: contracts/src/token/MultiToken.sol

260:         for (uint256 i = 0; i < ids.length; i++) {
```

### 3.23. The following unchecked statements are not documented

There should never exist any doubt in the absence of risk of overflows when using `unchecked` statements. Consider documenting the following:

- [contracts/src/libraries/FixedPointMath.sol](https://github.com/Certora/element-fi-hyperdrive/blob/main/contracts/src/libraries/FixedPointMath.sol)

```solidity
File: contracts/src/libraries/FixedPointMath.sol

165:         unchecked {

241:         unchecked {
```