pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

abstract contract CloneList {

    // protoId is a precursor hash to a cloneId used to identify tokenId/erc20 pairs
    mapping(uint => uint) public protoIdToIndexHead;

    // mapping to track the index before a specified index
    // 0 <- 1 <- 2 <- 3
    mapping(uint => mapping(uint => uint)) public protoIdToIndexToPrior;

    // mapping to track the next index after a specified index
    // 0 -> 1 -> 2 -> 3
    mapping(uint => mapping(uint => uint)) public protoIdToIndexToAfter;
    // tracks the number of clones in circulation under a protoId

    function pushListTail(uint protoId, uint index) internal {
        unchecked { // ethereum will be irrelevant if this ever overflows

            // index -> next
            protoIdToIndexToAfter[protoId][index] = index+1; // set reference **to** the next index

            // index <- next
            protoIdToIndexToPrior[protoId][index+1] = index; // set the next index's reference to previous index
        }
    }

    function popListIndex(uint protoId, uint index) internal {
        if (index == protoIdToIndexHead[protoId]) { // if index == indexHead move head to next index
            // index -> next
            // head = next
            protoIdToIndexHead[protoId] = protoIdToIndexToAfter[protoId][index];
        }
        // index pointers will change:
        // prev -> index -> next
        // becomes:
        // prev ----------> next
        protoIdToIndexToAfter[protoId][protoIdToIndexToPrior[protoId][index]] = protoIdToIndexToAfter[protoId][index];

        // prev <- index <- next
        // becomes:
        // prev <---------- next
        protoIdToIndexToPrior[protoId][protoIdToIndexToAfter[protoId][index]] = protoIdToIndexToPrior[protoId][index];
    }

    function popListHead(uint protoId) internal {
        uint head = protoIdToIndexHead[protoId];
        // indexHead -> next
        // head = next
        protoIdToIndexHead[protoId] = protoIdToIndexToAfter[protoId][head]; // move head to next index

        // index pointers will change:
        // prev -> index -> next
        // becomes:
        // prev ----------> next
        protoIdToIndexToAfter[protoId][protoIdToIndexToPrior[protoId][head]] = protoIdToIndexToAfter[protoId][head];

        // prev <- index <- next
        // becomes:
        // prev <---------- next
        protoIdToIndexToPrior[protoId][protoIdToIndexToAfter[protoId][head]] = protoIdToIndexToPrior[protoId][head];
    }

    function validIndex(uint protoId, uint index) internal view returns(bool) {
        // prev <- index
        // prev -> index
        return protoIdToIndexToAfter[protoId][protoIdToIndexToPrior[protoId][index]] == index;
    }

}
