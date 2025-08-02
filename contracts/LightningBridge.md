# LightningBridge Contract Specification

## Overview
LightningBridge enables atomic swaps between EVM chains and the Bitcoin Lightning Network. It coordinates HTLCs across both systems using the same preimage, enabling trustless exchanges between any EVM asset and Bitcoin Lightning payments.

## Design Principles
- Same preimage unlocks both Lightning and EVM HTLCs
- Minimal on-chain footprint for Lightning coordination
- Event-driven architecture for off-chain monitoring
- Support for both EVM→Lightning and Lightning→EVM flows
- Gas-efficient state management

## Contract Architecture

### Core State Structure
```solidity
struct LightningSwap {
    // EVM side details
    address evmEscrow;        // SimpleEscrow contract address
    address initiator;        // Who started the swap
    address evmToken;         // Token being swapped on EVM
    uint256 evmAmount;        // Amount in EVM token
    
    // Lightning side details
    bytes32 paymentHash;      // Same as hashlock in SimpleEscrow
    uint256 satoshiAmount;    // Amount in satoshis
    string lightningInvoice;  // BOLT11 invoice (set off-chain)
    
    // Swap state
    SwapState state;          // Current state of swap
    uint256 createdAt;        // Timestamp of creation
    bytes32 preimage;         // Revealed after completion
}

enum SwapState {
    None,
    EVMFunded,      // EVM escrow is funded
    InvoiceCreated, // Lightning invoice created
    LightningPaid,  // Lightning payment confirmed
    Completed,      // Preimage revealed, swap complete
    Expired         // Swap timed out
}
```

### State Variables
```solidity
mapping(bytes32 => LightningSwap) public swaps;  // paymentHash => swap details
mapping(address => bytes32[]) public userSwaps;  // user => their swap hashes

SimpleEscrowFactory public immutable escrowFactory;
address public resolver;                          // Authorized resolver address
uint256 public swapCounter;                       // Total swaps created

// Configuration
uint256 public minSatoshiAmount = 1000;          // Minimum Lightning amount
uint256 public maxSatoshiAmount = 10_000_000;    // Maximum Lightning amount
uint256 public swapTimeout = 3600;               // Default 1 hour timeout
```

## Core Functions

### initiateEVMToLightning
Start a swap from EVM tokens to Lightning payment.

```solidity
function initiateEVMToLightning(
    address evmToken,
    uint256 evmAmount,
    uint256 satoshiAmount,
    bytes32 paymentHash,
    uint256 timelock
) external returns (address escrow)
```

**Flow**:
1. Create SimpleEscrow for EVM tokens
2. Register swap in bridge contract
3. Emit event for resolver to create Lightning invoice
4. User funds the escrow
5. Resolver monitors and completes swap

**Parameters**:
- `evmToken`: ERC20 token to swap
- `evmAmount`: Amount of tokens to lock
- `satoshiAmount`: Expected Lightning payment
- `paymentHash`: Hash of the preimage (used in both systems)
- `timelock`: Expiry time for the swap

**Returns**: Address of created SimpleEscrow

### initiateLightningToEVM
Start a swap from Lightning payment to EVM tokens.

```solidity
function initiateLightningToEVM(
    string calldata lightningInvoice,
    address evmToken,
    uint256 evmAmount,
    address recipient
) external returns (bytes32 paymentHash)
```

**Flow**:
1. Decode Lightning invoice to extract payment hash
2. Register swap in bridge contract
3. Resolver creates matching EVM escrow
4. User pays Lightning invoice
5. Bridge uses revealed preimage to unlock EVM escrow

**Parameters**:
- `lightningInvoice`: BOLT11 Lightning invoice
- `evmToken`: Token to receive on EVM
- `evmAmount`: Amount to receive
- `recipient`: Who receives the EVM tokens

### setLightningInvoice
Resolver sets the Lightning invoice after creation.

```solidity
function setLightningInvoice(
    bytes32 paymentHash,
    string calldata invoice
) external onlyResolver
```

**Access**: Only authorized resolver

### confirmLightningPayment
Resolver confirms Lightning payment and reveals preimage.

```solidity
function confirmLightningPayment(
    bytes32 paymentHash,
    bytes32 preimage
) external onlyResolver
```

**Effects**:
- Validates preimage matches payment hash
- Updates swap state to LightningPaid
- Stores preimage for EVM withdrawal
- Emits LightningPaymentConfirmed event

### completeSwap
Finalize swap after both sides are settled.

```solidity
function completeSwap(bytes32 paymentHash) external
```

**Requirements**:
- Swap must be in LightningPaid state
- Caller must be initiator or resolver

**Effects**:
- Updates state to Completed
- Emits SwapCompleted event

### cancelExpiredSwap
Clean up expired swaps.

```solidity
function cancelExpiredSwap(bytes32 paymentHash) external
```

**Requirements**:
- Swap must be past expiry time
- Swap not yet completed

## View Functions

### getSwapDetails
```solidity
function getSwapDetails(bytes32 paymentHash) 
    external view returns (LightningSwap memory)
```

### getUserSwaps
```solidity
function getUserSwaps(address user) 
    external view returns (bytes32[] memory)
```

