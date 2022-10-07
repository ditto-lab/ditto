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

    mapping(uint => uint) public protoIdToDepth;

    function pushListTail(uint protoId, uint index) internal {
        unchecked { // ethereum will be irrelevant if this ever overflows
            ++protoIdToDepth[protoId]; // increase depth counter

            // index -> next
            protoIdToIndexToAfter[protoId][index] = index+1; // set reference **to** the next index

            // index <- next
            protoIdToIndexToPrior[protoId][index+1] = index; // set the next index's reference to previous index
        }
    }

    function popListIndex(uint protoId, uint index) internal {
        unchecked { // if clone deoesn't exist an error will throw above. should not underflow
            --protoIdToDepth[protoId]; // decrement clone depth counter
        }
        mapping(uint => uint) storage indexToAfter = protoIdToIndexToAfter[protoId];
        mapping(uint => uint) storage indexToPrior = protoIdToIndexToPrior[protoId];
        if (index == protoIdToIndexHead[protoId]) { // if index == indexHead move head to next index
            // index -> next
            // head = next
            protoIdToIndexHead[protoId] = indexToAfter[index];
        }
        // index pointers will change:
        // prev -> index -> next
        // becomes:
        // prev ----------> next
        indexToAfter[indexToPrior[index]] = indexToAfter[index];

        // prev <- index <- next
        // becomes:
        // prev <---------- next
        indexToPrior[indexToAfter[index]] = indexToPrior[index];
    }

    function popListHead(uint protoId) internal {
        uint head = protoIdToIndexHead[protoId];
        mapping(uint => uint) storage indexToAfter = protoIdToIndexToAfter[protoId];
        mapping(uint => uint) storage indexToPrior = protoIdToIndexToPrior[protoId];
        // indexHead -> next
        // head = next
        protoIdToIndexHead[protoId] = indexToAfter[head]; // move head to next index
        unchecked { --protoIdToDepth[protoId]; } // should not underflow, will error above if clone does not exist

        // index pointers will change:
        // prev -> index -> next
        // becomes:
        // prev ----------> next
        indexToAfter[indexToPrior[head]] = indexToAfter[head];

        // prev <- index <- next
        // becomes:
        // prev <---------- next
        indexToPrior[indexToAfter[head]] = indexToPrior[head];
    }

    function validIndex(uint protoId, uint index) internal view returns(bool) {
        // prev <- index
        // prev -> index
        return protoIdToIndexToAfter[protoId][protoIdToIndexToPrior[protoId][index]] == index;
    }

}
