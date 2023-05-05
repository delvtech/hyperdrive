import {DsrManager} from "../../contracts/src/interfaces/IMaker.sol";


contract DummyDsrManager is DsrManager {
    uint256 public _supplyPieTotal;
    uint256 public _chi;

    mapping (address => uint256) public _pieOf;
    mapping (address => uint256) public _daiBalance;

    uint256 constant RAY = 10 ** 27;
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = mul(x, y) / RAY;
    }
    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = mul(x, RAY) / y;
    }
    function rdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds up
        z = add(mul(x, RAY), sub(y, 1)) / y;
    }

    constructor() public {
        _chi = 10;
        _supplyPieTotal = 0;
    }

    function dai() external view returns (address) {
        return address(0);
    }

    function pot() external view returns (address) {
        return address(0);
    }

    function pieOf(address usr) external view returns (uint256) {
        return _pieOf[usr];
    }

    function daiBalance(address usr) external returns (uint256) {
        return _daiBalance[usr];
    }

    // dst ... owner getting new minted pie shares
    // wad ... amount payed for pie
    function join(address dst, uint256 wad) external {
        uint256 pie = rdiv(wad, _chi);
        _pieOf[dst] = add(_pieOf[dst], pie);
        _supplyPieTotal = add(_supplyPieTotal, pie);

        _daiBalance[msg.sender] = sub(_daiBalance[msg.sender], wad);
        _daiBalance[address(this)] = add(_daiBalance[address(this)], wad);
    }

    function exit(address dst, uint256 wad) external {
        uint256 userPie = rdivup(wad, _chi);

        require(_pieOf[msg.sender] >= userPie, "insufficient-balance");

        _pieOf[msg.sender] = sub(_pieOf[msg.sender], userPie);
        _supplyPieTotal = sub(_supplyPieTotal, userPie);

        uint256 returnedAmt = rmul(_chi, userPie);
        _daiBalance[dst] = add(_daiBalance[dst], returnedAmt);
    }

    function exitAll(address dst) external {
        uint256 allUserPie = _pieOf[msg.sender];

        _pieOf[msg.sender] = 0;
        _supplyPieTotal = sub(_supplyPieTotal, allUserPie);

        uint256 returnedAmt = rmul(_chi, allUserPie);
        _daiBalance[dst] = add(_daiBalance[dst], returnedAmt);
    }
}