import "Sanity.spec";
import "erc20.spec";
use rule sanity;

methods {
    function _.isApprovedForAll(address, address) external => DISPATCHER(true);
    function _.perTokenApprovals(uint256, address, address) external => DISPATCHER(true);
}
