pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import {CloneList} from "../CloneList.sol";

contract CloneListTest is Test, CloneList {

    function testListPushTail() public {

        for (uint i=0; i<50; ++i) {
            pushListTail(0, i);
            assertEq(protoIdToIndexToAfter[0][i], i+1);
            assertEq(protoIdToIndexToPrior[0][i+1], i);
            // console.log(protoIdToIndexToAfter[0][protoIdToIndexToPrior[0][i]]);
            // console.log(i);
            assertTrue(validIndex(0, i+1));
        }

        assertEq(protoIdToIndexToPrior[0][0], 0);
        assertEq(protoIdToIndexToAfter[0][0], 1);
        for (uint j=1; j<50; ++j) {
            assertEq(protoIdToIndexToPrior[0][j], j-1); // prior index is one before
            assertEq(protoIdToIndexToAfter[0][j], j+1); // after index is one after
            assertEq(protoIdToIndexToAfter[0][j], protoIdToIndexToPrior[0][j]+2); // after index is two after the prior index
        }
        assertEq(protoIdToIndexToPrior[0][50], 49);
        assertEq(protoIdToIndexToAfter[0][50], 0);
    }

    function testListPop(uint256 r) public {

        // initialize list of 50
        for (uint i=0; i<50; ++i) {
            pushListTail(0, i);
        }

        for (uint j=1; j<49; ++j) {
            assertEq(protoIdToIndexToPrior[0][j], j-1); // prior index is one before
            assertEq(protoIdToIndexToAfter[0][j], j+1); // after index is one after
            assertEq(protoIdToIndexToAfter[0][j], protoIdToIndexToPrior[0][j]+2); // after index is two after the prior index

            // console.log(protoIdToIndexToPrior[0][j]);
            // console.log(protoIdToIndexToAfter[0][j]);
            // console.log("");
        }

        uint index = r % 50;
        vm.assume(index > 0);

        uint prev = protoIdToIndexToPrior[0][index];
        uint next = protoIdToIndexToAfter[0][index];

        assertEq(prev, index-1);
        assertEq(next, index+1);

        popListIndex(0, index);

        assertFalse(validIndex(0, index));

        assertEq(protoIdToIndexToPrior[0][next], prev);
        assertEq(protoIdToIndexToAfter[0][prev], next);
    }

    function testListPopHead() public {

        // initialize list of 50
        for (uint i=0; i<50; ++i) {
            pushListTail(0, i);
        }

        for (uint j=1; j<49; ++j) {
            assertEq(protoIdToIndexToPrior[0][j], j-1); // prior index is one before
            assertEq(protoIdToIndexToAfter[0][j], j+1); // after index is one after
            assertEq(protoIdToIndexToAfter[0][j], protoIdToIndexToPrior[0][j]+2); // after index is two after the prior index
        }

        for (uint k=0; k<50; ++k) {
            uint index = k;
            assertEq(index, protoIdToIndexHead[0]);

            uint prev = protoIdToIndexToPrior[0][index];
            uint next = protoIdToIndexToAfter[0][index];

            assertEq(prev, 0);
            assertEq(next, index+1);

            popListHead(0);

            assertFalse(validIndex(0, index));

            assertEq(protoIdToIndexToPrior[0][next], prev);
            assertEq(protoIdToIndexToAfter[0][prev], next);
        }

    }

    function testListPopFuzzier(uint256[50] memory r) public {

        // initialize list of 50
        for (uint i=0; i<50; ++i) {
            pushListTail(0, i);
        }

        for (uint j=0; j<50; ++j) {
            unchecked { r[j] = r[j] % 50 - j; }
        }

        uint[50] memory indeces;
        for (uint k=0; k<50; ++k) {

            uint index = 0;

            for (uint l=0; l<indeces[k]; ++l) {
                if (l == 0) {
                    index = protoIdToIndexHead[0];
                } else {
                    index = protoIdToIndexToAfter[0][index];
                }
            }
            // vm.assume(index > 0);

            uint prev = protoIdToIndexToPrior[0][index];
            uint next = protoIdToIndexToAfter[0][index];

            assertEq(prev, index == 0 ? 0 : index-1); // if index is 0, its prev index will be 0
            assertEq(next, index+1);

            popListIndex(0, index);

            assertFalse(validIndex(0, index));

            assertEq(protoIdToIndexToPrior[0][next], prev);
            assertEq(protoIdToIndexToAfter[0][prev], next);
        }

    }

}
