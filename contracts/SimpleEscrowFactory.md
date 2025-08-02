# SimpleEscrowFactory Contract Specification

## Overview
SimpleEscrowFactory deploys SimpleEscrow contracts with deterministic addresses using CREATE2. It supports both direct creation and creation triggered by 1inch orders, maintaining compatibility while offering simplicity.

## Design Principles
- Deterministic deployment for cross-chain address prediction
- Dual creation paths: direct and 1inch-compatible
- Minimal validation and overhead
- Gas-efficient deployment pattern
- Event-driven for easy monitoring

## Contract State Variables

```solidity
mapping(address => bool) public deployedEscrows;  // Track deployed escrows
address public oneInchAdapter;                    // Optional 1inch adapter address
uint256 public escrowCount;                       // Total escrows created
```

## Constructor
```solidity
constructor(address _oneInchAdapter)
```

### Parameters
- `_oneInchAdapter`: Address of OneInchAdapter contract (can be zero for standalone deployment)

## Core Functions

### createEscrow
Direct escrow creation without 1inch dependency.

```solidity
function createEscrow(
    address token,
    address sender,
    address recipient,
    bytes32 hashlock,
    uint256 timelock,
    bytes32 salt
) external returns (address escrow)
```

**Parameters**:
- `token`: ERC20 token for the swap
- `sender`: Address that will fund the escrow
- `recipient`: Address that can withdraw with preimage
- `hashlock`: Hash of the secret
- `timelock`: Refund timestamp
- `salt`: Salt for CREATE2 deployment

**Access Control**: Public - anyone can create escrows

**Effects**:
- Deploys new SimpleEscrow with CREATE2
- Marks escrow as deployed
- Increments escrow count
- Emits EscrowCreated event

**Returns**: Address of deployed escrow

### createEscrowWithFunding
Creates and immediately funds an escrow (convenience function).

```solidity
function createEscrowWithFunding(
    address token,
    address sender,
    address recipient,
    bytes32 hashlock,
    uint256 timelock,
    bytes32 salt,
    uint256 amount
) external returns (address escrow)
```

**Additional Parameter**:
- `amount`: Amount to fund the escrow with

**Requirements**:
- Caller must have approved factory for token transfer
- Caller must be the sender

**Effects**:
- Creates escrow via createEscrow
- Transfers tokens from caller to escrow
- Calls fund() on the escrow

### createEscrowFrom1inchOrder
Creates escrow from 1inch order data (compatibility layer).

```solidity
function createEscrowFrom1inchOrder(
    IOrderMixin.Order calldata order,
    bytes calldata extension,
    uint256 makingAmount
) external returns (address escrow)
```

**Parameters**:
- `order`: 1inch order struct
- `extension`: Encoded atomic swap parameters
- `makingAmount`: Amount being swapped

**Access Control**: Only callable by oneInchAdapter

**Extension Decoding**:
```solidity
(bytes32 hashlock, address recipient, uint256 timeoutDuration, bytes32 salt) = 
    abi.decode(extension, (bytes32, address, uint256, bytes32));
```

**Effects**:
- Extracts parameters from order and extension
- Creates escrow using order.makerAsset and order.maker
- Uses current timestamp + timeoutDuration for timelock

### batchCreateEscrows
Creates multiple escrows in one transaction (gas optimization).

```solidity
function batchCreateEscrows(
    EscrowParams[] calldata params
) external returns (address[] memory escrows)
```

**Struct Definition**:
```solidity
struct EscrowParams {
    address token;
    address sender;
    address recipient;
    bytes32 hashlock;
    uint256 timelock;
    bytes32 salt;
}
```

**Effects**:
- Deploys multiple escrows in single transaction
- Returns array of deployed addresses

## View Functions

### computeEscrowAddress
Calculates escrow address before deployment (critical for cross-chain coordination).

```solidity
function computeEscrowAddress(
    address token,
    address sender,
    address recipient,
    bytes32 hashlock,
    uint256 timelock,
    bytes32 salt
) public view returns (address)
```

