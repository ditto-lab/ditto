pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

abstract contract Oracle {
    error CardinalityNotAllowed();
    error TimeRequestedTooOld();

    struct Observation {
        uint128 timestamp;
        uint128 cumulativeWorth;
    }

    struct ObservationIndex {
        uint128 cardinality; // max 65535 = type(uint16).max
        uint128 lastIndex;
    }

    // Observation array is 1 greater than the limit.
    mapping(uint256 => Observation[65536]) internal observations;
    mapping(uint256 => ObservationIndex) internal observationIndex;

    // write current price (before a trade).
    // If cardinality is 0, it first sets it to 1.

    function write(uint256 protoId, uint128 price) internal {
        ObservationIndex memory index = observationIndex[protoId];
        Observation memory lastObservation = observations[protoId][index.lastIndex];
        if (block.timestamp == lastObservation.timestamp) return;

        if (index.cardinality == 0) index.cardinality = 1;
        unchecked {
            if (++index.lastIndex == index.cardinality) {
                // since the maximum length is 65535, array's last timestamp is always 0
                if (observations[protoId][index.lastIndex].timestamp != 0) {
                    ++index.cardinality;
                } else {
                    index.lastIndex = 0;
                }
            }

            uint128 timeDelta = uint128(block.timestamp) - lastObservation.timestamp;
            observations[protoId][index.lastIndex] = Observation({
                timestamp: uint128(block.timestamp),
                cumulativeWorth: lastObservation.cumulativeWorth + (timeDelta * price)
            });
            observationIndex[protoId] = index;
        }
    }

    function grow(uint256 protoId, uint16 newCardinality) external {
        uint128 curCardinality = observationIndex[protoId].cardinality;

        unchecked {
            // a no-op if newCardinality <= curCardinality
            for(uint256 i = curCardinality; i < newCardinality; ++i) {
                // i is max 65534
                observations[protoId][i].timestamp = 1;
            }
        }
    }

    function observe(
        uint256 protoId,
        uint128[] calldata secondsAgos,
        uint128 curWorth
    ) internal view returns (uint128[] memory cumulativePrices) {
        cumulativePrices = new uint128[](secondsAgos.length);
        ObservationIndex memory index = observationIndex[protoId];
        for (uint256 i=0; i < secondsAgos.length; ++i) {
            cumulativePrices[i] = observeSingle(protoId, secondsAgos[i], index, curWorth);
        }
    }

    function observeSingle(
        uint256 protoId,
        uint128 secondsAgo,
        ObservationIndex memory lastIndex,
        uint128 curWorth
    ) internal view returns (uint128 cumulativePrice) {
        if (secondsAgo == 0) {
            Observation memory lastObservation = observations[protoId][lastIndex.lastIndex];
            if (block.timestamp != lastObservation.timestamp) {
                return transform(lastObservation, uint128(block.timestamp), curWorth);
            }
            return lastObservation.cumulativeWorth;
        }

        uint128 targetTimestamp = uint128(block.timestamp) - secondsAgo;

        (Observation memory beforeOrAt, Observation memory atOrAfter) =
            getSurroundingObservations(protoId, uint128(targetTimestamp), lastIndex, curWorth);

        if (targetTimestamp == beforeOrAt.timestamp) {
            // we're at the left boundary
            return beforeOrAt.cumulativeWorth;
        } else if (targetTimestamp == atOrAfter.timestamp) {
            // right boundary
            return atOrAfter.cumulativeWorth;
        } else {
            // middle
            uint128 observationTimeDelta = atOrAfter.timestamp - beforeOrAt.timestamp;
            uint128 targetDelta = targetTimestamp - beforeOrAt.timestamp;

            return
                beforeOrAt.cumulativeWorth +
                    ((atOrAfter.cumulativeWorth - beforeOrAt.cumulativeWorth) * targetDelta / observationTimeDelta);
        }
    }

    function getSurroundingObservations(
        uint256 protoId, uint128 targetTimestamp, ObservationIndex memory lastIndex, uint128 curWorth
    ) internal view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {

        // check if the newest obervation is older than the requested observation
        beforeOrAt = observations[protoId][lastIndex.lastIndex];

        if (targetTimestamp == beforeOrAt.timestamp) {
            return (beforeOrAt, atOrAfter);
        } else if (targetTimestamp > beforeOrAt.timestamp) {
            atOrAfter.timestamp = targetTimestamp;
            atOrAfter.cumulativeWorth = transform(beforeOrAt, targetTimestamp, curWorth);
            return (beforeOrAt, atOrAfter);
        }

        // check if oldest obervation is newer than the requested observation
        beforeOrAt = observations[protoId][(lastIndex.lastIndex + 1) % lastIndex.cardinality];
        if (targetTimestamp < beforeOrAt.timestamp) revert TimeRequestedTooOld();

        // apply binary search
        return binarySearch(protoId, targetTimestamp, lastIndex);
    }

    function binarySearch(
        uint256 protoId, uint128 targetTimestamp, ObservationIndex memory lastIndex
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

            if (targetTimestamp < beforeOrAt.timestamp) r = i-1;
            else if (targetTimestamp > atOrAfter.timestamp) l = i+1; // beforeOrAt.timestamp <= targetTimestamp
            else break; // beforeOrAt.timestamp <= targetTimestamp <= atOrAfter.timestamp, found
        }
    }

    function transform(
        Observation memory lastObservation, uint128 targetTimestamp, uint128 curWorth
    ) internal pure returns (uint128 cumulativeWorth) {
        return lastObservation.cumulativeWorth +
            (targetTimestamp - lastObservation.timestamp) * curWorth;
    }

}
