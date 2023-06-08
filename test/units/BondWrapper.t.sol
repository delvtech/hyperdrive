// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { MultiTokenDataProvider } from "contracts/src/MultiTokenDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockBondWrapper } from "contracts/test/MockBondWrapper.sol";
import { MockMultiToken, IMockMultiToken } from "contracts/test/MockMultiToken.sol";
import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { BaseTest } from "test/utils/BaseTest.sol";

contract __MockHyperDrive__ is MockMultiToken {
    uint256 __closeLongReturnValue__;

    constructor(
        address _dataProvider,
        address forwarderFactory
    ) MockMultiToken(_dataProvider, bytes32(0), forwarderFactory) {}

    event __CloseLong__(
        uint256 indexed _maturityTime,
        uint256 indexed _bondAmount,
        uint256 indexed _minOutput,
        address _destination,
        bool _asUnderlying
    );

    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256) {
        emit __CloseLong__(
            _maturityTime,
            _bondAmount,
            _minOutput,
            _destination,
            _asUnderlying
        );
        return __closeLongReturnValue__;
    }

    function __setCloseLongReturnValue__(uint256 _value) external {
        __closeLongReturnValue__ = _value;
    }
}

contract BondWrapperTest is BaseTest {
    IMockMultiToken multiToken;
    MockBondWrapper bondWrapper;
    ERC20Mintable baseToken;

    function setUp() public override {
        super.setUp();
        ForwarderFactory forwarderFactory = new ForwarderFactory();

        address dataProvider = address(
            new MultiTokenDataProvider(bytes32(0), address(forwarderFactory))
        );

        __MockHyperDrive__ hyperdrive = new __MockHyperDrive__(
            dataProvider,
            address(forwarderFactory)
        );

        multiToken = IMockMultiToken(
            address(
                new MockMultiToken(
                    dataProvider,
                    bytes32(0),
                    address(forwarderFactory)
                )
            )
        );
        baseToken = new ERC20Mintable();

        bondWrapper = new MockBondWrapper(
            IHyperdrive(address(hyperdrive)),
            IERC20(address(baseToken)),
            1e18,
            "Bond",
            "BND"
        );

        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            365 days
        );

        hyperdrive.__setBalanceOf(assetId, alice, 1e18);

        // Ensure that the bondWrapper contract has been approved by the user
        vm.startPrank(alice);
        hyperdrive.setApprovalForAll(address(bondWrapper), true);
        vm.stopPrank();
    }

    function test_BondWrapperRedeem() public {
        // Ensure that the bondWrapper contract has been approved by the user
        vm.startPrank(alice);
        multiToken.setApprovalForAll(address(bondWrapper), true);

        vm.startPrank(alice);
        uint256 balance = bondWrapper.balanceOf(alice);

        assert(balance == 0);

        bondWrapper.mint(365 days, 1e18, alice);

        balance = bondWrapper.balanceOf(bob);

        bondWrapper.redeem(balance);

        balance = bondWrapper.balanceOf(bob);

        assert(balance == 0);
    }

    function test_bond_wrapper_closeLimit() public {
        // Ensure that the bondWrapper contract has been approved by the user
        vm.startPrank(alice);
        multiToken.setApprovalForAll(address(bondWrapper), true);

        uint256 balance = bondWrapper.balanceOf(alice);

        assert(balance == 0);

        bondWrapper.mint(365 days, 1e18, alice);

        vm.warp(365 days);

        balance = bondWrapper.balanceOf(bob);

        vm.expectRevert(Errors.OutputLimit.selector);
        bondWrapper.close(365 days, balance, true, bob, 1e18 + 1);

        // Should pass when you get the right amount
        bondWrapper.close(365 days, balance, true, bob, 1e18);
    }

    function test_SweepAndRedeem() public {
        vm.startPrank(alice);
        uint256 balance = bondWrapper.balanceOf(alice);

        assert(balance == 0);

        bondWrapper.mint(365 days, 1e18, alice);

        balance = bondWrapper.balanceOf(bob);

        vm.warp(365 days);

        uint256[] memory maturityTimes = new uint256[](1);

        baseToken.mint(address(bondWrapper), type(uint256).max);

        maturityTimes[0] = 365 days;

        bondWrapper.sweepAndRedeem(maturityTimes, balance);

        balance = bondWrapper.balanceOf(bob);

        assert(balance == 0);
    }
}
