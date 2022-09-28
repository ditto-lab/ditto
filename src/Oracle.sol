pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

abstract contract Oracle {
    error CardinalityNotAllowed();
    error TimeRequestedTooOld();

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

    // write current price (before a trade)
    function write(uint256 protoId, uint256 price) internal {
        ObservationIndex memory index = observationIndex[protoId];
        Observation memory lastObservation = observations[protoId][index.lastIndex];
        if (block.timestamp == lastObservation.timestamp) return;

        unchecked {
            if (++index.lastIndex == index.cardinality) {
                if (observations[protoId][index.lastIndex].timestamp != 0) {
                    ++index.cardinality;
                } else {
                    index.lastIndex = 0;
                }
            }

            uint256 timeDelta = block.timestamp - lastObservation.timestamp;
            observations[protoId][index.lastIndex] = Observation({
                timestamp: block.timestamp,
                cumulativeWorth: lastObservation.cumulativeWorth + (timeDelta * price)
            });
            observationIndex[protoId] = index;
        }
    }

    function grow(uint256 protoId, uint16 newCardinality) public {
        uint128 curCardinality = observationIndex[protoId].cardinality;
        if (newCardinality <= curCardinality) revert CardinalityNotAllowed();

        unchecked {
            for(uint256 i = curCardinality; i < newCardinality; ++i) {
                observations[protoId][i].timestamp = 1;
            }
        }
    }

    function observe(
        uint256 protoId,
        uint256[] calldata secondsAgos
    ) internal view returns (uint256[] memory cumulativePrices) {
        cumulativePrices = new uint256[](secondsAgos.length);
        ObservationIndex memory index = observationIndex[protoId];
        for (uint256 i=0; i < secondsAgos.length; ++i) {
            cumulativePrices[i] = observeSingle(protoId, secondsAgos[i], index);
        }
    }

    function observeSingle(uint256 protoId, uint256 secondsAgo, ObservationIndex memory lastIndex) internal view returns (uint256 cumulativePrice) {
        if (secondsAgo == 0) {
            Observation memory lastObservation = observations[protoId][lastIndex.lastIndex];
            if (block.timestamp != lastObservation.timestamp) {
                return transform(lastObservation, block.timestamp);
            }
            return lastObservation.cumulativeWorth;
        }

        uint256 targetTimestamp = block.timestamp - secondsAgo;

        (Observation memory beforeOrAt, Observation memory atOrAfter) =
            getSurroundingObservations(protoId, targetTimestamp, lastIndex);

        if (targetTimestamp == beforeOrAt.timestamp) {
            // we're at the left boundary
            return beforeOrAt.cumulativeWorth;
        } else if (targetTimestamp == atOrAfter.timestamp) {
            // right boundary
            return atOrAfter.cumulativeWorth;
        } else {
            // middle
            uint256 observationTimeDelta = atOrAfter.timestamp - beforeOrAt.timestamp;
            uint256 targetDelta = targetTimestamp - beforeOrAt.timestamp;

            return
                beforeOrAt.cumulativeWorth +
                    ((atOrAfter.cumulativeWorth - beforeOrAt.cumulativeWorth) * targetDelta / observationTimeDelta);
        }
    }

    function getSurroundingObservations(
        uint256 protoId, uint256 targetTimestamp, ObservationIndex memory lastIndex
    ) internal view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {

        // check if the newest obervation is older than the requested observation
        beforeOrAt = observations[protoId][lastIndex.lastIndex];

        if (targetTimestamp == beforeOrAt.timestamp) {
            return (beforeOrAt, atOrAfter);
        } else if (targetTimestamp > beforeOrAt.timestamp) {
            atOrAfter.timestamp = targetTimestamp;
            atOrAfter.cumulativeWorth = transform(beforeOrAt, targetTimestamp);
            return (beforeOrAt, atOrAfter);
        }

        // check if oldest obervation is newer than the requested observation
        beforeOrAt = observations[protoId][(lastIndex.lastIndex + 1) % lastIndex.cardinality];
        if (targetTimestamp < beforeOrAt.timestamp) revert TimeRequestedTooOld();

        // apply binary search
        return binarySearch(protoId, targetTimestamp, lastIndex);

    }

    function binarySearch(
        uint256 protoId, uint256 targetTimestamp, ObservationIndex memory lastIndex
    ) internal view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // binary search on a sorted rotated array
        uint256 l = (lastIndex.lastIndex + 1) % lastIndex.cardinality; // oldest obervation
        uint256 r = l + lastIndex.cardinality - 1; // newest obervation
        // r can never be the target as we have already checked the newest observation

        // index i maps to the real index i % cardinality in the observations array.
        uint256 i;

        // goal is to find beforeOrAt
        // invariant: l <= beforeOrAt < r
        while (true) {
            i = (l + r) >> 1; // divide by 2
            beforeOrAt = observations[protoId][i % lastIndex.cardinality];
            atOrAfter = observations[protoId][(i+1) % lastIndex.cardinality];

            if (targetTimestamp < beforeOrAt.timestamp) {
                r = i-1;
                continue;
            }

            // beforeOrAt.timestamp <= targetTimestamp

            if (targetTimestamp <= atOrAfter.timestamp) break; // found

            // atOrAfter.timestamp < targetTimestamp, atOrAfter is at i+1
            l = i+1;
        }
    }

    function transform(
        Observation memory lastObservation, uint256 targetTimestamp
    ) internal pure returns (uint256 cumulativeWorth) {
        return lastObservation.cumulativeWorth +
            (targetTimestamp - lastObservation.timestamp) * lastObservation.cumulativeWorth;
    }

}
