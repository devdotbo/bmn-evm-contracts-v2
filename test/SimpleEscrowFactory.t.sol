// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/SimpleEscrowFactory.sol";
import "../src/SimpleEscrow.sol";
import "../src/mocks/MockERC20.sol";
import "../src/interfaces/IOrderMixin.sol";
import "../test/mocks/MockLimitOrderProtocol.sol";

contract SimpleEscrowFactoryTest is Test {
    SimpleEscrowFactory public factory;
    MockERC20 public token;
    MockLimitOrderProtocol public mockLimitOrder;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public oneInchAdapter = address(0x3);
    
    bytes32 public secret = keccak256("secret123");
    bytes32 public hashlock = keccak256(abi.encode(secret));
    uint256 public timelock;
    bytes32 public salt = keccak256("salt123");
    uint256 public amount = 100e18;
    
    event EscrowCreated(
        address indexed escrow,
        address indexed sender,
        address indexed recipient,
        address token,
        bytes32 hashlock,
        uint256 timelock,
        uint256 chainId,
        bytes32 salt
    );
    
    event EscrowCreatedFrom1inch(
        address indexed escrow,
        bytes32 indexed orderHash,
        address indexed maker,
        uint256 makingAmount
    );
    
    function setUp() public {
        // Deploy mock token
        token = new MockERC20("Test Token", "TEST", 18, 0);
        
        // Deploy factory with oneInchAdapter
        factory = new SimpleEscrowFactory(oneInchAdapter);
        
        // Deploy mock limit order protocol
        mockLimitOrder = new MockLimitOrderProtocol();
        
        // Set timelock
        timelock = block.timestamp + 1 hours;
        
        // Mint tokens to alice
        token.mint(alice, amount * 10);
        vm.prank(alice);
        token.approve(address(factory), amount * 10);
    }
    
    // ========== Basic Creation Tests ==========
    
    function testCreateEscrow() public {
        // Calculate expected address
        address expectedAddress = factory.computeEscrowAddress(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        // Create escrow
        vm.expectEmit(true, true, true, true);
        emit EscrowCreated(
            expectedAddress,
            alice,
            bob,
            address(token),
            hashlock,
            timelock,
            block.chainid,
            salt
        );
        
        address escrowAddress = factory.createEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        // Verify
        assertEq(escrowAddress, expectedAddress);
        assertTrue(factory.deployedEscrows(escrowAddress));
        assertEq(factory.escrowCount(), 1);
        
        // Verify escrow parameters
        SimpleEscrow escrow = SimpleEscrow(escrowAddress);
        assertEq(escrow.token(), address(token));
        assertEq(escrow.sender(), alice);
        assertEq(escrow.recipient(), bob);
        assertEq(escrow.hashlock(), hashlock);
        assertEq(escrow.timelock(), timelock);
    }
    
    function testCreateEscrowWithFunding() public {
        // Calculate expected address
        address expectedAddress = factory.computeEscrowAddress(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        // Create and fund escrow
        vm.prank(alice);
        address escrowAddress = factory.createEscrowWithFunding(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt,
            amount
        );
        
        // Verify escrow is created and funded
        assertEq(escrowAddress, expectedAddress);
        assertTrue(factory.deployedEscrows(escrowAddress));
        
        SimpleEscrow escrow = SimpleEscrow(escrowAddress);
        assertTrue(escrow.funded());
        assertEq(escrow.amount(), amount);
        assertEq(token.balanceOf(escrowAddress), amount);
    }
    
    function testCannotCreateDuplicateEscrow() public {
        // Create first escrow
        factory.createEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        // Try to create duplicate
        vm.expectRevert("SimpleEscrowFactory: escrow already exists");
        factory.createEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
    }
    
    // ========== Deterministic Address Tests ==========
    
    function testDeterministicAddressCalculation() public {
        // Calculate address before deployment
        address computed = factory.computeEscrowAddress(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        // Deploy and verify
        address deployed = factory.createEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        assertEq(computed, deployed);
    }
    
    function testCrossChainAddressPrediction() public {
        // Deploy two factories (simulating different chains)
        SimpleEscrowFactory factory1 = new SimpleEscrowFactory(address(0));
        SimpleEscrowFactory factory2 = new SimpleEscrowFactory(address(0));
        
        // Same creation parameters
        address token1 = address(0x1234);
        address token2 = address(0x5678);
        
        // If factories are deployed at different addresses, computed addresses will differ
        // But the computation method is consistent
        address computed1 = factory1.computeEscrowAddress(
            token1,
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        address computed2 = factory2.computeEscrowAddress(
            token2,
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        // Different tokens should produce different addresses
        assertTrue(computed1 != computed2);
    }
    
    // ========== Batch Creation Tests ==========
    
    function testBatchCreateEscrows() public {
        SimpleEscrowFactory.EscrowParams[] memory params = new SimpleEscrowFactory.EscrowParams[](3);
        
        params[0] = SimpleEscrowFactory.EscrowParams({
            token: address(token),
            sender: alice,
            recipient: bob,
            hashlock: hashlock,
            timelock: timelock,
            salt: keccak256("salt1")
        });
        
        params[1] = SimpleEscrowFactory.EscrowParams({
            token: address(token),
            sender: alice,
            recipient: bob,
            hashlock: keccak256(abi.encode(keccak256("secret2"))),
            timelock: timelock + 1 hours,
            salt: keccak256("salt2")
        });
        
        params[2] = SimpleEscrowFactory.EscrowParams({
            token: address(token),
            sender: bob,
            recipient: alice,
            hashlock: keccak256(abi.encode(keccak256("secret3"))),
            timelock: timelock + 2 hours,
            salt: keccak256("salt3")
        });
        
        // Create batch
        address[] memory escrows = factory.batchCreateEscrows(params);
        
        // Verify
        assertEq(escrows.length, 3);
        assertEq(factory.escrowCount(), 3);
        
        for (uint i = 0; i < escrows.length; i++) {
            assertTrue(factory.deployedEscrows(escrows[i]));
            
            // Verify parameters match
            SimpleEscrow escrow = SimpleEscrow(escrows[i]);
            assertEq(escrow.token(), params[i].token);
            assertEq(escrow.sender(), params[i].sender);
            assertEq(escrow.recipient(), params[i].recipient);
            assertEq(escrow.hashlock(), params[i].hashlock);
            assertEq(escrow.timelock(), params[i].timelock);
        }
    }
    
    function testBatchCreateWithEmptyArray() public {
        SimpleEscrowFactory.EscrowParams[] memory params = new SimpleEscrowFactory.EscrowParams[](0);
        
        vm.expectRevert("SimpleEscrowFactory: empty params array");
        factory.batchCreateEscrows(params);
    }
    
    // ========== 1inch Integration Tests ==========
    
    function testCreateEscrowFrom1inchOrder() public {
        // Setup order
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: uint256(keccak256("order-salt")),
            makerAsset: address(token),
            takerAsset: address(token), // Same token for simplicity
            maker: alice,
            receiver: address(0),
            allowedSender: address(0),
            makingAmount: amount,
            takingAmount: amount,
            offsets: 0,
            interactions: ""
        });
        
        // Encode extension data
        uint256 timeoutDuration = 1 hours;
        bytes memory extension = abi.encode(hashlock, bob, timeoutDuration, salt);
        
        // Create from 1inch adapter
        vm.prank(oneInchAdapter);
        address escrowAddress = factory.createEscrowFrom1inchOrder(
            order,
            extension,
            amount
        );
        
        // Verify escrow created
        assertTrue(factory.deployedEscrows(escrowAddress));
        
        SimpleEscrow escrow = SimpleEscrow(escrowAddress);
        assertEq(escrow.token(), address(token));
        assertEq(escrow.sender(), alice);
        assertEq(escrow.recipient(), bob);
        assertEq(escrow.hashlock(), hashlock);
        assertEq(escrow.timelock(), block.timestamp + timeoutDuration);
    }
    
    function testOnlyOneInchAdapterCanCreate1inchEscrow() public {
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 0,
            makerAsset: address(token),
            takerAsset: address(token),
            maker: alice,
            receiver: address(0),
            allowedSender: address(0),
            makingAmount: amount,
            takingAmount: amount,
            offsets: 0,
            interactions: ""
        });
        
        bytes memory extension = abi.encode(hashlock, bob, 1 hours, salt);
        
        vm.expectRevert("SimpleEscrowFactory: only 1inch adapter");
        factory.createEscrowFrom1inchOrder(order, extension, amount);
    }
    
    function testSetOneInchAdapter() public {
        address newAdapter = address(0x999);
        
        // Only owner can set
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        factory.setOneInchAdapter(newAdapter);
        
        // Owner sets successfully
        factory.setOneInchAdapter(newAdapter);
        assertEq(factory.oneInchAdapter(), newAdapter);
    }
    
    // ========== Parameter Validation Tests ==========
    
    function testCannotCreateWithZeroToken() public {
        vm.expectRevert("SimpleEscrowFactory: token cannot be zero address");
        factory.createEscrow(
            address(0),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
    }
    
    function testCannotCreateWithZeroSender() public {
        vm.expectRevert("SimpleEscrowFactory: sender cannot be zero address");
        factory.createEscrow(
            address(token),
            address(0),
            bob,
            hashlock,
            timelock,
            salt
        );
    }
    
    function testCannotCreateWithZeroRecipient() public {
        vm.expectRevert("SimpleEscrowFactory: recipient cannot be zero address");
        factory.createEscrow(
            address(token),
            alice,
            address(0),
            hashlock,
            timelock,
            salt
        );
    }
    
    function testCannotCreateWithZeroHashlock() public {
        vm.expectRevert("SimpleEscrowFactory: hashlock cannot be zero");
        factory.createEscrow(
            address(token),
            alice,
            bob,
            bytes32(0),
            timelock,
            salt
        );
    }
    
    function testCannotCreateWithPastTimelock() public {
        vm.expectRevert("SimpleEscrowFactory: timelock must be in future");
        factory.createEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            block.timestamp - 1,
            salt
        );
    }
    
    // ========== View Function Tests ==========
    
    function testGetEscrowDetails() public {
        // Create escrow
        address escrowAddress = factory.createEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        // Get details through factory
        SimpleEscrow.EscrowDetails memory details = factory.getEscrowDetails(escrowAddress);
        
        assertEq(details.token, address(token));
        assertEq(details.sender, alice);
        assertEq(details.recipient, bob);
        assertEq(details.hashlock, hashlock);
        assertEq(details.timelock, timelock);
        assertFalse(details.funded);
    }
    
    function testGetEscrowDetailsNotDeployed() public {
        vm.expectRevert("SimpleEscrowFactory: escrow not deployed by this factory");
        factory.getEscrowDetails(address(0x999));
    }
    
    function testIsEscrowDeployed() public {
        address escrowAddress = factory.createEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        
        assertTrue(factory.isEscrowDeployed(escrowAddress));
        assertFalse(factory.isEscrowDeployed(address(0x999)));
    }
    
    function testGetEscrowBytecode() public {
        bytes memory bytecode = factory.getEscrowBytecode(
            address(token),
            alice,
            bob,
            hashlock,
            timelock
        );
        
        // Verify bytecode starts with SimpleEscrow creation code
        assertTrue(bytecode.length > 0);
        
        // The bytecode should be deterministic
        bytes memory bytecode2 = factory.getEscrowBytecode(
            address(token),
            alice,
            bob,
            hashlock,
            timelock
        );
        
        assertEq(keccak256(bytecode), keccak256(bytecode2));
    }
    
    // ========== Gas Measurement Tests ==========
    
    function skip_testGasCostsForCreation() public {
        uint256 gasStart = gasleft();
        address escrowAddress = factory.createEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt
        );
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Escrow creation gas:", gasUsed);
        assertTrue(gasUsed < 1000000, "Creation gas exceeds 1M");
        assertTrue(escrowAddress != address(0));
    }
    
    function testGasCostsForBatchCreation() public {
        SimpleEscrowFactory.EscrowParams[] memory params = new SimpleEscrowFactory.EscrowParams[](5);
        
        for (uint i = 0; i < 5; i++) {
            params[i] = SimpleEscrowFactory.EscrowParams({
                token: address(token),
                sender: alice,
                recipient: bob,
                hashlock: keccak256(abi.encode("hash", i)),
                timelock: timelock + i * 1 hours,
                salt: keccak256(abi.encode("salt", i))
            });
        }
        
        uint256 gasStart = gasleft();
        factory.batchCreateEscrows(params);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Batch creation gas for 5 escrows:", gasUsed);
        console.log("Average gas per escrow:", gasUsed / 5);
    }
    
    // ========== Funding Flow Tests ==========
    
    function testCreateWithFundingOnlySenderCanFund() public {
        vm.expectRevert("SimpleEscrowFactory: only sender can create and fund");
        vm.prank(bob);
        factory.createEscrowWithFunding(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt,
            amount
        );
    }
    
    function testCreateWithFundingZeroAmount() public {
        vm.expectRevert("SimpleEscrowFactory: amount must be greater than 0");
        vm.prank(alice);
        factory.createEscrowWithFunding(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt,
            0
        );
    }
    
    function testCreateWithFundingInsufficientBalance() public {
        uint256 tooMuch = amount * 100;
        
        vm.expectRevert();
        vm.prank(alice);
        factory.createEscrowWithFunding(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt,
            tooMuch
        );
    }
    
    // ========== Integration Scenario Tests ==========
    
    function testCompleteAtomicSwapFlow() public {
        // Alice creates and funds escrow
        vm.prank(alice);
        address escrowAddress = factory.createEscrowWithFunding(
            address(token),
            alice,
            bob,
            hashlock,
            timelock,
            salt,
            amount
        );
        
        SimpleEscrow escrow = SimpleEscrow(escrowAddress);
        assertTrue(escrow.funded());
        
        // Bob withdraws with secret
        vm.prank(bob);
        escrow.withdraw(secret);
        
        // Verify completion
        assertTrue(escrow.withdrawn());
        assertEq(escrow.preimage(), secret);
        assertEq(token.balanceOf(bob), amount);
    }
    
    function testMultipleEscrowsWithSameSenderRecipient() public {
        // Create multiple escrows between same parties but different parameters
        bytes32[] memory salts = new bytes32[](3);
        address[] memory escrows = new address[](3);
        
        for (uint i = 0; i < 3; i++) {
            salts[i] = keccak256(abi.encode("unique-salt", i));
            escrows[i] = factory.createEscrow(
                address(token),
                alice,
                bob,
                keccak256(abi.encode("unique-hash", i)),
                timelock + i * 1 hours,
                salts[i]
            );
        }
        
        // All should be different addresses
        assertTrue(escrows[0] != escrows[1]);
        assertTrue(escrows[1] != escrows[2]);
        assertTrue(escrows[0] != escrows[2]);
        
        // All should be deployed
        for (uint i = 0; i < 3; i++) {
            assertTrue(factory.deployedEscrows(escrows[i]));
        }
        
        assertEq(factory.escrowCount(), 3);
    }
}