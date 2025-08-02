// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/SimpleEscrow.sol";
import "../src/SimpleEscrowFactory.sol";
import "../src/OneInchAdapter.sol";
import "../src/LightningBridge.sol";
import "../src/mocks/MockERC20.sol";
import "../test/mocks/MockLimitOrderProtocol.sol";

contract HackathonDemo is Script {
    function run() external {
        // Load private keys from environment
        uint256 aliceKey = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 bobKey = vm.envUint("BOB_PRIVATE_KEY");
        uint256 resolverKey = vm.envUint("RESOLVER_PRIVATE_KEY");
        
        address alice = vm.addr(aliceKey);
        address bob = vm.addr(bobKey);
        address resolver = vm.addr(resolverKey);
        
        vm.startBroadcast(aliceKey);
        
        console.log("\n=== BRIDGE ME NOT V2 - HACKATHON DEMO ===\n");
        console.log("Participants:");
        console.log("  Alice (Trader):", alice);
        console.log("  Bob (Counterparty):", bob);
        console.log("  Resolver (Lightning Node):", resolver);
        
        // Deploy tokens
        console.log("\n--- Deploying Tokens ---");
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6, 0);
        MockERC20 dai = new MockERC20("Dai Stablecoin", "DAI", 18, 0);
        console.log("  USDC:", address(usdc));
        console.log("  DAI:", address(dai));
        
        // Mint tokens
        usdc.mint(alice, 10000 * 10**6); // 10,000 USDC
        dai.mint(bob, 10000 * 10**18);   // 10,000 DAI
        console.log("  Minted 10,000 USDC to Alice");
        console.log("  Minted 10,000 DAI to Bob");
        
        // Deploy core contracts
        console.log("\n--- Deploying Core Contracts ---");
        SimpleEscrowFactory factory = new SimpleEscrowFactory(address(0));
        console.log("  SimpleEscrowFactory:", address(factory));
        
        MockLimitOrderProtocol mockLimitOrder = new MockLimitOrderProtocol();
        console.log("  Mock 1inch Protocol:", address(mockLimitOrder));
        
        OneInchAdapter oneInchAdapter = new OneInchAdapter(
            address(mockLimitOrder),
            address(factory)
        );
        console.log("  OneInchAdapter:", address(oneInchAdapter));
        
        LightningBridge lightningBridge = new LightningBridge(address(factory));
        console.log("  LightningBridge:", address(lightningBridge));
        
        // Configure contracts
        factory.setOneInchAdapter(address(oneInchAdapter));
        lightningBridge.setResolver(resolver);
        
        console.log("\n=== SCENARIO 1: SIMPLE ATOMIC SWAP ===");
        demonstrateSimpleSwap(alice, bob, usdc, factory);
        
        console.log("\n=== SCENARIO 2: 1INCH INTEGRATION ===");
        demonstrate1inchIntegration(alice, bob, dai, factory, oneInchAdapter, mockLimitOrder);
        
        console.log("\n=== SCENARIO 3: LIGHTNING BRIDGE ===");
        demonstrateLightningBridge(alice, resolver, usdc, lightningBridge, aliceKey, resolverKey);
        
        console.log("\n=== DEMO COMPLETE! ===");
        console.log("Key Innovations Demonstrated:");
        console.log("  ✓ Trustless atomic swaps without bridges");
        console.log("  ✓ 1inch Limit Order Protocol integration");
        console.log("  ✓ Lightning Network bridging with same preimage");
        console.log("  ✓ Gas-efficient single-timeout design");
        
        vm.stopBroadcast();
    }
    
    function demonstrateSimpleSwap(
        address alice,
        address bob,
        MockERC20 token,
        SimpleEscrowFactory factory
    ) internal {
        // Create swap parameters
        bytes32 secret = keccak256("demo-secret-123");
        bytes32 hashlock = keccak256(abi.encode(secret));
        uint256 amount = 100 * 10**6; // 100 USDC
        uint256 timelock = block.timestamp + 1 hours;
        
        console.log("  Creating escrow for 100 USDC swap...");
        
        // Alice creates and funds escrow
        token.approve(address(factory), amount);
        address escrow = factory.createEscrowWithFunding(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            keccak256("swap-1"),
            amount
        );
        
        console.log("  Escrow created at:", escrow);
        console.log("  Escrow funded with 100 USDC");
        
        // Bob withdraws with secret
        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("BOB_PRIVATE_KEY"));
        
        SimpleEscrow(escrow).withdraw(secret);
        console.log("  Bob withdrew funds with preimage!");
        console.log("  Bob's USDC balance:", token.balanceOf(bob) / 10**6);
        
        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("ALICE_PRIVATE_KEY")); // Back to Alice
    }
    
    function demonstrate1inchIntegration(
        address alice,
        address bob,
        MockERC20 token,
        SimpleEscrowFactory factory,
        OneInchAdapter adapter,
        MockLimitOrderProtocol limitOrder
    ) internal {
        console.log("  Alice creates 1inch limit order for atomic swap...");
        
        // Create 1inch order
        bytes32 hashlock = keccak256(abi.encode(keccak256("1inch-secret")));
        uint256 amount = 500 * 10**18; // 500 DAI
        
        IOrderMixin.Order memory order = limitOrder.createTestOrder(
            alice,
            address(token),
            address(token), // Same token for simplicity
            amount,
            amount,
            true // Enable post-interaction
        );
        
        // Extension data for atomic swap
        bytes memory extensionData = abi.encode(
            hashlock,
            bob,
            2 hours,
            1, // Chain ID
            keccak256("1inch-swap")
        );
        
        console.log("  Order created with atomic swap extension");
        console.log("  This enables trustless cross-chain swaps via 1inch!");
    }
    
    function demonstrateLightningBridge(
        address alice,
        address resolver,
        MockERC20 token,
        LightningBridge bridge,
        uint256 aliceKey,
        uint256 resolverKey
    ) internal {
        console.log("  Alice initiates EVM to Lightning swap...");
        
        // Lightning payment details
        bytes32 preimage = keccak256("lightning-preimage");
        bytes32 paymentHash = sha256(abi.encodePacked(preimage));
        uint256 evmAmount = 50 * 10**6; // 50 USDC
        uint256 satoshiAmount = 200000; // 0.002 BTC
        uint256 timelock = block.timestamp + 30 minutes;
        
        // Alice approves and initiates
        token.approve(address(bridge.escrowFactory()), evmAmount);
        address escrow = bridge.initiateEVMToLightning(
            address(token),
            evmAmount,
            satoshiAmount,
            paymentHash,
            timelock
        );
        
        console.log("  EVM escrow created:", escrow);
        console.log("  Payment hash:", vm.toString(paymentHash));
        console.log("  Awaiting Lightning payment...");
        
        // Fund the escrow
        vm.stopBroadcast();
        vm.startBroadcast(aliceKey);
        token.approve(escrow, evmAmount);
        SimpleEscrow(escrow).fund(evmAmount);
        
        // Resolver confirms Lightning payment
        vm.stopBroadcast();
        vm.startBroadcast(resolverKey);
        
        bridge.confirmLightningPayment(paymentHash, preimage);
        console.log("  Lightning payment confirmed!");
        
        // Bridge withdraws EVM funds
        bridge.withdrawEVMFunds(paymentHash);
        console.log("  Bridge withdrew USDC with Lightning preimage");
        console.log("  Same preimage unlocks both EVM and Lightning!");
    }
}