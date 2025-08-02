// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/mocks/MockERC20.sol";

contract DeployMockUSDC is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Mock USDC with 6 decimals and 1M initial supply
        MockERC20 mockUSDC = new MockERC20(
            "USD Coin (Mock)",
            "USDC",
            6,
            1_000_000 * 10**6 // 1M USDC
        );
        
        address usdcAddress = address(mockUSDC);
        console.log("MockUSDC deployed at:", usdcAddress);
        
        vm.stopBroadcast();
        
        return usdcAddress;
    }
}