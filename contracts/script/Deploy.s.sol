// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ProofOfLiveness} from "../src/ProofOfLiveness.sol";

contract DeployScript is Script {
    function run() external {
        uint256 requiredStake = vm.envOr("REQUIRED_STAKE", uint256(0.001 ether));
        uint256 heartbeatInterval = vm.envOr("HEARTBEAT_INTERVAL", uint256(1 days));
        address slashedFundsSink = vm.envAddress("SLASHED_FUNDS_SINK");

        vm.startBroadcast();

        ProofOfLiveness pol = new ProofOfLiveness(
            requiredStake,
            heartbeatInterval,
            slashedFundsSink
        );

        console.log("ProofOfLiveness deployed at:", address(pol));
        console.log("Required stake:", requiredStake);
        console.log("Heartbeat interval (seconds):", heartbeatInterval);
        console.log("Slashed funds sink:", slashedFundsSink);

        vm.stopBroadcast();
    }
}
