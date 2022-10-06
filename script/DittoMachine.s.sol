// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import {DittoMachine, DittoMachineSvg} from "src/DittoMachine.sol";

contract DittoMachineScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("GOERLI_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        DittoMachineSvg svg = new DittoMachineSvg();
        DittoMachine dm = new DittoMachine(address(svg));
        console.log(dm.name());
        console.log(address(dm));

        vm.stopBroadcast();
    }
}
