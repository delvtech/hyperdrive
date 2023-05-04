import {DsrManager} from "../../contracts/src/interfaces/IMaker.sol";
import {DummyERC20A} from "./DummyERC20A.sol";
import {DummyERC20B} from "./DummyERC20B.sol";


interface VatLike {
    function hope(address) external;
}

interface JoinLike {
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

contract JoinToken is DummyERC20B

interface PotLike {
    function vat() external view returns (address);
    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;
}

contract DummyDsrManager is DsrManager {
    PotLike public _pot;
    DummyERC20A  public _dai;
    JoinLike public _daiJoin;

    uint256 public supply;

    mapping (address => uint256) public _pieOf;
    // address randAddress1;
    // address randAddress2;
    // uint256 randNumber1;
    // uint256 randNumber2;




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
        _pot = PotLike(pot_);
        _daiJoin = JoinLike(daiJoin_);
        _dai = DummyERC20A("DummyERC20A", "DummySymbolA");

        VatLike vat = VatLike(_pot.vat());
        vat.hope(address(_daiJoin));
        vat.hope(address(_pot));
        _dai.approve(address(_daiJoin), uint256(-1));
    }


    function dai() external view returns (address) { return (address(_dai); }

    function pot() external view returns (address) { return (address(_pot); }

    function pieOf(address usr) external view returns (uint256) {
        return _pieOf[usr];
    }

    function daiBalance(address usr) external returns (uint256 wad) {
        uint256 chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        wad = rmul(chi, _pieOf[usr]);
    }

    function join(address dst, uint256 wad) external {
        uint256 chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        uint256 pie = rdiv(wad, chi);
        _pieOf[dst] = add(_pieOf[dst], pie);
        supply = add(supply, pie);

        _dai.transferFrom(msg.sender, address(this), wad);
        _daiJoin.join(address(this), wad);
        _pot.join(pie);
    }

    function exit(address dst, uint256 wad) external {
        uint256 chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        uint256 pie = rdivup(wad, chi);

        require(_pieOf[msg.sender] >= pie, "insufficient-balance");

        _pieOf[msg.sender] = sub(_pieOf[msg.sender], pie);
        supply = sub(supply, pie);

        _pot.exit(pie);
        uint256 amt = rmul(chi, pie);
        _daiJoin.exit(dst, amt);
    }

    function exitAll(address dst) external {
        uint256 chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        uint256 pie = _pieOf[msg.sender];

        _pieOf[msg.sender] = 0;
        supply = sub(supply, pie);

        _pot.exit(pie);
        uint256 amt = rmul(chi, pie);
        _daiJoin.exit(dst, amt);
    }
}