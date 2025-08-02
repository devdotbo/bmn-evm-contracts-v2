// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/mocks/MockERC20.sol";

contract DeployMockXTZ is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Mock XTZ with 18 decimals and 10M initial supply
        MockERC20 mockXTZ = new MockERC20(
            "Tezos (Mock)",
            "XTZ",
            18,
            10_000_000 * 10**18 // 10M XTZ
        );
        
        address xtzAddress = address(mockXTZ);
        console.log("MockXTZ deployed at:", xtzAddress);
        
        vm.stopBroadcast();
        
        return xtzAddress;
    }
}