import {DsrManager} from "../../contracts/src/interfaces/IMaker.sol";

contract DummyDsrManager is DsrManager {
    address randAddress1;
    address randAddress2;
    uint256 randNumber1;
    uint256 randNumber2;
    function dai() external view returns (address randAddress) {}

    function pot() external view returns (address randAddress) {}

    function pieOf(address) external view returns (uint256 randNumber1) {}

    function daiBalance(address) external returns (uint256 randNumber2) {}

    function join(address, uint256) external {}

    function exit(address, uint256) external {}

    function exitAll(address) external {}
}