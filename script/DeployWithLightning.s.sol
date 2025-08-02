// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/SimpleEscrow.sol";
import "../src/SimpleEscrowFactory.sol";
import "../src/OneInchAdapter.sol";
import "../src/LightningBridge.sol";

contract DeployWithLightning is Script {
    function run() external returns (address factory, address adapter, address bridge) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address limitOrderProtocol = vm.envOr("LIMIT_ORDER_PROTOCOL", address(0));
        address resolver = vm.envAddress("RESOLVER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy SimpleEscrowFactory
        SimpleEscrowFactory factoryContract = new SimpleEscrowFactory(address(0));
        factory = address(factoryContract);
        console.log("SimpleEscrowFactory deployed at:", factory);
        
        // Deploy OneInchAdapter (optional)
        if (limitOrderProtocol != address(0)) {
            OneInchAdapter adapterContract = new OneInchAdapter(
                factory,
                limitOrderProtocol
            );
            adapter = address(adapterContract);
            console.log("OneInchAdapter deployed at:", adapter);
            
            // Set adapter in factory
            factoryContract.setOneInchAdapter(adapter);
            console.log("OneInchAdapter set in factory");
        }
        
        // Deploy LightningBridge
        LightningBridge bridgeContract = new LightningBridge(factory);
        bridge = address(bridgeContract);
        console.log("LightningBridge deployed at:", bridge);
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        _saveDeployment(factory, adapter, bridge);
        
        return (factory, adapter, bridge);
    }
    
    function _saveDeployment(address factory, address adapter, address bridge) internal {
        string memory json = "deployment";
        vm.serializeAddress(json, "factory", factory);
        vm.serializeAddress(json, "adapter", adapter);
        vm.serializeAddress(json, "bridge", bridge);
        vm.serializeUint(json, "chainId", block.chainid);
        string memory output = vm.serializeUint(json, "timestamp", block.timestamp);
        
        string memory filename = string.concat(
            "./deployments/",
            vm.toString(block.chainid),
            "-lightning-deployment.json"
        );
        vm.writeJson(output, filename);
        console.log("Lightning deployment saved to:", filename);
    }
}