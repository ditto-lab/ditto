// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./DittoMachineEchidna.sol";


contract DittoMachineEchidnaTest is Test {

    DittoMachineEchidna dme;
    constructor() {
        dme = new DittoMachineEchidna();
    }

    function setUp() public virtual {
    }

    function testNameAndSymbol2() public {
        assertEq(dme.dm().name(), "Ditto");
        assertEq(dme.dm().symbol(), "DTO");
    }

}
