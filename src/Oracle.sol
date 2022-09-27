pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

abstract contract Oracle {
    error CardinalityNotAllowed();

    struct Observation {
        uint256 timestamp;
        uint256 cumulativeWorth;
    }

    struct ObservationIndex {
        uint128 cardinality;
        uint128 lastIndex;
    }

    mapping(uint256 => Observation[65536]) observations;
    mapping(uint256 => ObservationIndex) observationIndex;


    function write(uint256 cloneId, uint256 price) internal {
        ObservationIndex memory index = observationIndex[cloneId];
        Observation memory lastObservation = observations[cloneId][index.lastIndex];
        if (block.timestamp == lastObservation.timestamp) return;

        unchecked {
            if (++index.lastIndex == index.cardinality) {
                if (observations[cloneId][index.lastIndex].timestamp != 0) {
                    ++index.cardinality;
                } else {
                    index.lastIndex = 0;
                }
            }

            uint256 timeDelta = block.timestamp - lastObservation.timestamp;
            observations[cloneId][index.lastIndex] = Observation({
                timestamp: block.timestamp,
                cumulativeWorth: lastObservation.cumulativeWorth + (timeDelta * price)
            });
            observationIndex[cloneId] = index;
        }
    }

    function grow(uint256 cloneId, uint16 newCardinality) public {
        uint128 curCardinality = observationIndex[cloneId].cardinality;
        if (newCardinality <= curCardinality) revert CardinalityNotAllowed();

        unchecked {
            for(uint256 i = curCardinality; i < newCardinality; ++i) {
                observations[cloneId][i].timestamp = 1;
            }
        }
    }

    // function observe()

}
