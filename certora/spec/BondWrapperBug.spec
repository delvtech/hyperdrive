import "./BondWrapper.spec";


// STATUS - cathces the bug "Unsafe use of transfer()/transferFrom() with IERC20"
rule implementationCorrectness(env e) {
    uint256 maturityTime;
    uint256 amount; uint256 amount2;
    address destination;

    mint(e, maturityTime, amount, destination);
    redeem@withrevert(e, amount2);

    assert lastReverted, "Remember, with great power comes great responsibility.";
}
