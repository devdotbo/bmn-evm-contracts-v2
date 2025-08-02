# OneInchAdapter Contract Specification

## Overview
OneInchAdapter serves as the compatibility bridge between 1inch Limit Order Protocol and the simplified atomic swap system. It implements the necessary interfaces to receive callbacks from 1inch while triggering simplified escrow creation.

## Design Principles
- Minimal implementation of 1inch requirements
- Stateless design - no storage of order data
- Direct forwarding to SimpleEscrowFactory
- Gas-efficient parameter extraction
- Maintains full backward compatibility

## Inheritance Structure
```solidity
contract OneInchAdapter is BaseExtension
```

BaseExtension provides:
- IPreInteraction (not used but available)
- IPostInteraction (primary callback interface)
- IAmountGetter (stub implementation)

## Contract State Variables

```solidity
SimpleEscrowFactory public immutable factory;
address public immutable limitOrderProtocol;
```

## Constructor
```solidity
constructor(
    address _factory,
    address _limitOrderProtocol
)
```

### Parameters
- `_factory`: SimpleEscrowFactory contract address
- `_limitOrderProtocol`: 1inch Limit Order Protocol address

### Validation
- Both addresses must be non-zero
- Factory must implement expected interface

## Core Functions

### _postInteraction (Override)
Main callback from 1inch protocol after order execution.

```solidity
function _postInteraction(
    IOrderMixin.Order calldata order,
    bytes calldata extension,
    bytes32 orderHash,
    address taker,
    uint256 makingAmount,
    uint256 takingAmount,
    uint256 remainingMakingAmount,
    bytes calldata extraData
) internal override
```

**Called By**: 1inch Limit Order Protocol

**Parameters from 1inch**:
- `order`: Complete order data including maker, assets, amounts
- `extension`: Custom data containing atomic swap parameters
- `orderHash`: Unique identifier for the order
- `taker`: Address that filled the order
- `makingAmount`: Amount of maker asset in this fill
- `takingAmount`: Amount of taker asset in this fill
- `remainingMakingAmount`: Remaining unfilled amount
- `extraData`: Additional data (usually empty)

**Extension Format**:
```solidity
struct AtomicSwapData {
    bytes32 hashlock;        // Hash of the secret
    address crossChainRecipient;  // Recipient on destination chain
    uint256 timeoutDuration; // Timeout in seconds from now
    uint256 destinationChainId;   // Target chain for swap
    bytes32 escrowSalt;      // Salt for deterministic deployment
}
```

**Implementation Flow**:
1. Decode extension data to extract atomic swap parameters
2. Calculate timelock as `block.timestamp + timeoutDuration`
3. Call factory to create escrow
4. Transfer tokens from adapter to escrow
5. Call fund() on the escrow
6. Emit events for monitoring

### decodeExtension
Helper function to decode extension data.

```solidity
function decodeExtension(
    bytes calldata extension
) public pure returns (
    bytes32 hashlock,
    address recipient,
    uint256 timeoutDuration,
    uint256 destinationChainId,
    bytes32 salt
)
```

**Visibility**: Public for transparency and testing

### _validateOrder
Internal validation of order parameters.

```solidity
function _validateOrder(
    IOrderMixin.Order calldata order,
    uint256 makingAmount
) internal view
```

**Checks**:
- Order maker is not zero address
- Making amount is greater than zero
- Maker asset is a valid token address
- Order allows post-interaction (via makerTraits)

## Integration Functions

### rescueTokens
Emergency function to rescue stuck tokens.

```solidity
function rescueTokens(
    address token,
    address to,
    uint256 amount
) external onlyOwner
```

**Use Case**: If tokens get stuck due to failed funding

### pause/unpause
Circuit breaker for emergency situations.

```solidity
function pause() external onlyOwner
function unpause() external onlyOwner
```

**Effect**: Prevents _postInteraction execution when paused

## Events

### AtomicSwapInitiated
```solidity
event AtomicSwapInitiated(
    bytes32 indexed orderHash,
    address indexed escrow,
    address indexed maker,
    address taker,
    bytes32 hashlock,
    uint256 amount
);
```

