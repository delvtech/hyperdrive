// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IMultiTokenRead {
    function name(uint256 id) external view returns (string memory);

    function symbol(uint256 id) external view returns (string memory);

    function totalSupply(uint256 id) external view returns (uint256);

    function isApprovedForAll(
        address owner,
        address spender
    ) external view returns (bool);

    function perTokenApprovals(
        uint256 tokenId,
        address owner,
        address spender
    ) external view returns (uint256);

    function balanceOf(
        uint256 tokenId,
        address owner
    ) external view returns (uint256);

    function nonces(address owner) external view returns (uint256);
}
