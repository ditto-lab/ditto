// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../Oracle.sol";

contract OracleTest is Test, Oracle {

    function setUp() public {}

    function testWrite() public {
        // write current worth 1 for protoId 1.
        write(0, 1);

        ObservationIndex memory lastIndex = observationIndex[0];
        // Since cardinality is 0, it should write the price at index 0.
        assertEq(lastIndex.lastIndex, 0);
        assertEq(lastIndex.cardinality, 0);

        // Since no time has passed since writing observation,
        // the last written observation 1 should be the output.
        assertEq(observeSingle(0,0,lastIndex,0), 1);
        assertEq(observeSingle(0,0,lastIndex,10), 1);

        vm.warp(block.timestamp + 10);
        assertEq(observeSingle(0,0,lastIndex,0), 1);
        assertEq(observeSingle(0,0,lastIndex,15), 1+10*15);
    }

}
