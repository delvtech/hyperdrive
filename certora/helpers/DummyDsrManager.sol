import {DsrManager} from "../../contracts/src/interfaces/IMaker.sol";
import {DummyERC20A} from "./DummyERC20A.sol";
import {DummyERC20B} from "./DummyERC20B.sol";
import {PotLikeImpl} from "./PotLikeImpl.sol";
// import {DummyPot} from "./DummyPot.sol";


interface VatLike {
    function hope(address) external;
}

// Not used as JoinLikeImpl is DummyERC20B
// interface JoinLike {
//     function dai() external view returns (address);
//     function join(address, uint256) external;
//     function exit(address, uint256) external;
// }


// minimal Vat contract based on https://github.com/makerdao/dss/blob/master/src/vat.sol
// TODO: review, that this minimal version is enough.
contract VatLikeImpl is VatLike {
    mapping (address => uint) public wards;
    mapping(address => mapping (address => uint)) public can;
    uint256 public live;  // Active Flag
    function hope(address usr) external { can[msg.sender][usr] = 1; }

    constructor(address usr) public {
        wards[usr] = 1;
        live = 1;
    }
}





contract JoinLikeImpl is DummyERC20B {
    address _dai;
    constructor(address dai) DummyERC20B("Dummy","JoinLikeImpl") {
        _dai = dai;
    }

    function join(address dst, uint256 wad) external {
        //TODO : Add join implementation
    }

    function exit(address, uint256) external {
        //TODO : Add exit implementation
    }

    function dai() external view returns (address) {
        return _dai;
    }
}

contract DummyDsrManager is DsrManager {
    PotLikeImpl  public _pot;
    DummyERC20A  public _dai;
    JoinLikeImpl public _daiJoin;

    uint256 public supply;

    mapping (address => uint256) public _pieOf;

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

    constructor(address pot_, address daiJoin_) public {
        _pot = new PotLikeImpl(pot_);
        _daiJoin = new JoinLikeImpl(daiJoin_);
        _dai = new DummyERC20A("DummyDai", "DummySymbol");

        VatLikeImpl vat = new VatLikeImpl(_pot.vat());
        vat.hope(address(_daiJoin));
        vat.hope(address(_pot));
        //TODO: get MAX_INT from local math libs.
        uint256 MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        _dai.approve(address(_daiJoin), MAX_INT);
    }


    function dai() external view returns (address) { return address(_dai); }

    function pot() external view returns (address) { return address(_pot); }

    function pieOf(address usr) external view returns (uint256) {
        return _pieOf[usr];
    }

    function daiBalance(address usr) external returns (uint256 wad) {
        uint256 chi = (block.timestamp > _pot.rho()) ? _pot.drip() : _pot.chi();
        wad = rmul(chi, _pieOf[usr]);
    }

    function join(address dst, uint256 wad) external {
        uint256 chi = (block.timestamp > _pot.rho()) ? _pot.drip() : _pot.chi();
        uint256 pie = rdiv(wad, chi);
        _pieOf[dst] = add(_pieOf[dst], pie);
        supply = add(supply, pie);

        _dai.transferFrom(msg.sender, address(this), wad);
        _daiJoin.join(address(this), wad);
        _pot.join(pie);
    }

    function exit(address dst, uint256 wad) external {
        uint256 chi = (block.timestamp > _pot.rho()) ? _pot.drip() : _pot.chi();
        uint256 pie = rdivup(wad, chi);

        require(_pieOf[msg.sender] >= pie, "insufficient-balance");

        _pieOf[msg.sender] = sub(_pieOf[msg.sender], pie);
        supply = sub(supply, pie);

        _pot.exit(pie);
        uint256 amt = rmul(chi, pie);
        _daiJoin.exit(dst, amt);
    }

    function exitAll(address dst) external {
        uint256 chi = (block.timestamp > _pot.rho()) ? _pot.drip() : _pot.chi();
        uint256 pie = _pieOf[msg.sender];

        _pieOf[msg.sender] = 0;
        supply = sub(supply, pie);

        _pot.exit(pie);
        uint256 amt = rmul(chi, pie);
        _daiJoin.exit(dst, amt);
    }
}