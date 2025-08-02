// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/LightningBridge.sol";

contract DeployLightningBridge is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy LightningBridge
        LightningBridge bridge = new LightningBridge(factoryAddress);
        
        address bridgeAddress = address(bridge);
        console.log("LightningBridge deployed at:", bridgeAddress);
        
        vm.stopBroadcast();
        
        return bridgeAddress;
    }
}