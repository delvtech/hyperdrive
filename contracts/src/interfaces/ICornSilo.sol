// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IGatewayRouter {
    function getGateway(address) external view returns (address);

    function outboundTransferCustomRefund(
        address _l1Token,
        address _refundTo,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external payable returns (bytes memory);
}

interface ICornSilo {
    // Events
    event TokenDeposited(
        address indexed user,
        address indexed token,
        uint256 assets,
        uint256 shares
    );
    event TokenWithdrawn(
        address indexed user,
        address indexed token,
        uint256 assets,
        uint256 shares
    );
    event TokenBridged(
        address indexed token,
        address indexed user,
        address indexed recipient,
        uint256 amount,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes data
    );

    event BridgeEnabled(address gatewayRouter, address swapFacilityVault);

    // Errors
    error BridgeNotEnabled();
    error BridgeIsEnabled();
    error BridgeIsNotSet();
    error ZeroDeposit(address token);
    error ZeroWithdraw(address token);
    error ZeroShares(address token);
    error ZeroSharesForAnyToken(address account);
    error TokenNotApproved(address token);
    error BitcornMinterAssetMustNotBeApprovedToken(address bitcornMinterAsset);
    error BitcornMustNotBeApprovedToken(address bitcorn);
    error TokenAlreadyApproved(address token);
    error InsufficientShares(
        address token,
        uint256 cachedShares,
        uint256 shares
    );
    error WithdrawalFeeAboveMax(uint256 fee);
    error SharesNotMultipleOfOneSatoshi(
        uint256 bitcornShares,
        uint256 oneSatoshiOfBitcornShares
    );
    error BelowOneSatoshiOfShares(
        uint256 shares,
        uint256 oneSatoshiOfBitcornShares
    );
    error InsufficientBitcornSharesToBridge(
        uint256 cachedShares,
        uint256 requiredShares
    );

    function pause() external;

    function unpause() external;

    function getGatewayRouter()
        external
        view
        returns (IGatewayRouter gatewayRouter);

    function sharesOf(
        address user,
        address token
    ) external view returns (uint256);

    function totalShares(address token) external view returns (uint256);

    function deposit(
        address token,
        uint256 assets
    ) external returns (uint256 shares);

    function depositFor(
        address recipient,
        address token,
        uint256 assets
    ) external returns (uint256 shares);

    function mintAndDepositBitcorn(
        uint256 assets
    ) external returns (uint256 shares);

    function mintAndDepositBitcornFor(
        address recipient,
        uint256 assets
    ) external returns (uint256 shares);

    function redeemToken(
        address token,
        uint256 shares
    ) external returns (uint256 assets);

    function redeemBitcorn(uint256 shares) external returns (uint256 assets);

    function redeemAll()
        external
        returns (
            address[] memory approvedTokens,
            uint256[] memory depositedAssets,
            uint256 bitcornShares,
            uint256 minterAssetReturned
        );

    function enableBridge(
        address gatewayRouter,
        address erc20Inbox,
        address swapFacilityVault
    ) external;

    function bridgeToken(
        address token,
        address recipient,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external;

    function bridgeAllTokens(
        address recipient,
        uint256 cost,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external;

    function addApprovedToken(address token) external;

    function getApprovedTokens() external view returns (address[] memory);

    function fromAssetDecimalsTo18Decimals(
        uint256 amount
    ) external view returns (uint256);

    function from18DecimalsToAssetDecimals(
        uint256 amountIn18Decimals
    ) external view returns (uint256);
}
