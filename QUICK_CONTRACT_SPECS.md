# Quick Contract Specifications for Hackathon

## 🎯 Goal: Minimal Viable Atomic Swap with 1inch Compatibility

### Core Design Principles
- **KISS**: Keep It Simple, Stupid
- **Works > Perfect**: Focus on functionality
- **1inch Compatible**: Maintain interface compatibility
- **Lightning Ready**: Prepare for Lightning integration

## 📄 Contract 1: SimpleEscrow.sol

### Purpose
Single contract that handles both source and destination escrow logic. No complex phases, just lock → withdraw/refund.

### Storage Variables
```solidity
address public immutable token;
address public immutable sender;
address public immutable recipient;
bytes32 public immutable hashlock;
uint256 public immutable timelock;

uint256 public amount;
bool public funded;
bool public withdrawn;
bool public refunded;
bytes32 public preimage;
```

### Functions
```solidity
constructor(address _token, address _sender, address _recipient, bytes32 _hashlock, uint256 _timelock)

function fund(uint256 _amount) external
    - Only sender can fund
    - Transfer tokens to escrow
    - Set funded = true

function withdraw(bytes32 _preimage) external
    - Verify: keccak256(abi.encode(_preimage)) == hashlock
    - Require: funded && !withdrawn && !refunded
    - Require: block.timestamp < timelock
    - Transfer tokens to recipient
    - Store preimage for others to see
    - Set withdrawn = true

function refund() external
    - Require: funded && !withdrawn && !refunded  
    - Require: block.timestamp >= timelock
    - Require: msg.sender == sender
    - Transfer tokens back to sender
    - Set refunded = true

function getDetails() view returns (...)
    - Return all escrow details for easy querying
```

### Events
```solidity
event EscrowFunded(address indexed sender, uint256 amount);
event EscrowWithdrawn(address indexed recipient, bytes32 preimage);
event EscrowRefunded(address indexed sender);
```

## 📄 Contract 2: SimpleEscrowFactory.sol

### Purpose
Deploy escrows with deterministic addresses. Support both direct creation and 1inch order creation.

### Storage Variables
```solidity
mapping(address => bool) public deployedEscrows;
address public oneInchAdapter; // Optional
```

### Functions
```solidity
function createEscrow(
    address token,
    address sender, 
    address recipient,
    bytes32 hashlock,
    uint256 timelock,
    bytes32 salt
) external returns (address escrow)
    - Deploy SimpleEscrow with CREATE2
    - Use salt for deterministic address
    - Mark as deployed
    - Emit event

function createEscrowFrom1inchOrder(
    IOrderMixin.Order calldata order,
    bytes calldata extension
) external returns (address escrow)
    - Only callable by OneInchAdapter
    - Extract atomic swap params from extension
    - Call createEscrow internally

function computeEscrowAddress(
    address token,
    address sender,
    address recipient,
    bytes32 hashlock,
    uint256 timelock,
    bytes32 salt
) external view returns (address)
    - Calculate CREATE2 address
    - Same on all chains
```

### Events
```solidity
event EscrowCreated(
    address indexed escrow,
    address indexed sender,
    address indexed recipient,
    bytes32 hashlock,
    uint256 chainId
);
```

## 📄 Contract 3: OneInchAdapter.sol

### Purpose
Bridge between 1inch Limit Order Protocol and our atomic swaps. Minimal implementation for hackathon.

### Implementation
```solidity
contract OneInchAdapter is BaseExtension {
    SimpleEscrowFactory public immutable factory;
    
    constructor(address _factory, address _limitOrderProtocol) {
        factory = SimpleEscrowFactory(_factory);
    }
    
    function _postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal override {
        // Decode extension data
        (bytes32 hashlock, address recipient, uint256 timeout, bytes32 salt) = 
            abi.decode(extension, (bytes32, address, uint256, bytes32));
        
        // Create escrow
        address escrow = factory.createEscrow(
            order.makerAsset,
            order.maker,
            recipient,
            hashlock,
            block.timestamp + timeout,
            salt
        );
        
        // Fund escrow (tokens already transferred to adapter)
        IERC20(order.makerAsset).approve(escrow, makingAmount);
        SimpleEscrow(escrow).fund(makingAmount);
    }
}
```

## 📄 Contract 4: LightningAdapter.sol (Phase 2)

### Purpose
Bridge between EVM escrows and Lightning Network HTLCs.

