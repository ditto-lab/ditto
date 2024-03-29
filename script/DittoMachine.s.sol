// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import {DittoMachine, DittoMachineSvg} from "src/DittoMachine.sol";

contract DittoMachineScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        DittoMachine dm = new DittoMachine();
        console.log(address(dm));

        vm.stopBroadcast();
    }
}
