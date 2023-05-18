pragma solidity ^0.8.18;

import {DsrManager} from "../../contracts/src/interfaces/IMaker.sol";
import "./DummyDAI.sol";
import "./DummyPot.sol";


contract DummyDsrManager is DsrManager {
    DummyPot public potInstance;
    DummyDAI public daiInstance;
    
    uint256 public _supplyPieTotal;

    mapping (address => uint256) public _pieOf;

    // Used to simulate dai because we only need balanceOf() and transfer() functions. 
    // We can simulate this behavior here for simplicity
    // Also, no instances of dai is used in the contract.
    // mapping (address => uint256) public _daiBalance;

    uint256 constant RAY = 10 ** 27;

    // keep it to round up (Solidity only rounds down).
    function rdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds up
        z = (x * RAY + y - 1) / y;
    }

    constructor() public {
        _supplyPieTotal = 0;
    }

    function dai() external view returns (address) {
        return address(daiInstance);
    }

    function pot() external view returns (address) {
        return address(potInstance);
    }

    function pieOf(address user) external view returns (uint256) {
        return _pieOf[user];
    }

    function daiBalance(address user) external returns (uint256) {
        return daiInstance.balanceOf(user);
    }

    // dst ... owner getting new minted pie shares
    // wad ... amount payed for pie
    function join(address dst, uint256 wad) external {
        uint256 chi = (block.timestamp > potInstance.rho()) ? potInstance.drip() : potInstance.chi();
            
        uint256 pie = wad / chi;
        _pieOf[dst] += pie;
        _supplyPieTotal += pie;

        daiInstance.transferFrom(msg.sender, address(this), wad);
    }

    function exit(address dst, uint256 wad) external {
        uint256 chi = (block.timestamp > potInstance.rho()) ? potInstance.drip() : potInstance.chi();

        uint256 userPie = rdivup(wad, chi);

        require(_pieOf[msg.sender] >= userPie, "insufficient-balance");

        _pieOf[msg.sender] -= userPie;
        _supplyPieTotal -= userPie;

        uint256 returnedAmt = userPie * chi;
        daiInstance.transferFrom(address(this), dst, returnedAmt);
    }

    function exitAll(address dst) external {
        uint256 chi = (block.timestamp > potInstance.rho()) ? potInstance.drip() : potInstance.chi();

        uint256 allUserPie = _pieOf[msg.sender];

        _pieOf[msg.sender] = 0;
        _supplyPieTotal -= allUserPie;

        uint256 returnedAmt = chi * allUserPie;
        daiInstance.transferFrom(address(this), dst, returnedAmt);
    }
}