import "erc20.spec";
import "Sanity.spec";
use rule sanity;

methods {
    // Hyperdrive
    function _.initialize(uint256, uint256, address, bool) external => DISPATCHER(true);
    // DsrManager
    function _.join(address, uint256) external => DISPATCHER(true);
    function _.daiBalance(address) external => DISPATCHER(true);
}
