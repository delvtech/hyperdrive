/// @dev Methods block of the HyperdriveStorageGetters methods.
/// Note that the Hyperdrive instance name (e.g. AaveHyperdrive) needs to be modified
/// based on the contract being verified.
/// This change applies to the prefix of the struct.
methods {
    /// MultiToken Storage
    function factory() external returns (address) envfree;
    function linkerCodeHash() external returns (bytes32) envfree; 
    function balanceOfByToken(uint256, address) external returns (uint256) envfree;
    function totalSupplyByToken(uint256) external returns (uint256) envfree;
    function isApprovedForAllByToken(address, address) external returns (bool) envfree;
    function perTokenApprovals(uint256, address, address) external returns (uint256) envfree;
    /// Hyperdrive Storage
    function baseToken() external returns (address) envfree;
    function checkpointDuration() external returns (uint256) envfree; 
    function positionDuration() external returns (uint256) envfree;
    function timeStretch() external returns (uint256) envfree; 
    function initialSharePrice() external returns (uint256) envfree; 
    function marketState() external returns (AaveHyperdrive.MarketState memory) envfree;
    function stateShareReserves() external returns (uint128) envfree; 
    function stateBondReserves() external returns (uint128) envfree; 
    function withdrawPool() external returns (AaveHyperdrive.WithdrawPool memory) envfree;
    function curveFee() external returns (uint256) envfree;
    function flatFee() external returns (uint256) envfree;
    function governanceFee() external returns (uint256) envfree;
    function checkPoints(uint256) external returns (AaveHyperdrive.Checkpoint memory) envfree;
    function checkPointSharePrice(uint256) external returns (uint128) envfree;
    function pausers(address) external returns (bool) envfree;
    function governanceFeesAccrued() external returns (uint256) envfree;
    function governance() external returns (address) envfree;
    function updateGap() external returns (uint256) envfree;
}