### calculatePaymentHash
```solidity
function calculatePaymentHash(bytes32 preimage) 
    external pure returns (bytes32)
```

### decodeInvoice
```solidity
function decodeInvoice(string calldata invoice) 
    external pure returns (
        bytes32 paymentHash,
        uint256 amount,
        uint256 expiry
    )
```

## Events

### EVMToLightningInitiated
```solidity
event EVMToLightningInitiated(
    bytes32 indexed paymentHash,
    address indexed initiator,
    address evmEscrow,
    uint256 evmAmount,
    uint256 satoshiAmount
);
```

### LightningToEVMInitiated
```solidity
event LightningToEVMInitiated(
    bytes32 indexed paymentHash,
    address indexed recipient,
    string lightningInvoice,
    uint256 evmAmount
);
```

### LightningInvoiceSet
```solidity
event LightningInvoiceSet(
    bytes32 indexed paymentHash,
    string invoice
);
```

### LightningPaymentConfirmed
```solidity
event LightningPaymentConfirmed(
    bytes32 indexed paymentHash,
    bytes32 preimage
);
```

### SwapCompleted
```solidity
event SwapCompleted(
    bytes32 indexed paymentHash,
    address indexed initiator,
    uint256 evmAmount,
    uint256 satoshiAmount
);
```

## Access Control

### onlyResolver
```solidity
modifier onlyResolver() {
    require(msg.sender == resolver, "Not authorized resolver");
    _;
}
```

### setResolver
```solidity
function setResolver(address _resolver) external onlyOwner
```

## Security Considerations

### Preimage Security
- Never store preimage before Lightning payment
- Validate preimage hash before accepting
- Use same hash algorithm as Lightning (SHA256)

### Timeout Management
- EVM escrow timeout must be longer than Lightning invoice expiry
- Add buffer for network delays
- Allow manual expiry handling

### Amount Validation
- Verify satoshi amounts are within acceptable range
- Consider exchange rate mechanisms
- Protect against dust attacks

### State Transitions
- Enforce strict state machine
- Prevent replay attacks
- Handle edge cases (partial payments, etc.)

## Integration Architecture

### Required Off-Chain Components

1. **Lightning Node Manager**
   - Creates invoices with specific payment hashes
   - Monitors for incoming payments
   - Extracts preimages from settled payments

2. **Bridge Resolver Service**
   - Monitors blockchain events
   - Manages Lightning node
   - Coordinates cross-system settlements
   - Handles exchange rates

3. **Price Oracle (Optional)**
   - Provides EVM token to BTC rates
   - Enables automatic amount calculation

### Flow Diagrams

#### EVM → Lightning Flow
```
1. User locks EVM tokens in SimpleEscrow
2. Bridge registers swap with payment hash
3. Resolver creates Lightning invoice
4. User pays Lightning invoice
5. Lightning node reveals preimage
6. Resolver can claim EVM tokens (optional)
```

#### Lightning → EVM Flow
```
1. Resolver creates Lightning invoice
2. Bridge registers expected EVM delivery
3. Resolver locks EVM tokens in escrow
4. User pays Lightning invoice
5. Preimage revealed to resolver
6. User claims EVM tokens with preimage
```

## Gas Optimization

### Storage Packing
```solidity
struct LightningSwap {
    address evmEscrow;        // slot 1
    address initiator;        // slot 2 (with 12 bytes)
    SwapState state;          // slot 2 (1 byte)
    uint32 createdAt;         // slot 2 (4 bytes)
    address evmToken;         // slot 3
    uint128 evmAmount;        // slot 4 (with satoshiAmount)
    uint128 satoshiAmount;    // slot 4
    bytes32 paymentHash;      // slot 5
    bytes32 preimage;         // slot 6
    // Lightning invoice stored separately in mapping
}
```

### Event Optimization
- Index only essential fields
- Pack data efficiently
- Emit minimal necessary information

## Testing Considerations

### Unit Tests
- [ ] Payment hash calculation
- [ ] State transition validation
- [ ] Timeout handling
- [ ] Access control
- [ ] Amount validations

### Integration Tests
- [ ] Full EVM to Lightning flow
- [ ] Full Lightning to EVM flow
- [ ] Timeout and refund scenarios
- [ ] Multiple concurrent swaps
- [ ] Edge cases (zero amounts, etc.)

### Lightning Testing
- [ ] Use Lightning regtest network
- [ ] Test with real invoice creation
- [ ] Verify preimage revelation
- [ ] Test payment failures

## Configuration for Hackathon

### Quick Setup Values
```solidity
minSatoshiAmount = 1000;        // ~$0.50
maxSatoshiAmount = 1_000_000;   // ~$500
swapTimeout = 600;              // 10 minutes for demo
```

### Demo Scenarios
1. **Simple EVM → Lightning**: Lock USDC, receive sats
2. **Simple Lightning → EVM**: Pay invoice, receive tokens
3. **Cross-chain via Lightning**: ETH on Ethereum → Lightning → MATIC on Polygon

## Future Enhancements

### Production Features
- Multi-resolver support
- Automatic market making
- Fee mechanisms
- Batch swap support
- Advanced routing

### Security Enhancements
- Decentralized resolver network
- Stake-based security
- Reputation system
- Insurance mechanisms