### Core Concept
```solidity
contract LightningAdapter {
    struct LightningSwap {
        address evmEscrow;
        bytes32 paymentHash;  // Same as hashlock
        uint256 satoshiAmount;
        address recipient;
        bool settled;
    }
    
    mapping(bytes32 => LightningSwap) public lightningSwaps;
    
    function initiateLightningSwap(
        address evmEscrow,
        bytes32 paymentHash,
        uint256 satoshiAmount,
        address recipient
    ) external {
        // Register Lightning swap
        // Emit event for Lightning node to create invoice
    }
    
    function settleLightningSwap(
        bytes32 paymentHash,
        bytes32 preimage
    ) external {
        // Called when Lightning payment completes
        // Verify preimage matches hash
        // Mark as settled
        // Now can withdraw from EVM escrow
    }
}
```

## 🔧 Deployment Scripts

### Deploy.s.sol
```solidity
contract DeploySimple is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        
        // Deploy factory
        SimpleEscrowFactory factory = new SimpleEscrowFactory();
        
        // Deploy 1inch adapter (if needed)
        if (vm.envBool("DEPLOY_1INCH_ADAPTER")) {
            address lop = vm.envAddress("LIMIT_ORDER_PROTOCOL");
            OneInchAdapter adapter = new OneInchAdapter(address(factory), lop);
        }
        
        vm.stopBroadcast();
    }
}
```

## 🧪 Quick Test Scenarios

### Test 1: Direct Atomic Swap
```solidity
function testDirectSwap() public {
    // Alice creates escrow
    address escrow = factory.createEscrow(...);
    
    // Alice funds
    SimpleEscrow(escrow).fund(100e18);
    
    // Bob withdraws with preimage
    SimpleEscrow(escrow).withdraw(preimage);
    
    // Check Bob received funds
    assertEq(token.balanceOf(bob), 100e18);
}
```

### Test 2: 1inch Order Integration
```solidity
function test1inchIntegration() public {
    // Create 1inch order with extension
    IOrderMixin.Order memory order = ...;
    bytes memory extension = abi.encode(hashlock, bob, timeout, salt);
    
    // Fill order (triggers adapter)
    limitOrderProtocol.fillOrder(order, signature, ...);
    
    // Verify escrow created and funded
    address escrow = factory.computeEscrowAddress(...);
    assertTrue(SimpleEscrow(escrow).funded());
}
```

### Test 3: Timeout Refund
```solidity
function testTimeout() public {
    // Create and fund escrow
    address escrow = factory.createEscrow(...);
    SimpleEscrow(escrow).fund(100e18);
    
    // Fast forward past timeout
    vm.warp(block.timestamp + 2 hours);
    
    // Alice refunds
    SimpleEscrow(escrow).refund();
    
    // Check Alice got funds back
    assertEq(token.balanceOf(alice), 100e18);
}
```

## 🚀 Integration with Resolver

### Required Updates in bmn-evm-resolver:

1. **Update ABIs** to match new contracts
2. **Simplify monitoring** - just watch for EscrowCreated events
3. **Update execution logic**:
   ```typescript
   // Old: Complex multi-phase logic
   // New: Simple three steps
   async executeSwap(escrowAddress: string) {
     // 1. Create corresponding escrow on other chain
     // 2. Fund both escrows
     // 3. Withdraw with preimage
   }
   ```

## ⚡ Lightning Network Preparation

### What we need:
1. **Payment Hash Compatibility**: Use same hash for EVM and Lightning
2. **Amount Conversion**: Handle satoshi ↔ wei conversion
3. **Node Integration**: Connect to LND/CLN via REST/gRPC
4. **Invoice Management**: Create and monitor HTLC invoices

### Lightning Flow:
```
Alice (EVM) → Lightning Network → Bob (EVM)
     ↓              ↓                ↓
SimpleEscrow   HTLC Invoice    SimpleEscrow
  (Chain A)     (Bitcoin)       (Chain B)
```

## 📋 Hackathon Checklist

- [ ] Deploy SimpleEscrow implementation
- [ ] Deploy SimpleEscrowFactory
- [ ] Test direct escrow creation
- [ ] Deploy OneInchAdapter
- [ ] Test 1inch order integration
- [ ] Update resolver to work with new contracts
- [ ] Complete end-to-end atomic swap
- [ ] Add Lightning adapter
- [ ] Demo Lightning integration

Remember: **Focus on working demo, not perfect code!**