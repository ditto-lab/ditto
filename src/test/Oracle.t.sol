// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import {Oracle} from "../Oracle.sol";
import {OracleWrapper} from "./OracleWrapper.sol";

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

    // last secAgos is always 0
    function setExactSecAgos(Observation[65536] storage obs, uint128 maxIndex) internal view returns (uint128[] memory secAgos) {
        secAgos = new uint128[](maxIndex+2);
        for (uint i=0; i<=maxIndex; ++i) {
            secAgos[i] = uint128(block.timestamp) - obs[i].timestamp;
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
        // test for even length of observations array
        uint snapshot = vm.snapshot();
        testWithCardinality(1000);
        vm.revertTo(snapshot);

        // test for odd length of observations array
        testWithCardinality(1001);
    }

    function testWithCardinality(uint16 c) internal {
        this.grow(0, c);
        uint128 i=0;
        for(; i<c; ++i) {
            write(0, i+1);
            assertEq(observationIndex[0].lastIndex, i);
            assertEq(observationIndex[0].cardinality, i+1);
            vm.warp(block.timestamp+10);
        }
        assertEq(observationIndex[0].lastIndex, c-1, "O3");
        assertEq(observationIndex[0].cardinality, c, "O2");

        // last element secAgos[c] always stays 0
        uint128[] memory secAgos = setExactSecAgos(observations[0], c-1);

        // asserting correct observations when secondsAgos perfectly match with write timestamps
        uint128[] memory worth = this.observeWrapper(0, secAgos, 0);
        for (uint j=0; j<c; ++j) {
            assertEq(worth[j], observations[0][j].cumulativeWorth);
        }
        assertEq(worth[c], observations[0][c-1].cumulativeWorth, "O1");

        uint128 shiftObsTime = 2;

        for (uint j=0; j<c; ++j) {
            secAgos[j] -= shiftObsTime;
        }

        uint128 curWorth = 15;
        worth = this.observeWrapper(0, secAgos, curWorth);
        for (uint j=0; j<c-1; ++j) {
            uint128 obsTimeDelta = observations[0][j+1].timestamp - observations[0][j].timestamp;
            uint128 targetDelta = (uint128(block.timestamp) - secAgos[j]) - observations[0][j].timestamp;
            assertEq(obsTimeDelta, 10);
            assertEq(targetDelta, shiftObsTime);
            assertEq(
                worth[j],
                observations[0][j].cumulativeWorth
                + (observations[0][j+1].cumulativeWorth - observations[0][j].cumulativeWorth)
                    * targetDelta / obsTimeDelta);
        }
        assertEq(
            worth[c-1],
            observations[0][c-1].cumulativeWorth
            + (curWorth * (uint128(block.timestamp - secAgos[c-1]) - observations[0][c-1].timestamp)));
        assertEq(worth[c],
            observations[0][c-1].cumulativeWorth
            + (curWorth * (uint128(block.timestamp) - observations[0][c-1].timestamp)));

        for(; i<c+201; ++i) {
            write(0, i+1);
            vm.warp(block.timestamp+10);
        }
        assertEq(observationIndex[0].lastIndex, 200, "O4");
        assertEq(observationIndex[0].cardinality, c, "O5");
        assertEq(observations[0][c].cumulativeWorth, 0, "O6");
        secAgos = setExactSecAgos(observations[0], c-1);

        worth = this.observeWrapper(0, secAgos, 0);
        for (uint j=0; j<c; ++j) {
            assertEq(worth[j], observations[0][j].cumulativeWorth);
        }
        assertEq(worth[c], observations[0][200].cumulativeWorth, "O1");

        for (uint j=0; j<c; ++j) {
            secAgos[j] -= shiftObsTime;
        }

        worth = this.observeWrapper(0, secAgos, curWorth);
        for (uint k=201; k<c+200; ++k) {
            uint j=k%c;
            uint128 obsTimeDelta = observations[0][(j+1)%c].timestamp - observations[0][j].timestamp;
            uint128 targetDelta = (uint128(block.timestamp) - secAgos[j]) - observations[0][j].timestamp;
            assertEq(obsTimeDelta, 10);
            assertEq(targetDelta, shiftObsTime);
            assertEq(
                worth[j],
                observations[0][j].cumulativeWorth
                + (observations[0][(j+1)%c].cumulativeWorth - observations[0][j].cumulativeWorth)
                    * targetDelta / obsTimeDelta);
        }
        assertEq(
            worth[200],
            observations[0][200].cumulativeWorth
            + (curWorth * (uint128(block.timestamp - secAgos[200]) - observations[0][200].timestamp)));
        assertEq(worth[c],
            observations[0][200].cumulativeWorth
            + (curWorth * (uint128(block.timestamp) - observations[0][200].timestamp)));

        for (; i<c+800; ++i) {
            write(0, i+1);
            vm.warp(block.timestamp+10);
        }
        assertEq(observationIndex[0].lastIndex, 799);
        assertEq(observationIndex[0].cardinality, c);
        assertEq(observations[0][c].cumulativeWorth, 0);
        secAgos = setExactSecAgos(observations[0], c-1);

        worth = this.observeWrapper(0, secAgos, 0);
        for (uint j=0; j<c; ++j) {
            assertEq(worth[j], observations[0][j].cumulativeWorth);
        }
        assertEq(worth[c], observations[0][799].cumulativeWorth, "O1");

        for (uint j=0; j<c; ++j) {
            secAgos[j] -= shiftObsTime;
        }

        worth = this.observeWrapper(0, secAgos, curWorth);
        for (uint k=800; k<c+799; ++k) {
            uint j=k%c;
            uint128 obsTimeDelta = observations[0][(j+1)%c].timestamp - observations[0][j].timestamp;
            uint128 targetDelta = (uint128(block.timestamp) - secAgos[j]) - observations[0][j].timestamp;
            assertEq(obsTimeDelta, 10);
            assertEq(targetDelta, shiftObsTime);
            assertEq(
                worth[j],
                observations[0][j].cumulativeWorth
                + (observations[0][(j+1)%c].cumulativeWorth - observations[0][j].cumulativeWorth)
                    * targetDelta / obsTimeDelta);
        }
        assertEq(
            worth[799],
            observations[0][799].cumulativeWorth
            + (curWorth * (uint128(block.timestamp - secAgos[799]) - observations[0][799].timestamp)));
        assertEq(worth[c],
            observations[0][799].cumulativeWorth
            + (curWorth * (uint128(block.timestamp) - observations[0][799].timestamp)));
    }

    function testObserveTooOld() public {
        OracleWrapper o = new OracleWrapper();
        o.grow(0, 3);
        o.writeWrapper(0, 1);
        vm.warp(block.timestamp+1);
        o.writeWrapper(0, 2);
        vm.warp(block.timestamp+1);
        o.writeWrapper(0, 3);
        vm.warp(block.timestamp+1);

        uint128[] memory secAgos = new uint128[](1);
        secAgos[0] = uint128(block.timestamp) - (uint128(INIT_TIME)-1);

        vm.expectRevert(abi.encodeWithSelector(Oracle.TimeRequestedTooOld.selector));
        o.observeWrapper(0, secAgos, 0);

        o.writeWrapper(0, 4); // overwrites the first observation written at INIT_TIME

        secAgos[0] = uint128(block.timestamp) - uint128(INIT_TIME);
        vm.expectRevert(abi.encodeWithSelector(Oracle.TimeRequestedTooOld.selector));
        o.observeWrapper(0, secAgos, 0);
    }
}