### AtomicSwapFunded
```solidity
event AtomicSwapFunded(
    address indexed escrow,
    uint256 amount,
    address token
);
```

### ExtensionDecoded
```solidity
event ExtensionDecoded(
    bytes32 indexed orderHash,
    bytes32 hashlock,
    address recipient,
    uint256 destinationChainId
);
```

## Security Considerations

### Access Control
- Only 1inch protocol can trigger _postInteraction
- Modifier: `onlyLimitOrderProtocol`
- Owner functions for emergency operations

### Token Handling
- Use SafeERC20 for all token operations
- Approve escrow before funding
- Check token balance before and after transfers

### Validation
- Validate extension data format
- Ensure timelock is reasonable (not too far in future)
- Check that escrow was successfully created

### Reentrancy
- Mark state before external calls
- Use reentrancy guard if holding state

## Error Handling

### Custom Errors
```solidity
error InvalidExtensionData();
error EscrowCreationFailed();
error TokenTransferFailed();
error OrderValidationFailed();
error AdapterPaused();
```

### Revert Conditions
- Invalid extension data format
- Failed escrow creation
- Insufficient token balance
- Failed token transfer to escrow
- Contract is paused

## Gas Optimizations

### Extension Decoding
- Decode only once and pass values
- Use memory for intermediate values
- Pack struct values efficiently

### Token Transfers
- Single approval before transfer
- Batch approve + transfer in one call if possible

## Integration with 1inch

### Order Creation (Off-chain)
```javascript
// Create order with atomic swap extension
const extension = encodeExtension({
    hashlock: keccak256(secret),
    crossChainRecipient: bobAddress,
    timeoutDuration: 3600, // 1 hour
    destinationChainId: 137, // Polygon
    escrowSalt: generateSalt()
});

const order = {
    salt: BigInt(keccak256(extension)),
    maker: aliceAddress,
    receiver: ZERO_ADDRESS,
    makerAsset: USDC_ADDRESS,
    takerAsset: USDT_ADDRESS,
    makingAmount: parseUnits("100", 6),
    takingAmount: parseUnits("100", 6),
    makerTraits: buildMakerTraits({
        allowPartialFill: false,
        needPostInteraction: true,
        extension: adapterAddress
    })
};
```

### Order Execution Flow
1. User creates order with extension data
2. Order is signed and submitted to 1inch
3. Taker fills order through 1inch protocol
4. 1inch transfers tokens and calls adapter
5. Adapter creates and funds escrow
6. Atomic swap can proceed on both chains

## Testing Scenarios

### Unit Tests
- [ ] Extension decoding with valid data
- [ ] Extension decoding with invalid data
- [ ] Order validation logic
- [ ] Access control (only LOP can call)
- [ ] Pause/unpause functionality

### Integration Tests
- [ ] Full flow from 1inch order to escrow creation
- [ ] Partial fill handling
- [ ] Multiple fills of same order
- [ ] Token transfer failures
- [ ] Factory creation failures
- [ ] Gas consumption measurement

### Edge Cases
- [ ] Zero amounts
- [ ] Past timelocks
- [ ] Invalid token addresses
- [ ] Reentrancy attempts
- [ ] Malformed extension data

## Deployment Checklist

1. Deploy SimpleEscrowFactory first
2. Deploy OneInchAdapter with factory address
3. Set adapter address in factory (if needed)
4. Verify both contracts on Etherscan
5. Test with small amount order
6. Monitor events for proper emission

## Monitoring and Maintenance

### Key Metrics
- Number of atomic swaps initiated
- Success rate of escrow creation
- Average gas cost per swap
- Token types being swapped

### Alerts
- Failed escrow creations
- Stuck tokens in adapter
- Unusual timeout durations
- Pause events

### Maintenance Tasks
- Monitor for 1inch protocol updates
- Update integration if 1inch changes
- Clear any stuck tokens
- Review gas optimization opportunities