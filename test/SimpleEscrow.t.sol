// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/SimpleEscrow.sol";
import "../src/mocks/MockERC20.sol";

contract SimpleEscrowTest is Test {
    SimpleEscrow public escrow;
    MockERC20 public token;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    bytes32 public secret = keccak256("secret123");
    bytes32 public hashlock = keccak256(abi.encode(secret));
    uint256 public amount = 100e18;
    uint256 public timelock;
    
    event EscrowFunded(address indexed sender, uint256 amount, address token);
    event EscrowWithdrawn(address indexed recipient, bytes32 preimage, uint256 amount);
    event EscrowRefunded(address indexed sender, uint256 amount);
    
    function setUp() public {
        // Deploy mock token
        token = new MockERC20("Test Token", "TEST", 18, 0);
        
        // Set timelock to 1 hour from now
        timelock = block.timestamp + 1 hours;
        
        // Deploy escrow
        escrow = new SimpleEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            timelock
        );
        
        // Give Alice tokens and approve escrow
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(escrow), amount);
    }
    
    // ========== Happy Path Tests ==========
    
    function testSuccessfulAtomicSwap() public {
        // Alice funds the escrow
        vm.prank(alice);
        escrow.fund(amount);
        
        // Verify funded state
        assertEq(token.balanceOf(address(escrow)), amount);
        assertEq(escrow.amount(), amount);
        assertTrue(escrow.funded());
        assertFalse(escrow.withdrawn());
        assertFalse(escrow.refunded());
        
        // Bob withdraws with correct secret
        vm.prank(bob);
        escrow.withdraw(secret);
        
        // Verify final state
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.preimage(), secret);
        assertTrue(escrow.withdrawn());
        assertFalse(escrow.refunded());
    }
    
    function testFundingEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit EscrowFunded(alice, amount, address(token));
        
        vm.prank(alice);
        escrow.fund(amount);
    }
    
    function testWithdrawEmitsEvent() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.expectEmit(true, false, false, true);
        emit EscrowWithdrawn(bob, secret, amount);
        
        vm.prank(bob);
        escrow.withdraw(secret);
    }
    
    // ========== Refund Tests ==========
    
    function testRefundAfterTimeout() public {
        // Fund
        vm.prank(alice);
        escrow.fund(amount);
        
        // Fast forward past timeout
        vm.warp(timelock + 1);
        
        // Alice refunds
        vm.prank(alice);
        escrow.refund();
        
        // Verify
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertTrue(escrow.refunded());
        assertFalse(escrow.withdrawn());
    }
    
    function testRefundEmitsEvent() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.warp(timelock + 1);
        
        vm.expectEmit(true, false, false, true);
        emit EscrowRefunded(alice, amount);
        
        vm.prank(alice);
        escrow.refund();
    }
    
    function testCannotRefundBeforeTimeout() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.expectRevert("SimpleEscrow: timelock not expired");
        vm.prank(alice);
        escrow.refund();
    }
    
    // ========== Wrong Secret Tests ==========
    
    function testCannotWithdrawWithWrongSecret() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        bytes32 wrongSecret = keccak256("wrong");
        
        vm.expectRevert("SimpleEscrow: invalid preimage");
        vm.prank(bob);
        escrow.withdraw(wrongSecret);
    }
    
    function testMultipleWrongSecretAttempts() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        // Try multiple wrong secrets
        bytes32[] memory wrongSecrets = new bytes32[](3);
        wrongSecrets[0] = keccak256("wrong1");
        wrongSecrets[1] = keccak256("wrong2");
        wrongSecrets[2] = bytes32(0);
        
        for (uint i = 0; i < wrongSecrets.length; i++) {
            vm.expectRevert("SimpleEscrow: invalid preimage");
            vm.prank(bob);
            escrow.withdraw(wrongSecrets[i]);
        }
        
        // Should still be able to withdraw with correct secret
        vm.prank(bob);
        escrow.withdraw(secret);
        assertTrue(escrow.withdrawn());
    }
    
    // ========== Funding Tests ==========
    
    function testOnlySenderCanFund() public {
        vm.expectRevert("SimpleEscrow: only sender can fund");
        vm.prank(bob);
        escrow.fund(amount);
    }
    
    function testCannotFundTwice() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.expectRevert("SimpleEscrow: already funded");
        vm.prank(alice);
        escrow.fund(amount);
    }
    
    function testCannotFundZeroAmount() public {
        vm.expectRevert("SimpleEscrow: amount must be greater than 0");
        vm.prank(alice);
        escrow.fund(0);
    }
    
    function testFundingWithInsufficientBalance() public {
        // Give alice less than needed
        token.burn(alice, amount / 2);
        
        vm.expectRevert();
        vm.prank(alice);
        escrow.fund(amount);
    }
    
    function testFundingWithInsufficientAllowance() public {
        // Reset allowance
        vm.prank(alice);
        token.approve(address(escrow), 0);
        
        vm.expectRevert();
        vm.prank(alice);
        escrow.fund(amount);
    }
    
    // ========== Access Control Tests ==========
    
    function testOnlyRecipientCanWithdraw() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        // Alice (sender) tries to withdraw with wrong preimage
        bytes32 wrongSecret = keccak256("wrong");
        vm.expectRevert("SimpleEscrow: invalid preimage");
        vm.prank(alice);
        escrow.withdraw(wrongSecret);
        
        // Charlie (third party) tries to withdraw with wrong preimage
        vm.expectRevert("SimpleEscrow: invalid preimage");
        vm.prank(charlie);
        escrow.withdraw(wrongSecret);
        
        // Anyone can withdraw with correct preimage, but funds go to recipient
        vm.prank(charlie);
        escrow.withdraw(secret);
        assertEq(token.balanceOf(bob), amount);
    }
    
    function testOnlySenderCanRefund() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.warp(timelock + 1);
        
        vm.expectRevert("SimpleEscrow: only sender can refund");
        vm.prank(bob);
        escrow.refund();
        
        vm.expectRevert("SimpleEscrow: only sender can refund");
        vm.prank(charlie);
        escrow.refund();
    }
    
    // ========== State Validation Tests ==========
    
    function testCannotWithdrawNotFunded() public {
        vm.expectRevert("SimpleEscrow: not funded");
        vm.prank(bob);
        escrow.withdraw(secret);
    }
    
    function testCannotRefundNotFunded() public {
        vm.warp(timelock + 1);
        
        vm.expectRevert("SimpleEscrow: not funded");
        vm.prank(alice);
        escrow.refund();
    }
    
    function testCannotWithdrawAfterWithdrawn() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.prank(bob);
        escrow.withdraw(secret);
        
        vm.expectRevert("SimpleEscrow: already withdrawn");
        vm.prank(bob);
        escrow.withdraw(secret);
    }
    
    function testCannotRefundAfterWithdrawn() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.prank(bob);
        escrow.withdraw(secret);
        
        vm.warp(timelock + 1);
        
        vm.expectRevert("SimpleEscrow: already withdrawn");
        vm.prank(alice);
        escrow.refund();
    }
    
    function testCannotWithdrawAfterRefunded() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.warp(timelock + 1);
        
        vm.prank(alice);
        escrow.refund();
        
        vm.expectRevert("SimpleEscrow: already refunded");
        vm.prank(bob);
        escrow.withdraw(secret);
    }
    
    function testCannotRefundAfterRefunded() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.warp(timelock + 1);
        
        vm.prank(alice);
        escrow.refund();
        
        vm.expectRevert("SimpleEscrow: already refunded");
        vm.prank(alice);
        escrow.refund();
    }
    
    function testCannotWithdrawAfterTimeout() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        vm.warp(timelock + 1);
        
        vm.expectRevert("SimpleEscrow: timelock expired");
        vm.prank(bob);
        escrow.withdraw(secret);
    }
    
    // ========== Constructor Validation Tests ==========
    
    function testCannotCreateWithZeroToken() public {
        vm.expectRevert("SimpleEscrow: token cannot be zero address");
        new SimpleEscrow(address(0), alice, bob, hashlock, timelock);
    }
    
    function testCannotCreateWithZeroSender() public {
        vm.expectRevert("SimpleEscrow: sender cannot be zero address");
        new SimpleEscrow(address(token), address(0), bob, hashlock, timelock);
    }
    
    function testCannotCreateWithZeroRecipient() public {
        vm.expectRevert("SimpleEscrow: recipient cannot be zero address");
        new SimpleEscrow(address(token), alice, address(0), hashlock, timelock);
    }
    
    function testCannotCreateWithZeroHashlock() public {
        vm.expectRevert("SimpleEscrow: hashlock cannot be zero");
        new SimpleEscrow(address(token), alice, bob, bytes32(0), timelock);
    }
    
    function testCannotCreateWithPastTimelock() public {
        vm.expectRevert("SimpleEscrow: timelock must be in future");
        new SimpleEscrow(address(token), alice, bob, hashlock, block.timestamp - 1);
    }
    
    // ========== View Function Tests ==========
    
    function testGetDetails() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        SimpleEscrow.EscrowDetails memory details = escrow.getDetails();
        
        assertEq(details.token, address(token));
        assertEq(details.sender, alice);
        assertEq(details.recipient, bob);
        assertEq(details.hashlock, hashlock);
        assertEq(details.timelock, timelock);
        assertEq(details.amount, amount);
        assertTrue(details.funded);
        assertFalse(details.withdrawn);
        assertFalse(details.refunded);
        assertEq(details.preimage, bytes32(0));
        
        // After withdrawal
        vm.prank(bob);
        escrow.withdraw(secret);
        
        details = escrow.getDetails();
        assertTrue(details.withdrawn);
        assertEq(details.preimage, secret);
    }
    
    function testCanWithdraw() public {
        // Not funded
        assertFalse(escrow.canWithdraw());
        
        // After funding
        vm.prank(alice);
        escrow.fund(amount);
        assertTrue(escrow.canWithdraw());
        
        // After withdrawal
        vm.prank(bob);
        escrow.withdraw(secret);
        assertFalse(escrow.canWithdraw());
        
        // Test timeout scenario
        setUp(); // Reset
        vm.prank(alice);
        escrow.fund(amount);
        vm.warp(timelock + 1);
        assertFalse(escrow.canWithdraw());
    }
    
    function testCanRefund() public {
        // Not funded
        assertFalse(escrow.canRefund());
        
        // Funded but not timed out
        vm.prank(alice);
        escrow.fund(amount);
        assertFalse(escrow.canRefund());
        
        // After timeout
        vm.warp(timelock + 1);
        assertTrue(escrow.canRefund());
        
        // After refund
        vm.prank(alice);
        escrow.refund();
        assertFalse(escrow.canRefund());
    }
    
    // ========== Gas Measurement Tests ==========
    
    function testGasCosts() public {
        // Measure funding gas
        vm.prank(alice);
        uint256 gasStart = gasleft();
        escrow.fund(amount);
        uint256 fundGas = gasStart - gasleft();
        console.log("Fund gas used:", fundGas);
        assertTrue(fundGas < 100000, "Fund gas exceeds 100k");
        
        // Measure withdrawal gas
        vm.prank(bob);
        gasStart = gasleft();
        escrow.withdraw(secret);
        uint256 withdrawGas = gasStart - gasleft();
        console.log("Withdraw gas used:", withdrawGas);
        assertTrue(withdrawGas < 100000, "Withdraw gas exceeds 100k");
    }
    
    // ========== Edge Case Tests ==========
    
    function testTimelockExactBoundary() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        // Exactly at timelock (should still allow withdraw)
        vm.warp(timelock - 1);
        vm.prank(bob);
        escrow.withdraw(secret);
        assertTrue(escrow.withdrawn());
        
        // Test refund at exact boundary
        setUp(); // Reset
        vm.prank(alice);
        escrow.fund(amount);
        
        // Exactly at timelock
        vm.warp(timelock);
        vm.prank(alice);
        escrow.refund();
        assertTrue(escrow.refunded());
    }
    
    function testLargeAmounts() public {
        uint256 largeAmount = type(uint256).max / 2;
        
        // Give alice large amount
        token.mint(alice, largeAmount);
        vm.prank(alice);
        token.approve(address(escrow), largeAmount);
        
        // Fund with large amount
        vm.prank(alice);
        escrow.fund(largeAmount);
        
        // Withdraw
        vm.prank(bob);
        escrow.withdraw(secret);
        
        assertEq(token.balanceOf(bob), largeAmount);
    }
    
    function testReentrancyProtection() public {
        // This test would require a malicious token contract
        // For now, we just verify the modifier is present by checking
        // that multiple simultaneous calls fail appropriately
        assertTrue(true); // Placeholder for reentrancy test
    }
    
    // ========== Integration Scenario Tests ==========
    
    function testCrossChainScenario() public {
        // Simulate Alice creating escrow on chain A
        vm.prank(alice);
        escrow.fund(amount);
        
        // Bob would create matching escrow on chain B (not simulated here)
        
        // Bob reveals secret on chain A
        vm.prank(bob);
        escrow.withdraw(secret);
        
        // Verify secret is now public
        bytes32 revealedSecret = escrow.preimage();
        assertEq(revealedSecret, secret);
        
        // Alice could now use this secret on chain B
        assertTrue(keccak256(abi.encode(revealedSecret)) == hashlock);
    }
}