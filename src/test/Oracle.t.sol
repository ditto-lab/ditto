// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../Oracle.sol";

contract OracleTest is Test, Oracle {
    uint256 constant INIT_TIME = 1644911858;

    function setUp() public {
        vm.warp(INIT_TIME);
    }

    function testWrite() public {
        // write current worth of 2 for protoId 0.
        write(0, 2);

        ObservationIndex memory lastIndex = observationIndex[0];
        // Since cardinality is 0, it should write the price at index 0.
        assertEq(lastIndex.lastIndex, 0);
        assertEq(lastIndex.cardinality, 1);

        // Since no time has passed since writing observation,
        // the last written observation 1 should be the output.
        assertEq(observeSingle(0,0,lastIndex,0), INIT_TIME*2);
        assertEq(observeSingle(0,0,lastIndex,10), INIT_TIME*2);

        assertEq(observations[0][0].timestamp, INIT_TIME);
        assertEq(observations[0][0].cumulativeWorth, INIT_TIME*2);

        vm.warp(block.timestamp + 10);
        assertEq(observeSingle(0,0,lastIndex,0), INIT_TIME*2);
        assertEq(observeSingle(0,0,lastIndex,15), (INIT_TIME*2)+(10*15));

        this.grow(0, 3);

        // all the previous assertions should hold
        assertEq(observeSingle(0,0,lastIndex,0), INIT_TIME*2);
        assertEq(observeSingle(0,0,lastIndex,15), (INIT_TIME*2)+(10*15));

        assertEq(observationIndex[0].cardinality, 1);
        assertEq(observationIndex[0].lastIndex, 0);
        assertEq(observations[0][0].timestamp, INIT_TIME);
        assertEq(observations[0][0].cumulativeWorth, INIT_TIME*2);

        for (uint i=1; i<=2; ++i) {
            assertEq(observations[0][i].timestamp, 1);
            assertEq(observations[0][i].cumulativeWorth, 0);
        }
    }

    function testBinarySearch() public {

    }

}
