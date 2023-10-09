// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockBondWrapper } from "contracts/test/MockBondWrapper.sol";
import { MockMultiToken, IMockMultiToken } from "contracts/test/MockMultiToken.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { MultiTokenDataProvider } from "contracts/src/token/MultiTokenDataProvider.sol";
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
        bool _asUnderlying,
        bytes _extraData
    );

    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external returns (uint256) {
        emit __CloseLong__(
            _maturityTime,
            _bondAmount,
            _minOutput,
            _destination,
            _asUnderlying,
            _extraData
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
            9000,
            "Bond",
            "BND"
        );

        baseToken.mint(address(bondWrapper), 10e18);

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

        vm.warp(365 days + 1);

        // Encode the asset ID
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            365 days
        );

        uint256 deposited = bondWrapper.deposits(alice, assetId);

        vm.expectRevert(IHyperdrive.OutputLimit.selector);
        bondWrapper.close(
            365 days,
            deposited,
            true,
            bob,
            deposited + 1,
            new bytes(0)
        );

        // Should pass when you get the right amount
        bondWrapper.close(
            365 days,
            deposited,
            true,
            bob,
            deposited,
            new bytes(0)
        );
    }

    function test_sweepAndRedeem() public {
        // Alice mints some BondWrapper tokens.
        vm.startPrank(alice);
        uint256 balance = bondWrapper.balanceOf(alice);
        assertEq(balance, 0);
        bondWrapper.mint(365 days, 1e18, alice);
        balance = bondWrapper.balanceOf(bob);

        // 1 year passes.
        vm.warp(365 days);

        // Alice sweeps and redeems all of her BondWrapper tokens.
        uint256[] memory maturityTimes = new uint256[](1);
        maturityTimes[0] = 365 days;
        bondWrapper.sweepAndRedeem(maturityTimes, balance, new bytes[](1));
        balance = bondWrapper.balanceOf(bob);
        assertEq(balance, 0);
    }

    function test_sweepAndRedeem_inputLengthMismatch() external {
        vm.startPrank(alice);

        // maturityTimes.length > extraDatas.length
        uint256[] memory maturityTimes = new uint256[](2);
        bytes[] memory extraDatas = new bytes[](1);
        vm.expectRevert(IHyperdrive.InputLengthMismatch.selector);
        bondWrapper.sweepAndRedeem(maturityTimes, 10e18, extraDatas);

        // maturityTimes.length < extraDatas.length
        maturityTimes = new uint256[](1);
        extraDatas = new bytes[](2);
        vm.expectRevert(IHyperdrive.InputLengthMismatch.selector);
        bondWrapper.sweepAndRedeem(maturityTimes, 10e18, extraDatas);
    }
}
