// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../Oracle.sol";

contract OracleTest is Test, Oracle {
    uint256 constant INIT_TIME = 1644911858;

    function setUp() public {
        vm.warp(INIT_TIME);
    }

    // we cannot call `Oracle.observe()` directly as it takes calldata argument.
    // wrapping it in an external function lets us call it via `this.observeWrapper()`.
    function observeWrapper(
        uint256 protoId,
        uint128[] calldata secondsAgos,
        uint128 curWorth
    ) external view returns (uint128[] memory cumulativePrices) {
        return Oracle.observe(protoId, secondsAgos, curWorth);
    }

    function getConstantHash(Observation[65536] storage obs, uint128 maxIndex, uint exceptIndex) internal view returns (uint _hash) {
        for (uint k=0;k<=maxIndex;++k) {
            if (k==exceptIndex) continue;
            _hash = uint(keccak256(abi.encodePacked(
                _hash,
                obs[k].timestamp,
                obs[k].cumulativeWorth
            )));
        }
    }

    function testWrite() public {
        uint128 price = 2;
        uint256 protoId = 0;
        write(protoId, price);

        ObservationIndex memory lastIndex = observationIndex[0];
        // Since cardinality is 0, it should write the price at index 0.
        assertEq(lastIndex.lastIndex, 0);
        assertEq(lastIndex.cardinality, 1);

        // Since no time has passed since writing observation,
        // the last written observation 1 should be the output.
        assertEq(observeSingle(0,0,lastIndex,0), INIT_TIME*price);
        assertEq(observeSingle(0,0,lastIndex,10), INIT_TIME*price);

        assertEq(observations[0][0].timestamp, INIT_TIME);
        assertEq(observations[0][0].cumulativeWorth, INIT_TIME*price);

        vm.warp(block.timestamp + 10);
        assertEq(observeSingle(0,0,lastIndex,0), INIT_TIME*price);
        assertEq(observeSingle(0,0,lastIndex,15), (INIT_TIME*price)+(10*15));

        uint16 newCardinality = 3;
        this.grow(0, newCardinality);

        // all the previous assertions should hold
        assertEq(observeSingle(0,0,lastIndex,0), INIT_TIME*price);
        assertEq(observeSingle(0,0,lastIndex,15), (INIT_TIME*price)+(10*15));
        vm.warp(block.timestamp - 10);

        assertEq(observationIndex[0].cardinality, 1);
        assertEq(observationIndex[0].lastIndex, 0);
        assertEq(observations[0][0].timestamp, INIT_TIME);
        assertEq(observations[0][0].cumulativeWorth, INIT_TIME*price);

        // grow() should only change the timestamp of expanded array
        for (uint i = 1; i < newCardinality; ++i) {
            assertEq(observations[0][i].timestamp, 1);
            assertEq(observations[0][i].cumulativeWorth, 0);
        }

        assertEq(observations[0][newCardinality].timestamp, 0);
        assertEq(observations[0][newCardinality].cumulativeWorth, 0);

        uint128[3] memory prices;
        prices[0] = 30;
        prices[1] = 10;
        prices[2] = 20;

        uint128 cumulativeWorth = observations[0][0].cumulativeWorth;
        uint128 cardinality = 1;
        for (uint i=1; i<=3; ++i) {
            vm.warp(block.timestamp+10);
            uint j = i%3;

            uint otherObs = getConstantHash(observations[0], newCardinality, j);

            write(0, prices[j]);
            if (++cardinality > newCardinality) cardinality = newCardinality;

            cumulativeWorth += prices[j]*10;

            assertEq(observationIndex[0].cardinality, cardinality);
            assertEq(observationIndex[0].lastIndex, j);
            assertEq(observations[0][j].timestamp, block.timestamp);
            assertEq(observations[0][j].cumulativeWorth, cumulativeWorth);

            // ensures that only the j-th index in observations is changed.
            assertEq(otherObs, getConstantHash(observations[0], newCardinality, j));

            vm.warp(block.timestamp+20);

            assertEq(observeSingle(0,0,observationIndex[0],0), cumulativeWorth);
            assertEq(observeSingle(0,0,observationIndex[0],15), cumulativeWorth+(20*15));

            vm.warp(block.timestamp-20);
        }
    }

    function testBinarySearch() public {
        this.grow(0, 1000);
        uint128 i=0;
        for(; i<1000; ++i) {
            write(0, i+1);
            vm.warp(block.timestamp+1);
        }

        // TODO: test binary search

        for(; i<1200; ++i) {
            write(0, i+1);
            vm.warp(block.timestamp+1);
        }

        // TODO: test binary search

        for (; i<1800; ++i) {
            write(0, i+1);
            vm.warp(block.timestamp+1);
        }

        // TODO: test binary search

    }

}
