// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/SimpleEscrow.sol";
import "../src/SimpleEscrowFactory.sol";
import "../src/mocks/MockERC20.sol";

contract QuickDemo is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address alice = vm.addr(deployerKey);
        address bob = address(0xB0B);
        
        vm.startBroadcast(deployerKey);
        
        console.log("=== Bridge Me Not V2 Demo ===");
        console.log("Alice:", alice);
        console.log("Bob:", bob);
        
        // Deploy mock token
        MockERC20 token = new MockERC20("Demo USDC", "USDC", 6);
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
        (
            address _token,
            address _sender,
            address _recipient,
            uint256 _amount,
            bytes32 _hashlock,
            uint256 _timelock,
            bool _funded,
            bool _withdrawn,
            bool _refunded,
            bytes32 _preimage
        ) = SimpleEscrow(escrow).getDetails();
        
        console.log("\n=== Escrow Details ===");
        console.log("Amount locked:", _amount / 10**6, "USDC");
        console.log("Funded:", _funded);
        console.log("Can withdraw:", SimpleEscrow(escrow).canWithdraw());
        
        // Simulate Bob withdrawing with secret
        vm.stopBroadcast();
        vm.startBroadcast(uint256(0xB0B)); // Switch to Bob
        
        console.log("\n=== Bob Withdrawing ===");
        SimpleEscrow(escrow).withdraw(secret);
        console.log("Withdrawal successful!");
        
        // Check final state
        (, , , , , , , bool withdrawn, , bytes32 revealedPreimage) = SimpleEscrow(escrow).getDetails();
        console.log("Withdrawn:", withdrawn);
        console.log("Revealed preimage:", vm.toString(revealedPreimage));
        console.log("Bob's balance:", token.balanceOf(bob) / 10**6, "USDC");
        
        console.log("\n=== Demo Complete! ===");
        console.log("Atomic swap executed successfully without any bridge!");
        
        vm.stopBroadcast();
    }
}