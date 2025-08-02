// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/OneInchAdapter.sol";
import "../../src/SimpleEscrowFactory.sol";

contract DeployOneInchAdapter is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        address limitOrderProtocol = vm.envOr("LIMIT_ORDER_PROTOCOL", 0x1111111254EEB25477B68fb85Ed929f73A960582);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy OneInchAdapter
        OneInchAdapter adapter = new OneInchAdapter(
            factoryAddress,
            limitOrderProtocol
        );
        
        address adapterAddress = address(adapter);
        console.log("OneInchAdapter deployed at:", adapterAddress);
        
        // Set adapter in factory
        SimpleEscrowFactory(factoryAddress).setOneInchAdapter(adapterAddress);
        console.log("OneInchAdapter set in factory");
        
        vm.stopBroadcast();
        
        return adapterAddress;
    }
}