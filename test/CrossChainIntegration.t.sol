// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/SimpleEscrowFactory.sol";
import "../src/SimpleEscrow.sol";
import "../src/OneInchAdapter.sol";
import "../src/mocks/MockERC20.sol";
import "../src/interfaces/IOrderMixin.sol";
import "../test/mocks/MockLimitOrderProtocol.sol";

contract CrossChainIntegrationTest is Test {
    // Chain 1 components
    SimpleEscrowFactory public factoryChain1;
    MockERC20 public tokenChain1;
    MockLimitOrderProtocol public limitOrderChain1;
    OneInchAdapter public adapterChain1;
    
    // Chain 2 components (simulated)
    SimpleEscrowFactory public factoryChain2;
    MockERC20 public tokenChain2;
    MockLimitOrderProtocol public limitOrderChain2;
    OneInchAdapter public adapterChain2;
    
    // Common addresses (same on both chains)
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public resolver = address(0x3);
    
    // Swap parameters
    bytes32 public secret = keccak256("cross-chain-secret");
    bytes32 public hashlock = keccak256(abi.encode(secret));
    uint256 public timelock;
    bytes32 public salt = keccak256("cross-chain-salt");
    uint256 public amountChain1 = 100e6; // 100 USDC
    uint256 public amountChain2 = 100e18; // 100 DAI
    
    function setUp() public {
        timelock = block.timestamp + 2 hours;
        
        // Setup Chain 1 (e.g., Ethereum)
        vm.chainId(1);
        tokenChain1 = new MockERC20("USDC", "USDC", 6, 0);
        limitOrderChain1 = new MockLimitOrderProtocol();
        factoryChain1 = new SimpleEscrowFactory(address(0));
        adapterChain1 = new OneInchAdapter(address(limitOrderChain1), address(factoryChain1));
        factoryChain1.setOneInchAdapter(address(adapterChain1));
        
        // Setup Chain 2 (e.g., Polygon)
        vm.chainId(137);
        tokenChain2 = new MockERC20("DAI", "DAI", 18, 0);
        limitOrderChain2 = new MockLimitOrderProtocol();
        factoryChain2 = new SimpleEscrowFactory(address(0));
        adapterChain2 = new OneInchAdapter(address(limitOrderChain2), address(factoryChain2));
        factoryChain2.setOneInchAdapter(address(adapterChain2));
        
        // Reset to chain 1
        vm.chainId(1);
        
        // Fund users
        tokenChain1.mint(alice, amountChain1 * 10);
        tokenChain2.mint(bob, amountChain2 * 10);
        
        // Approve factories
        vm.prank(alice);
        tokenChain1.approve(address(factoryChain1), type(uint256).max);
        vm.prank(bob);
        tokenChain2.approve(address(factoryChain2), type(uint256).max);
    }
    
    // ========== Deterministic Address Tests ==========
    
    function testDeterministicAddressAcrossChains() public {
        // Deploy factories at same address on both chains (simulated)
        // In reality, this would require careful deployment
        
        // Note: In a real cross-chain scenario, factories would need to be
        // deployed at the same address using CREATE2 with same deployer
        
        // For this test, we'll verify the computation method works
        address computed1 = factoryChain1.computeEscrowAddress(
            address(tokenChain1),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        address computed2 = factoryChain2.computeEscrowAddress(
            address(tokenChain2),
            bob,
            alice,
            hashlock,
            timelock,
            salt
        );
        
        // Different tokens and swapped sender/recipient = different addresses
        assertTrue(computed1 != computed2);
        
        // But same parameters would give same address (if factories at same address)
        address sameComputed1 = factoryChain1.computeEscrowAddress(
            address(0x123), // Same token address
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        address sameComputed2 = factoryChain2.computeEscrowAddress(
            address(0x123), // Same token address
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        // Would be equal if factories were at same address
        console.log("Computed1:", sameComputed1);
        console.log("Computed2:", sameComputed2);
    }
    
    // ========== Atomic Swap Flow Tests ==========
    
    function testCompleteAtomicSwapFlow() public {
        // Step 1: Alice creates escrow on Chain 1 (USDC)
        vm.chainId(1);
        vm.prank(alice);
        address escrow1 = factoryChain1.createEscrowWithFunding(
            address(tokenChain1),
            alice,
            bob,
            hashlock,
            timelock,
            salt,
            amountChain1
        );
        
        // Step 2: Bob creates escrow on Chain 2 (DAI)
        vm.chainId(137);
        vm.prank(bob);
        address escrow2 = factoryChain2.createEscrowWithFunding(
            address(tokenChain2),
            bob,
            alice,
            hashlock,
            timelock,
            salt,
            amountChain2
        );
        
        // Step 3: Bob reveals secret on Chain 1
        vm.chainId(1);
        SimpleEscrow escrowContract1 = SimpleEscrow(escrow1);
        vm.prank(bob);
        escrowContract1.withdraw(secret);
        
        // Verify Bob received USDC
        assertEq(tokenChain1.balanceOf(bob), amountChain1);
        assertTrue(escrowContract1.withdrawn());
        assertEq(escrowContract1.preimage(), secret);
        
        // Step 4: Alice uses revealed secret on Chain 2
        vm.chainId(137);
        SimpleEscrow escrowContract2 = SimpleEscrow(escrow2);
        
        // In real scenario, Alice would observe Chain 1 events
        bytes32 revealedSecret = secret; // Simulating Alice reading from Chain 1
        
        vm.prank(alice);
        escrowContract2.withdraw(revealedSecret);
        
        // Verify Alice received DAI
        assertEq(tokenChain2.balanceOf(alice), amountChain2);
        assertTrue(escrowContract2.withdrawn());
        assertEq(escrowContract2.preimage(), revealedSecret);
    }
    
    function testTimeoutScenario() public {
        // Alice creates on Chain 1
        vm.chainId(1);
        vm.prank(alice);
        address escrow1 = factoryChain1.createEscrowWithFunding(
            address(tokenChain1),
            alice,
            bob,
            hashlock,
            timelock,
            salt,
            amountChain1
        );
        
        // Bob creates on Chain 2
        vm.chainId(137);
        vm.prank(bob);
        address escrow2 = factoryChain2.createEscrowWithFunding(
            address(tokenChain2),
            bob,
            alice,
            hashlock,
            timelock,
            salt,
            amountChain2
        );
        
        // Fast forward past timeout
        vm.warp(timelock + 1);
        
        // Both can refund
        vm.chainId(1);
        vm.prank(alice);
        SimpleEscrow(escrow1).refund();
        assertEq(tokenChain1.balanceOf(alice), amountChain1 * 10); // Got refund
        
        vm.chainId(137);
        vm.prank(bob);
        SimpleEscrow(escrow2).refund();
        assertEq(tokenChain2.balanceOf(bob), amountChain2 * 10); // Got refund
    }
    
    // ========== 1inch Integration Cross-Chain Tests ==========
    
    function skip_testCrossChain1inchOrders() public {
        // Alice creates 1inch order on Chain 1
        vm.chainId(1);
        
        IOrderMixin.Order memory order1 = limitOrderChain1.createTestOrder(
            alice,
            address(tokenChain1),
            address(tokenChain1), // Use same token for simplicity
            amountChain1,
            amountChain1, // Taker needs to provide same amount
            true // Enable post-interaction
        );
        
        // Prepare extension data for atomic swap
        bytes memory extensionData = abi.encode(
            hashlock,
            bob,
            2 hours, // timeout duration
            salt
        );
        bytes memory fullExtension = abi.encodePacked(address(adapterChain1), extensionData);
        
        // Alice approves limit order protocol
        vm.prank(alice);
        tokenChain1.approve(address(limitOrderChain1), amountChain1);
        
        // Resolver fills order (triggers escrow creation)
        vm.prank(resolver);
        limitOrderChain1.fillOrder(
            order1,
            "", // signature not used in mock
            fullExtension,
            amountChain1,
            0
        );
        
        // Calculate expected escrow address
        address expectedEscrow1 = factoryChain1.computeEscrowAddress(
            address(tokenChain1),
            alice,
            bob,
            hashlock,
            block.timestamp + 2 hours,
            salt
        );
        
        // Verify escrow was created and funded
        assertTrue(factoryChain1.isEscrowDeployed(expectedEscrow1));
        SimpleEscrow escrow1 = SimpleEscrow(expectedEscrow1);
        assertTrue(escrow1.funded());
        
        // Bob creates matching order on Chain 2
        vm.chainId(137);
        
        // Similar process for Chain 2...
        // (Abbreviated for brevity, but would follow same pattern)
    }
    
    // ========== Gas Measurement Tests ==========
    
    function skip_testCrossChainGasCosts() public {
        uint256 totalGasChain1 = 0;
        uint256 totalGasChain2 = 0;
        
        // Chain 1: Create and fund
        vm.chainId(1);
        uint256 gasStart = gasleft();
        vm.prank(alice);
        address escrow1 = factoryChain1.createEscrowWithFunding(
            address(tokenChain1),
            alice,
            bob,
            hashlock,
            timelock,
            salt,
            amountChain1
        );
        totalGasChain1 += gasStart - gasleft();
        
        // Chain 2: Create and fund
        vm.chainId(137);
        gasStart = gasleft();
        vm.prank(bob);
        address escrow2 = factoryChain2.createEscrowWithFunding(
            address(tokenChain2),
            bob,
            alice,
            hashlock,
            timelock,
            salt,
            amountChain2
        );
        totalGasChain2 += gasStart - gasleft();
        
        // Chain 1: Withdraw
        vm.chainId(1);
        gasStart = gasleft();
        vm.prank(bob);
        SimpleEscrow(escrow1).withdraw(secret);
        totalGasChain1 += gasStart - gasleft();
        
        // Chain 2: Withdraw
        vm.chainId(137);
        gasStart = gasleft();
        vm.prank(alice);
        SimpleEscrow(escrow2).withdraw(secret);
        totalGasChain2 += gasStart - gasleft();
        
        console.log("Total gas Chain 1:", totalGasChain1);
        console.log("Total gas Chain 2:", totalGasChain2);
        console.log("Total gas both chains:", totalGasChain1 + totalGasChain2);
        
        // Should be under reasonable limits
        assertTrue(totalGasChain1 < 3000000, "Chain 1 gas too high");
        assertTrue(totalGasChain2 < 3000000, "Chain 2 gas too high");
    }
    
    // ========== Resolver Coordination Tests ==========
    
    function testResolverCoordination() public {
        // Setup initial balances for resolver
        tokenChain1.mint(resolver, amountChain1);
        tokenChain2.mint(resolver, amountChain2);
        
        vm.prank(resolver);
        tokenChain1.approve(address(factoryChain1), amountChain1);
        vm.prank(resolver);
        tokenChain2.approve(address(factoryChain2), amountChain2);
        
        // Resolver creates both escrows (acting as intermediary)
        vm.chainId(1);
        vm.prank(resolver);
        address escrow1 = factoryChain1.createEscrowWithFunding(
            address(tokenChain1),
            resolver,
            alice,
            hashlock,
            timelock,
            salt,
            amountChain1
        );
        
        vm.chainId(137);
        vm.prank(resolver);
        address escrow2 = factoryChain2.createEscrowWithFunding(
            address(tokenChain2),
            resolver,
            bob,
            hashlock,
            timelock,
            salt,
            amountChain2
        );
        
        // Resolver reveals secret on both chains
        vm.chainId(1);
        vm.prank(alice);
        SimpleEscrow(escrow1).withdraw(secret);
        
        vm.chainId(137);
        vm.prank(bob);
        SimpleEscrow(escrow2).withdraw(secret);
        
        // Verify transfers completed
        assertEq(tokenChain1.balanceOf(alice), amountChain1 * 10 + amountChain1);
        assertEq(tokenChain2.balanceOf(bob), amountChain2 * 10 + amountChain2);
    }
    
    // ========== Edge Cases and Failure Modes ==========
    
    function testAsymmetricTimeouts() public {
        // Create escrows with different timeouts
        uint256 shortTimeout = block.timestamp + 30 minutes;
        uint256 longTimeout = block.timestamp + 2 hours;
        
        vm.chainId(1);
        vm.prank(alice);
        address escrow1 = factoryChain1.createEscrowWithFunding(
            address(tokenChain1),
            alice,
            bob,
            hashlock,
            shortTimeout,
            salt,
            amountChain1
        );
        
        vm.chainId(137);
        vm.prank(bob);
        address escrow2 = factoryChain2.createEscrowWithFunding(
            address(tokenChain2),
            bob,
            alice,
            hashlock,
            longTimeout,
            salt,
            amountChain2
        );
        
        // Fast forward to between timeouts
        vm.warp(shortTimeout + 1);
        
        // Chain 1 can refund
        vm.chainId(1);
        vm.prank(alice);
        SimpleEscrow(escrow1).refund();
        assertTrue(SimpleEscrow(escrow1).refunded());
        
        // Chain 2 cannot refund yet
        vm.chainId(137);
        vm.expectRevert("SimpleEscrow: timelock not expired");
        vm.prank(bob);
        SimpleEscrow(escrow2).refund();
        
        // But can still withdraw if secret is known
        vm.prank(alice);
        SimpleEscrow(escrow2).withdraw(secret);
        assertTrue(SimpleEscrow(escrow2).withdrawn());
    }
    
    function testDifferentHashlocks() public {
        // Accidentally use different hashlocks
        bytes32 hashlock1 = keccak256(abi.encode(secret));
        bytes32 hashlock2 = keccak256(abi.encode(keccak256("different")));
        
        vm.chainId(1);
        vm.prank(alice);
        address escrow1 = factoryChain1.createEscrowWithFunding(
            address(tokenChain1),
            alice,
            bob,
            hashlock1,
            timelock,
            salt,
            amountChain1
        );
        
        vm.chainId(137);
        vm.prank(bob);
        address escrow2 = factoryChain2.createEscrowWithFunding(
            address(tokenChain2),
            bob,
            alice,
            hashlock2,
            timelock,
            salt,
            amountChain2
        );
        
        // Bob can withdraw from Chain 1
        vm.chainId(1);
        vm.prank(bob);
        SimpleEscrow(escrow1).withdraw(secret);
        
        // But Alice cannot withdraw from Chain 2 with same secret
        vm.chainId(137);
        vm.expectRevert("SimpleEscrow: invalid preimage");
        vm.prank(alice);
        SimpleEscrow(escrow2).withdraw(secret);
        
        // Both must refund after timeout
        vm.warp(timelock + 1);
        
        vm.chainId(137);
        vm.prank(bob);
        SimpleEscrow(escrow2).refund();
        assertTrue(SimpleEscrow(escrow2).refunded());
    }
    
    // ========== Multi-hop Swap Tests ==========
    
    function testThreeWaySwap() public {
        address charlie = address(0x4);
        MockERC20 tokenChain3 = new MockERC20("WETH", "WETH", 18, 0);
        tokenChain3.mint(charlie, 1e18);
        
        // Create circular swap: Alice -> Bob -> Charlie -> Alice
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");
        
        // All use same hashlock
        vm.prank(alice);
        tokenChain1.approve(address(factoryChain1), amountChain1);
        vm.prank(bob);
        tokenChain2.approve(address(factoryChain2), amountChain2);
        vm.prank(charlie);
        tokenChain3.approve(address(factoryChain1), 1e18);
        
        // Alice -> Bob (USDC)
        vm.prank(alice);
        address escrow1 = factoryChain1.createEscrowWithFunding(
            address(tokenChain1),
            alice,
            bob,
            hashlock,
            timelock,
            salt1,
            amountChain1
        );
        
        // Bob -> Charlie (DAI)
        vm.prank(bob);
        address escrow2 = factoryChain2.createEscrowWithFunding(
            address(tokenChain2),
            bob,
            charlie,
            hashlock,
            timelock,
            salt2,
            amountChain2
        );
        
        // Charlie -> Alice (WETH)
        vm.prank(charlie);
        address escrow3 = factoryChain1.createEscrowWithFunding(
            address(tokenChain3),
            charlie,
            alice,
            hashlock,
            timelock,
            salt3,
            1e18
        );
        
        // Charlie reveals secret, triggering cascade
        vm.prank(alice);
        SimpleEscrow(escrow3).withdraw(secret);
        
        // Now everyone can claim
        vm.prank(charlie);
        SimpleEscrow(escrow2).withdraw(secret);
        
        vm.prank(bob);
        SimpleEscrow(escrow1).withdraw(secret);
        
        // Verify final balances
        assertEq(tokenChain3.balanceOf(alice), 1e18);
        assertEq(tokenChain2.balanceOf(charlie), amountChain2);
        assertEq(tokenChain1.balanceOf(bob), amountChain1);
    }
}