**Returns**: Deterministic address where escrow will be deployed

**Implementation**:
```solidity
bytes memory bytecode = abi.encodePacked(
    type(SimpleEscrow).creationCode,
    abi.encode(token, sender, recipient, hashlock, timelock)
);

bytes32 hash = keccak256(
    abi.encodePacked(
        bytes1(0xff),
        address(this),
        salt,
        keccak256(bytecode)
    )
);

return address(uint160(uint256(hash)));
```

### isEscrowDeployed
Checks if an escrow has been deployed at given address.

```solidity
function isEscrowDeployed(address escrow) external view returns (bool)
```

### getEscrowDetails
Fetches details from a deployed escrow (convenience function).

```solidity
function getEscrowDetails(address escrow) external view returns (EscrowDetails memory)
```

## Events

### EscrowCreated
```solidity
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
```

### EscrowCreatedFrom1inch
```solidity
event EscrowCreatedFrom1inch(
    address indexed escrow,
    bytes32 indexed orderHash,
    address indexed maker,
    uint256 makingAmount
);
```

## Access Control

### setOneInchAdapter
Allows updating the 1inch adapter address.

```solidity
function setOneInchAdapter(address _oneInchAdapter) external onlyOwner
```

**Note**: Consider if this should be immutable for security

## Security Considerations

### CREATE2 Security
- Salt must include chain-specific data to prevent cross-chain replay
- Validate that computed address matches deployed address
- Check that escrow doesn't already exist at computed address

### Parameter Validation
- Ensure timelock is in future
- Validate non-zero addresses
- Check hashlock is not zero

### Reentrancy
- No external calls in create functions (except deployment)
- State updates before external calls in funding variant

## Gas Optimizations

### Deployment Optimization
- Pre-compute bytecode hash as constant if possible
- Batch deployments for multiple escrows
- Consider minimal proxy pattern for very frequent deployments

### Event Optimization
- Use indexed parameters for commonly filtered fields
- Pack data efficiently in events

## Integration Patterns

### Cross-Chain Deployment
```solidity
// Chain A
bytes32 salt = keccak256(abi.encode(userSalt, block.chainid, "source"));
address escrowA = factory.createEscrow(..., salt);

// Chain B - predict address first
bytes32 salt = keccak256(abi.encode(userSalt, block.chainid, "destination"));
address predictedB = factory.computeEscrowAddress(..., salt);
// Send predictedB to Chain A before deployment
```

### With 1inch Integration
```solidity
// OneInchAdapter calls factory
address escrow = factory.createEscrowFrom1inchOrder(order, extension, amount);
// Then funds the escrow
```

### Direct Integration
```solidity
// Create and fund in separate transactions
address escrow = factory.createEscrow(...);
token.approve(escrow, amount);
SimpleEscrow(escrow).fund(amount);

// Or use convenience function
address escrow = factory.createEscrowWithFunding(..., amount);
```

## Testing Checklist

- [ ] Deterministic address calculation accuracy
- [ ] CREATE2 deployment with various parameters
- [ ] Salt uniqueness enforcement
- [ ] 1inch order parameter extraction
- [ ] Batch creation gas efficiency
- [ ] Cross-chain address prediction
- [ ] Access control for 1inch adapter
- [ ] Event emission correctness
- [ ] Edge cases (zero addresses, past timelock, etc.)

## Deployment Considerations

### Multi-Chain Deployment
1. Deploy factory to same address on all chains (using same deployer nonce)
2. Or use CREATE2 factory deployer for consistent addresses
3. Verify bytecode is identical across chains
4. Test address prediction across all target chains

### Configuration
- Set 1inch adapter after deployment if needed
- Consider making adapter immutable in production
- Document salt generation strategy for integrators

### Monitoring
- Index EscrowCreated events for tracking
- Monitor for failed deployments (shouldn't happen with CREATE2)
- Track gas costs for optimization opportunities