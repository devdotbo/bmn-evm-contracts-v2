// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/SimpleEscrowFactory.sol";

contract DeploySimpleEscrowFactory is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy SimpleEscrowFactory with no initial adapter
        SimpleEscrowFactory factory = new SimpleEscrowFactory(address(0));
        
        address factoryAddress = address(factory);
        console.log("SimpleEscrowFactory deployed at:", factoryAddress);
        
        vm.stopBroadcast();
        
        return factoryAddress;
    }
}