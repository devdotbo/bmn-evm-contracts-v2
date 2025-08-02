// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/SimpleEscrow.sol";
import "../src/SimpleEscrowFactory.sol";
import "../src/mocks/MockERC20.sol";

contract QuickDemo is Script {
    function run() external {
        // Load private key from environment
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address alice = vm.addr(deployerKey);
        address bob = address(0xB0B);
        
        vm.startBroadcast(deployerKey);
        
        console.log("=== Bridge Me Not V2 Demo ===");
        console.log("Alice:", alice);
        console.log("Bob:", bob);
        
        // Deploy mock token
        MockERC20 token = new MockERC20("Demo USDC", "USDC", 6, 0);
        console.log("Token deployed:", address(token));
        
        // Mint tokens to Alice
        token.mint(alice, 1000 * 10**6); // 1000 USDC
        console.log("Minted 1000 USDC to Alice");
        
        // Deploy factory
        SimpleEscrowFactory factory = new SimpleEscrowFactory(address(0));
        console.log("Factory deployed:", address(factory));
        
        // Create atomic swap parameters
        bytes32 secret = keccak256("supersecret123");
        bytes32 hashlock = keccak256(abi.encode(secret));
        uint256 timelock = block.timestamp + 1 hours;
        bytes32 salt = keccak256("demo-swap-1");
        
        console.log("\n=== Creating Atomic Swap ===");
        console.log("Hashlock:", vm.toString(hashlock));
        console.log("Timelock:", timelock);
        
        // Create escrow
        address escrow = factory.createEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        console.log("Escrow created:", escrow);
        
        // Fund escrow
        uint256 amount = 100 * 10**6; // 100 USDC
        token.approve(escrow, amount);
        SimpleEscrow(escrow).fund(amount);
        console.log("Escrow funded with 100 USDC");
        
        // Show escrow details
        SimpleEscrow.EscrowDetails memory details = SimpleEscrow(escrow).getDetails();
        
        console.log("\n=== Escrow Details ===");
        console.log("Amount locked:", details.amount / 10**6, "USDC");
        console.log("Funded:", details.funded);
        console.log("Can withdraw:", SimpleEscrow(escrow).canWithdraw());
        
        // Simulate Bob withdrawing with secret
        vm.stopBroadcast();
        vm.startBroadcast(uint256(0xB0B)); // Switch to Bob
        
        console.log("\n=== Bob Withdrawing ===");
        SimpleEscrow(escrow).withdraw(secret);
        console.log("Withdrawal successful!");
        
        // Check final state
        SimpleEscrow.EscrowDetails memory finalDetails = SimpleEscrow(escrow).getDetails();
        console.log("Withdrawn:", finalDetails.withdrawn);
        console.log("Revealed preimage:", vm.toString(finalDetails.preimage));
        console.log("Bob's balance:", token.balanceOf(bob) / 10**6, "USDC");
        
        console.log("\n=== Demo Complete! ===");
        console.log("Atomic swap executed successfully without any bridge!");
        
        vm.stopBroadcast();
    }
}