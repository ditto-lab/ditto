pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../TimeCurve.sol";

contract TimeCurveTest is Test {

    constructor() {}

    function testTimeCurve() public {

        for (uint256 i = 1; i < 256; i++) {
            uint256 x = TimeCurve.calc(i);
            // console.log(x);
        }
    }

}
