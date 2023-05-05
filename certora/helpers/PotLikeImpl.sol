interface PotLike {
    function vat() external view returns (address);
    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;
}


contract PotLikeImpl is PotLike {
    address _pot;

    // TODO: Delete these munged values
    address randAddress;
    uint256 randUint1;
    uint256 randUint2;
    uint256 randUint3;
    constructor(address pot) {
        _pot = pot;
    }
    function vat() external view returns (address) {
        //TODO: implement
        return randAddress;
    }
    function chi() external view returns (uint256) {
        //TODO: implement
        return randUint1;
    }
    function rho() external view returns (uint256) {
        //TODO: implement
        return randUint2;
    }
    function drip() external returns (uint256) {
        //TODO: implement
        return randUint3;
    }
    function join(uint256) external {
        //TODO: implement
    }
    function exit(uint256) external {
        //TODO: implement
    }
}
